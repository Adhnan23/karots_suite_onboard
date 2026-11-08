import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/suite/client.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_shop.dart';

void main() {
  sqfliteFfiInit();
  late FakeShop shop;
  late Db db;
  late Shop s;
  var restocks = 0;
  var failSecondRestock = false;

  setUp(() async {
    shop = FakeShop();
    await shop.start();
    db = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    restocks = 0;
    failSecondRestock = false;
    s = Shop(
      name: 'Iman',
      kind: 'pharmacy',
      address: shop.url,
      snapshot: {
        'plugins': ['productplus'],
        'stockTake': true,
        'units': [
          {'id': 4, 'abbreviation': 'pcs'},
          {'id': 5, 'abbreviation': 'm'},
        ],
        'fields': [
          {'id': 1, 'key': 'generic_name', 'label': 'Generic name', 'isActive': true},
        ],
      },
    );
    await db.saveShop(s);
    var nextCat = 10;
    shop.routes = {
      'POST /api/v1/admin/categories/quick': (_, _) => {'id': nextCat++},
      'POST /api/v1/admin/suppliers': (_, _) => {'id': 33},
      'POST /api/v1/admin/inventory/intake/create': (_, _) => {'productId': 70, 'name': 'Amoxil'},
      'POST /api/v1/admin/products/70/packs': (_, _) => {'id': 1},
      'POST /api/v1/admin/products/70/barcodes': (_, _) => {'barcode': 'x'},
      'GET /api/v1/admin/products/70/packs': (_, _) => [],
      'GET /api/v1/admin/products/70/barcodes': (_, _) => [],
      'POST /api/v1/admin/inventory/intake/restock': (r, _) {
        restocks++;
        if (failSecondRestock && restocks == 2) {
          r.response.statusCode = 422;
          return {
            'error': {'code': 'VALIDATION', 'message': 'bad expiry'},
          };
        }
        return {'productId': 70};
      },
    };
  });
  tearDown(() async {
    await shop.server.close(force: true);
    await db.close();
  });

  Draft draft() => Draft(
    product: CatalogProduct(
      name: 'Amoxil 250',
      barcode: '555',
      barcodes: ['556'],
      category: 'Medicine > Antibiotic',
      unit: 'pcs',
      cost: '20',
      selling: '25',
      packs: [Pack(name: 'Card', size: '10', selling: '240', barcode: 'C1')],
      fields: {'Generic name': 'Amoxicillin'},
    ),
    newSupplier: CatalogSupplier(name: 'New Pharma', phone: '077'),
    mode: StockMode.several,
    batches: [
      StockBatch(qty: '30', expiry: '2027-12-31'),
      StockBatch(qty: '20', expiry: '2028-06-30', cost: '21', selling: '26'),
      StockBatch(qty: '10', expiry: '2028-09-30'),
    ],
  );

  List<Map> sent(String path) => [
    for (final c in shop.calls)
      if (c.$2 == path && c.$4.isNotEmpty) jsonDecode(c.$4) as Map,
  ];

  test('a new product with three batches: one create, two restocks; the catalogue gets it', () async {
    final r = await pushCreate(db, SuiteClient(shop.url), s, draft());
    expect(r.productId, 70);
    expect(r.failed, isEmpty);
    final create = sent('/api/v1/admin/inventory/intake/create').single;
    expect(create['quantity'], '30');
    expect(create['expiry'], '2027-12-31');
    final p = create['product'] as Map;
    expect(p['categoryId'], 11, reason: 'Medicine (10) > Antibiotic (11), level by level');
    expect(p['unitId'], 4);
    expect(p['supplierId'], 33);
    expect(p['costPrice'], '20');
    expect(p['packs'], [
      {'name': 'Card', 'size': '10', 'sellingPrice': '240', 'wholesalePrice': '', 'barcode': 'C1'},
    ]);
    expect(p['extra'], {
      'productplus': {
        'values': {'generic_name': 'Amoxicillin'},
      },
    });
    expect(sent('/api/v1/admin/products/70/packs'), [
      {'name': 'Card', 'size': '10', 'sellingPrice': '240', 'wholesalePrice': '', 'barcode': 'C1'},
    ], reason: 'intake makes the product only: its packs go on after');
    expect(sent('/api/v1/admin/products/70/barcodes'), [
      {'barcode': '556', 'source': 'form'},
    ]);
    final rs = sent('/api/v1/admin/inventory/intake/restock');
    expect(
      [for (final x in rs) (x['quantity'], x['expiry'], x['costPrice'], x['sellingPrice'])],
      [('20', '2028-06-30', '21', '26'), ('10', '2028-09-30', '20', '25')],
    );
    final cat = (await db.products()).single;
    expect(cat.name, 'Amoxil 250');
    expect(cat.sources, {s.uid});
    expect(cat.kinds, {'pharmacy'});
  });

  test('stock-take off: refused before any call', () async {
    s.snapshot['stockTake'] = false;
    await expectLater(
      pushCreate(db, SuiteClient(shop.url), s, draft()),
      throwsA(isA<PushError>().having((e) => e.message, 'message', 'Turn on Stock-take on this shop first')),
    );
    expect(shop.calls, isEmpty);
  });

  test('a batch refused half-way is listed; a retry sends only it', () async {
    failSecondRestock = true;
    final r = await pushCreate(db, SuiteClient(shop.url), s, draft());
    expect(r.productId, 70);
    expect(r.failed.map((f) => (f.index, f.message)), [(2, 'bad expiry')]);
    restocks = 0;
    failSecondRestock = false;
    final again = await retryBatches(SuiteClient(shop.url), r);
    expect(again.failed, isEmpty);
    expect(restocks, 1);
    expect(sent('/api/v1/admin/inventory/intake/restock').last['quantity'], '10');
  });

  test('offline: queued, and a flush sends it once', () async {
    await queue(db, s, 'create', draft());
    expect((await db.pending(s.uid)).length, 1);
    final left = await flushPending(db, SuiteClient(shop.url), s);
    expect(left, 0);
    expect(await db.pending(s.uid), isEmpty);
    expect(sent('/api/v1/admin/inventory/intake/create').length, 1);
  });

  test('a queued product made but with a batch refused: the retry sends only that batch, never a second product', () async {
    failSecondRestock = true;
    await queue(db, s, 'create', draft());
    expect(await flushPending(db, SuiteClient(shop.url), s), 1);
    final left = (await db.pending(s.uid)).single;
    expect(left.op, 'batches');
    expect(left.error, contains('bad expiry'));
    failSecondRestock = false;
    restocks = 0;
    expect(await flushPending(db, SuiteClient(shop.url), s), 0);
    expect(sent('/api/v1/admin/inventory/intake/create').length, 1);
    expect(restocks, 1);
  });

  test('the same new supplier on two products is made once in the shop', () async {
    var made = 0;
    shop.routes['POST /api/v1/admin/suppliers'] = (_, _) => {'id': 33 + made++};
    await pushCreate(db, SuiteClient(shop.url), s, draft());
    final second = draft()..product = CatalogProduct(name: 'Amoxil 500', category: 'Medicine', cost: '1', selling: '2');
    await pushCreate(db, SuiteClient(shop.url), s, second);
    expect(made, 1);
    expect((sent('/api/v1/admin/inventory/intake/create').last['product'] as Map)['supplierId'], 33);
  });

  test('a change keeps the shop\'s own reorder level', () async {
    shop.routes['GET /api/v1/admin/products/70'] = (_, _) => {'id': 70, 'name': 'Amoxil', 'reorderLevel': 25, 'reorderAuto': false, 'supplierId': 3};
    shop.routes['PUT /api/v1/admin/products/70'] = (_, _) => {'id': 70};
    await pushUpdate(
      db,
      SuiteClient(shop.url),
      s,
      Draft(
        product: CatalogProduct(name: 'Amoxil 250mg', category: 'Medicine', unit: 'pcs'),
        remoteId: 70,
      ),
    );
    final put = jsonDecode(shop.calls.lastWhere((c) => c.$1 == 'PUT').$4) as Map;
    expect(put['name'], 'Amoxil 250mg');
    expect(put['reorderLevel'], 25);
    expect(put['supplierId'], 3);
  });

  test('a catalogue product goes to a shop without a category: the shop files it', () {
    final p = CatalogProduct(name: 'Panadol', category: 'Medicine > Pain', selling: '12', fields: {'Generic name': 'Paracetamol'});
    final d = fromCatalogue(p);
    expect(d.product.category, '');
    expect(d.product.name, 'Panadol');
    expect(d.product.fields, {'Generic name': 'Paracetamol'});
    expect(p.category, 'Medicine > Pain', reason: 'the catalogue keeps its own');
  });

  test('a pushed product shows in the shop\'s list at once, and a change updates it', () async {
    await pushCreate(db, SuiteClient(shop.url), s, draft());
    var mine = await db.shopProducts(s.uid);
    expect(mine.map((x) => (x['remote_id'], x['name'])), [(70, 'Amoxil 250')]);
    shop.routes['GET /api/v1/admin/products/70'] = (_, _) => {'id': 70, 'name': 'Amoxil 250', 'reorderLevel': 0, 'supplierId': 0};
    shop.routes['PUT /api/v1/admin/products/70'] = (_, _) => {'id': 70};
    await pushUpdate(
      db,
      SuiteClient(shop.url),
      s,
      Draft(
        product: CatalogProduct(name: 'Amoxil 250mg Capsules', unit: 'pcs'),
        remoteId: 70,
      ),
    );
    mine = await db.shopProducts(s.uid);
    expect(mine.map((x) => (x['remote_id'], x['name'])), [(70, 'Amoxil 250mg Capsules')]);
  });

  test('a refused pack is reported; the product stands', () async {
    shop.routes['POST /api/v1/admin/products/70/packs'] = (r, _) {
      r.response.statusCode = 422;
      return {
        'error': {'code': 'VALIDATION', 'message': 'that barcode is already used'},
      };
    };
    final r = await pushCreate(db, SuiteClient(shop.url), s, draft());
    expect(r.productId, 70);
    expect(r.notes, ['Pack Card: that barcode is already used']);
  });

  test('a batch added offline waits, then goes in as a restock only', () async {
    await queueBatch(db, s, 70, CatalogProduct(name: 'Amoxil', cost: '20', selling: '25'), StockBatch(qty: '15', expiry: '2028-01-31'));
    expect((await db.pending(s.uid)).single.op, 'batches');
    expect(await flushPending(db, SuiteClient(shop.url), s), 0);
    final r = sent('/api/v1/admin/inventory/intake/restock').single;
    expect((r['productId'], r['quantity'], r['expiry'], r['costPrice']), (70, '15', '2028-01-31', '20'));
    expect(sent('/api/v1/admin/inventory/intake/create'), isEmpty);
  });

  test('a unit the shop hasn\'t got is made there first', () async {
    shop.routes['POST /api/v1/admin/units'] = (_, _) => {'id': 9, 'name': 'Metre', 'abbreviation': 'm'};
    final d = draft()..product.unit = 'm';
    d.mode = StockMode.none;
    await pushCreate(db, SuiteClient(shop.url), s, d);
    expect(sent('/api/v1/admin/units'), isEmpty, reason: 'the shop already has m');
    expect((sent('/api/v1/admin/inventory/intake/create').single['product'] as Map)['unitId'], 5);
    final d2 = draft()..product.unit = 'roll';
    d2.mode = StockMode.none;
    await pushCreate(db, SuiteClient(shop.url), s, d2);
    expect(sent('/api/v1/admin/units').single['abbreviation'], 'roll');
    expect((sent('/api/v1/admin/inventory/intake/create').last['product'] as Map)['unitId'], 9);
    expect((s.snapshot['units'] as List).any((u) => u['abbreviation'] == 'roll'), isTrue);
  });

  test('a quick add brings the product\'s usual supplier: the shop\'s own, or made there', () async {
    var made = 0;
    shop.routes['POST /api/v1/admin/suppliers'] = (_, _) => {'id': 60 + made++};
    s.snapshot['suppliers'] = [
      {'id': 3, 'name': 'Hemas'},
    ];
    final a = Draft(
      product: CatalogProduct(name: 'A', supplier: 'HEMAS', unit: 'pcs'),
      useProductSupplier: true,
    );
    await pushCreate(db, SuiteClient(shop.url), s, a);
    expect((sent('/api/v1/admin/inventory/intake/create').last['product'] as Map)['supplierId'], 3);
    final b = Draft(
      product: CatalogProduct(name: 'B', supplier: 'Lanka Wire', unit: 'pcs'),
      useProductSupplier: true,
    );
    await pushCreate(db, SuiteClient(shop.url), s, b);
    expect((sent('/api/v1/admin/inventory/intake/create').last['product'] as Map)['supplierId'], 60);
    final c = Draft(
      product: CatalogProduct(name: 'C', supplier: 'Lanka Wire', unit: 'pcs'),
    );
    await pushCreate(db, SuiteClient(shop.url), s, c);
    expect((sent('/api/v1/admin/inventory/intake/create').last['product'] as Map)['supplierId'], 0, reason: 'the editor said none');
    expect(made, 1);
  });

  test('a change also sends packs and barcodes the shop hasn\'t got', () async {
    shop.routes['GET /api/v1/admin/products/70'] = (_, _) => {'id': 70, 'name': 'Amoxil', 'reorderLevel': 0, 'supplierId': 0};
    shop.routes['PUT /api/v1/admin/products/70'] = (_, _) => {'id': 70};
    shop.routes['GET /api/v1/admin/products/70/packs'] = (_, _) => [
      {'id': 1, 'name': 'Card', 'size': '10'},
    ];
    shop.routes['GET /api/v1/admin/products/70/barcodes'] = (_, _) => [
      {'barcode': '555'},
    ];
    final p = CatalogProduct(
      name: 'Amoxil',
      barcode: '555',
      barcodes: ['556'],
      unit: 'pcs',
      packs: [
        Pack(name: 'Card', size: '10'),
        Pack(name: 'Box', size: '100', selling: '2300'),
      ],
    );
    await pushUpdate(db, SuiteClient(shop.url), s, Draft(product: p, remoteId: 70));
    expect(sent('/api/v1/admin/products/70/packs').map((x) => x['name']), ['Box']);
    expect(sent('/api/v1/admin/products/70/barcodes').map((x) => x['barcode']), ['556']);
  });

  test('disabling a product in the shop: the shop keeps its history, it leaves the shop\'s list here', () async {
    shop.routes['DELETE /api/v1/admin/products/70'] = (r, _) {
      r.response.statusCode = 204;
      return '';
    };
    await db.putShopProduct(s.uid, {'remote_id': 70, 'name': 'Amoxil', 'json': '{}'});
    await disableInShop(db, SuiteClient(shop.url), s, 70);
    expect(shop.calls.where((c) => c.$1 == 'DELETE' && c.$2 == '/api/v1/admin/products/70').length, 1);
    expect(await db.shopProducts(s.uid), isEmpty);
  });
}
