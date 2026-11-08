// Karots Shelf against a running dev Suite with every plugin (make plugins P=all; make dev):
//   LIVE_SUITE=http://localhost:3000 flutter test test/shelf_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/flavor.dart';
import 'package:karots_suite_onboard/suite/client.dart';
import 'package:karots_suite_onboard/sync/pull.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final url = Platform.environment['LIVE_SUITE'];
  test('a ticked cashier puts a product in from Shelf; an unticked one is refused', () async {
    sqfliteFfiInit();
    final db = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final admin = SuiteClient(url!);
    await admin.signIn('no-secret-in-dev', (await admin.loginInfo()).installId);
    if (!(await admin.me()).stockTakeEnabled) await admin.enableStockTake();
    final tag = DateTime.now().millisecondsSinceEpoch % 100000000;
    String phone(int n) => '07${((tag + n) % 100000000).toString().padLeft(8, '0')}';
    final ticked =
        await admin.post('/admin/users', {'name': 'Shelf T$tag', 'phone': phone(1), 'role': 'cashier', 'pin': '4321', 'canUseShelf': true}) as Map;
    final unticked = await admin.post('/admin/users', {'name': 'Shelf U$tag', 'phone': phone(2), 'role': 'cashier', 'pin': '4321'}) as Map;
    addTearDown(() async {
      await admin.delete('/admin/users/${ticked['id']}');
      await admin.delete('/admin/users/${unticked['id']}');
    });

    final no = SuiteClient(url, app: 'shelf', device: 'live-u');
    await expectLater(no.signInPerson(phone(2), '4321'), throwsA(isA<SuiteError>().having((e) => e.code, 'code', 'SHELF_NO_ACCESS')));

    setShelf(true);
    addTearDown(() => setShelf(false));
    final c = SuiteClient(url, app: 'shelf', device: 'live-t');
    expect((await c.signInPerson(phone(1), '4321')).role, 'cashier');
    final s = Shop(name: 'Dev', address: url);
    await db.saveShop(s);
    await pull(db, c, s);
    expect(await db.products(), isEmpty);
    expect(await db.shopProducts(s.uid), isNotEmpty);
    expect((s.snapshot['units'] as List).any((u) => (u as Map)['isDefault'] == true), isTrue);
    expect(await c.get('/x/productplus/fields'), isA<List>());

    final d = Draft(
      product: newShopProduct(s, name: 'Shelf live $tag', barcode: '99$tag')..selling = '120.00',
      mode: StockMode.one,
      batches: [StockBatch(qty: '5', expiry: '2028-01-31')],
    );
    final r = await pushCreate(db, c, s, d);
    expect(r.failed, isEmpty);
    final made = await c.get('/admin/products/${d.remoteId}') as Map;
    expect(made['name'], 'Shelf live $tag');
    expect(await db.products(), isEmpty, reason: 'Shelf never writes the catalogue');

    d.product.selling = '125.00';
    await pushUpdate(db, c, s, d);
    expect('${(await c.get('/admin/products/${d.remoteId}') as Map)['sellingPrice']}', '125.00');

    // A second phone can't make a twin of that barcode.
    final twin = Draft(
      product: newShopProduct(s, name: 'Twin $tag', barcode: '99$tag'),
    );
    await queue(db, s, 'create', twin, who: phone(1));
    expect(await flushPending(db, c, s, who: phone(1)), 1);
    expect((await db.pending(s.uid)).single.error, isNotEmpty);

    for (final p in ['/admin/sales', '/admin/settings', '/admin/users']) {
      await expectLater(c.get(p), throwsA(isA<SuiteError>().having((e) => e.status, 'status', 403)), reason: p);
    }

    await admin.put('/admin/users/${ticked['id']}', {'name': 'Shelf T$tag', 'phone': phone(1), 'role': 'cashier'});
    await expectLater(c.get('/admin/units'), throwsA(isA<SuiteError>().having((e) => e.code, 'code', 'SHELF_NO_ACCESS')));
    await admin.delete('/admin/products/${d.remoteId}');
    await db.close();
  }, skip: url == null ? 'set LIVE_SUITE' : false);
}
