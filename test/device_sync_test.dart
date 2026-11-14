import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/sync/device_sync.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('two devices swap and merge; a wrong code is refused', () async {
    final pc = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    await pc.saveProduct(CatalogProduct(name: 'Only on the PC', barcode: '1'));
    await pc.saveShop(Shop(name: 'Iman', address: 'http://100.101.5.2:3000'));
    final host = await SyncHost.start(pc, port: 0, code: '123456');

    final phonePath = '${Directory.systemTemp.createTempSync('phone').path}/onboard.db';
    final phone = await Db.openWith(path: phonePath, factory: databaseFactoryFfi);
    await phone.saveProduct(CatalogProduct(name: 'Only on the phone', barcode: '2'));
    await phone.saveSupplier(CatalogSupplier(name: 'Hemas'));

    await expectLater(syncWith(phone, 'http://127.0.0.1:${host.port}', '000000'), throwsA(isA<SyncError>()));
    final r = await syncWith(phone, 'http://127.0.0.1:${host.port}', '123456');
    expect((r.got.products, r.got.shops, r.sent.products, r.sent.suppliers), (1, 1, 1, 1));
    expect({for (final p in await phone.products()) p.name}, {'Only on the PC', 'Only on the phone'});
    expect({for (final p in await pc.products()) p.name}, {'Only on the PC', 'Only on the phone'});
    expect((await pc.suppliers()).single.name, 'Hemas');
    expect((await phone.shops()).single.name, 'Iman');
    await host.stop();
    await pc.close();
    await phone.close();
  });

  test('after the first sync only what changed travels, both ways', () async {
    final pc = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    for (var i = 0; i < 3; i++) {
      await pc.saveProduct(CatalogProduct(name: 'Old $i', barcode: '$i'));
    }
    await pc.saveShop(Shop(name: 'Iman', address: 'http://100.101.5.2:3000'));
    final host = await SyncHost.start(pc, port: 0, code: '123456');
    final phone = await Db.openWith(path: '${Directory.systemTemp.createTempSync('ph').path}/onboard.db', factory: databaseFactoryFfi);
    final url = 'http://127.0.0.1:${host.port}';

    final first = await syncWith(phone, url, '123456');
    expect((first.received, first.got.products), (3, 3));
    final echo = await syncWith(phone, url, '123456', since: first.marks); // hands back what it just took, once
    expect(echo.received, 0);

    await pc.saveProduct(CatalogProduct(name: 'New on the PC', barcode: '9'));
    await phone.saveProduct(CatalogProduct(name: 'New on the phone', barcode: '8'));
    final r = await syncWith(phone, url, '123456', since: echo.marks);
    expect((r.received, r.got.products, r.sent.products), (1, 1, 1));
    expect((await pc.products()).length, 5);

    final quiet = await syncWith(phone, url, '123456', since: (await syncWith(phone, url, '123456', since: r.marks)).marks);
    expect((quiet.received, quiet.got.shops, quiet.sent.products), (0, 0, 0));
    await host.stop();
    await pc.close();
    await phone.close();
  });

  test('five wrong codes close the device for syncing', () async {
    final pc = await Db.openWith(path: '${Directory.systemTemp.createTempSync('pc').path}/onboard.db', factory: databaseFactoryFfi);
    final phone = await Db.openWith(path: '${Directory.systemTemp.createTempSync('ph').path}/onboard.db', factory: databaseFactoryFfi);
    final host = await SyncHost.start(pc, port: 0, code: '123456');
    for (var i = 0; i < 5; i++) {
      await expectLater(syncWith(phone, 'http://127.0.0.1:${host.port}', '00000$i'), throwsA(isA<SyncError>()));
    }
    expect(host.closed, isTrue);
    await expectLater(syncWith(phone, 'http://127.0.0.1:${host.port}', '123456'), throwsA(anything));
    await pc.close();
    await phone.close();
  });
}
