import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/flavor.dart';
import 'package:karots_suite_onboard/suite/client.dart';
import 'package:karots_suite_onboard/sync/pull.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_shop.dart';
import 'pull_test.dart' show header;

void main() {
  sqfliteFfiInit();
  late FakeShop shop;
  late Db db;
  late Shop s;
  setUp(() async {
    setShelf(true);
    shop = FakeShop();
    await shop.start();
    db = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    s = Shop(
      name: 'Iman',
      address: shop.url,
      snapshot: {
        'stockTake': true,
        'units': [
          {'id': 1, 'abbreviation': 'pcs', 'isDefault': true},
        ],
        'categories': [],
        'suppliers': [],
      },
    );
    await db.saveShop(s);
  });
  tearDown(() async {
    setShelf(false);
    await shop.server.close(force: true);
    await db.close();
  });

  Object? refuse(dynamic r, int status, String code, String msg) {
    r.response.statusCode = status;
    return {
      'error': {'code': code, 'message': msg},
    };
  }

  // A new product is filed under a category first.
  final filed = <String, Object? Function(dynamic, String)>{
    'POST /api/v1/admin/categories/quick': (_, _) => {'id': 9},
  };

  test('a Shelf pull fills the shop\'s list only: no catalogue, no review, no Alternatives', () async {
    shop.routes = {
      'GET /api/v1/me': (_, _) => {
        'shopName': 'Iman',
        'plugins': ['alternatives'],
        'stockTakeEnabled': true,
      },
      'GET /api/v1/admin/products/export': (_, _) => '${header}Panadol 500mg,,111,,Medicine,pcs,8.50,10.00,0.00,0.00,0,40,Hemas,false,0,,7\r\n',
      'GET /api/v1/admin/products/packs': (_, _) => <String, Object>{},
      'GET /api/v1/admin/suppliers/export': (_, _) => 'name,contact_person,phone,address,credit_days,opening_balance\r\nHemas,,,,0,0\r\n',
      'GET /api/v1/admin/categories': (_, _) => [],
      'GET /api/v1/admin/units': (_, _) => [],
      'GET /api/v1/admin/supplier-options': (_, _) => [],
    };
    final r = await pull(db, SuiteClient(shop.url, app: 'shelf'), s);
    expect(r.known + r.toReview, 1);
    expect(await db.products(), isEmpty);
    expect(await db.reviews(), isEmpty);
    expect((await db.shopProducts(s.uid)).single['name'], 'Panadol 500mg');
    expect(shop.calls.any((c) => c.$2.contains('alternatives')), isFalse);
  });

  test('a pushed product joins the shop\'s list, never the catalogue', () async {
    await keepCopy(db, s, CatalogProduct(name: 'Samaposha', barcode: '9'), remoteId: 5);
    expect(await db.products(), isEmpty);
    expect((await db.shopProducts(s.uid)).single['remote_id'], 5);
  });

  test('each person\'s queue goes up only under their own sign-in', () async {
    shop.routes = {...filed, 'POST /api/v1/admin/inventory/intake/create': (r, _) => refuse(r, 409, 'CONFLICT', 'refused')};
    await queue(
      db,
      s,
      'create',
      Draft(product: CatalogProduct(name: 'A thing')),
      who: '0771',
    );
    await queue(
      db,
      s,
      'create',
      Draft(product: CatalogProduct(name: 'B thing')),
      who: '0772',
    );
    await flushPending(db, SuiteClient(shop.url, app: 'shelf'), s, who: '0772');
    final left = {for (final o in await db.pending(s.uid)) o.data['product']['name']: o};
    expect(left['A thing']!.error, '');
    expect(left['A thing']!.who, '0771');
    expect(left['B thing']!.error, 'refused');
  });

  test('a barcode someone else added meanwhile stays in the queue with the shop\'s reason', () async {
    shop.routes = {
      ...filed,
      'POST /api/v1/admin/inventory/intake/create': (r, _) => refuse(r, 409, 'CONFLICT', 'Barcode 111 is already on Panadol 500mg'),
    };
    await queue(
      db,
      s,
      'create',
      Draft(
        product: CatalogProduct(name: 'Panadol', barcode: '111'),
      ),
      who: '0771',
    );
    expect(await flushPending(db, SuiteClient(shop.url, app: 'shelf'), s, who: '0771'), 1);
    expect((await db.pending(s.uid)).single.error, 'Barcode 111 is already on Panadol 500mg');
  });

  test('access taken away: the queue stays, saying to ask the owner', () async {
    shop.routes = {...filed, 'POST /api/v1/admin/inventory/intake/create': (r, _) => refuse(r, 403, 'SHELF_NO_ACCESS', 'x')};
    await queue(
      db,
      s,
      'create',
      Draft(product: CatalogProduct(name: 'X')),
      who: '0771',
    );
    await flushPending(db, SuiteClient(shop.url, app: 'shelf'), s, who: '0771');
    expect((await db.pending(s.uid)).single.error, 'Ask the owner to give you Karots Shelf (Users page)');
  });
}
