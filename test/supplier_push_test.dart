import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/suite/client.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_shop.dart';

void main() {
  test('a supplier goes into a shop once; the catalogue keeps it', () async {
    sqfliteFfiInit();
    final shop = FakeShop();
    await shop.start();
    final db = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    var made = 0;
    shop.routes = {
      'POST /api/v1/admin/suppliers': (_, _) => {'id': 40 + made++},
    };
    final s = Shop(
      name: 'Iman',
      kind: 'pharmacy',
      address: shop.url,
      snapshot: {
        'suppliers': [
          {'id': 3, 'name': 'Hemas'},
        ],
      },
    );
    await db.saveShop(s);
    final c = SuiteClient(shop.url);
    final sup = CatalogSupplier(name: 'Lanka Wire', contact: 'Sunil', phone: '077', address: 'Colombo', creditDays: 30);
    expect(await pushSupplier(db, c, s, sup), 40);
    expect(await pushSupplier(db, c, s, CatalogSupplier(name: 'lanka  wire')), 40, reason: 'already there');
    expect(await pushSupplier(db, c, s, CatalogSupplier(name: 'HEMAS')), 3);
    expect(made, 1);
    final body = jsonDecode(shop.calls.single.$4) as Map;
    expect((body['name'], body['contact'], body['phone'], body['creditDays']), ('Lanka Wire', 'Sunil', '077', 30));
    final cat = (await db.suppliers()).firstWhere((x) => x.name == 'Lanka Wire');
    expect(cat.name, 'Lanka Wire');
    expect(cat.sources, {s.uid});
    expect(cat.kinds, {'pharmacy'});
    await shop.server.close(force: true);
    await db.close();
  });
}
