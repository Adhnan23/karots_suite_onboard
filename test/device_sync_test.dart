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
}
