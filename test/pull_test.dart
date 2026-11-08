import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/suite/client.dart';
import 'package:karots_suite_onboard/sync/pull.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_shop.dart';

const header =
    'name,name_local,barcode,extra_barcodes,category,unit,cost_price,selling_price,wholesale_price,tax_rate,reorder_level,opening_qty,supplier,track_serial,warranty_months,Generic name,id\r\n';

void main() {
  sqfliteFfiInit();
  late FakeShop shop;
  late Db db;
  setUp(() async {
    shop = FakeShop();
    await shop.start();
    db = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    shop.routes = {
      'GET /api/v1/me': (_, _) => {
        'shopName': 'Iman',
        'plugins': ['productplus', 'alternatives', 'aicatalog'],
        'stockTakeEnabled': true,
      },
      'GET /api/v1/admin/products/export': (_, _) =>
          '${header}Panadol 500mg,,111,,Medicine,pcs,8.50,10.00,0.00,0.00,0,40,Hemas,false,0,Paracetamol,7\r\n'
          'Amoxil 250,,555,,Medicine,pcs,20.00,25.00,0.00,0.00,0,0,,false,0,Amoxicillin,8\r\n',
      'GET /api/v1/admin/products/packs': (_, _) => {
        '8': [
          {
            'name': 'Card',
            'size': '10',
            'sellingPrice': '240.00',
            'wholesalePrice': '0.00',
            'barcodes': ['C8'],
          },
        ],
      },
      'GET /api/v1/admin/suppliers/export': (_, _) =>
          'name,contact_person,phone,address,credit_days,opening_balance\r\nHemas,Ravi,0771,,30,0\r\nNew Pharma,,0772,,0,0\r\n',
      'GET /api/v1/admin/categories': (_, _) => [
        {'id': 1, 'name': 'Medicine', 'parentId': 0, 'path': []},
      ],
      'GET /api/v1/admin/units': (_, _) => [
        {'id': 1, 'name': 'Pieces', 'abbreviation': 'pcs', 'allowDecimal': false},
      ],
      'GET /api/v1/admin/supplier-options': (_, _) => [
        {'id': 3, 'name': 'Hemas'},
      ],
      'GET /api/v1/x/productplus/fields': (_, _) => [
        {
          'id': 1,
          'key': 'generic_name',
          'label': 'Generic name',
          'type': 'text',
          'isActive': true,
          'scope': [
            {'id': 1, 'name': 'Medicine'},
          ],
          'options': [],
        },
      ],
      'GET /api/v1/x/alternatives': (_, _) => [
        {'id': 1, 'name': 'Paracetamol 500', 'tiers': []},
      ],
      'GET /api/v1/x/aicatalog/settings': (_, _) => {
        'namingStyle': 'Brand Strength Form',
        'customPrompt': '',
        'identifyFields': ['generic_name'],
      },
    };
  });
  tearDown(() async {
    await shop.server.close(force: true);
    await db.close();
  });

  test('known products are skipped, new ones go to Review with packs and fields; the shop snapshot is kept', () async {
    await db.saveProduct(CatalogProduct(name: 'panadol 500mg', barcode: '111'));
    await db.saveSupplier(CatalogSupplier(name: 'HEMAS'));
    final s = Shop(name: 'Iman', kind: 'pharmacy', address: shop.url);
    await db.saveShop(s);
    final r = await pull(db, SuiteClient(shop.url), s);
    expect((r.known, r.toReview, r.suppliersKnown, r.suppliersToReview), (1, 1, 1, 1));
    final rev = await db.reviews();
    final p = CatalogProduct.fromJson(rev.firstWhere((x) => x.kind == 'product').data);
    expect(p.name, 'Amoxil 250');
    expect(p.packs.single.name, 'Card');
    expect(p.packs.single.barcode, 'C8');
    expect(p.fields, {'Generic name': 'Amoxicillin'});
    expect(p.kinds, {'pharmacy'});
    expect(rev.firstWhere((x) => x.kind == 'supplier').data['name'], 'New Pharma');
    final saved = (await db.shops()).single;
    expect(saved.plugins, contains('productplus'));
    expect(saved.snapshot['stockTake'], isTrue);
    expect((saved.snapshot['fields'] as List).single['label'], 'Generic name');
    expect(saved.snapshot['ai']['namingStyle'], 'Brand Strength Form');
    expect(saved.lastPull, isNotNull);
    expect((await db.shopProducts(s.uid)).map((x) => x['remote_id']), [8, 7]);
    // the matched product now knows it is in this shop
    expect((await db.productByBarcode('111'))!.sources, {s.uid});

    final again = await pull(db, SuiteClient(shop.url), s);
    expect(again.toReview, 0, reason: 'a second pull adds no duplicate review rows');
    expect((await db.reviews()).length, 2);
  });
}
