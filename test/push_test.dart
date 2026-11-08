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
      if (c.$2 == path) jsonDecode(c.$4) as Map,
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
}
