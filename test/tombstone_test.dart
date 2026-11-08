import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/backup.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Db> fresh() => Db.openWith(path: '${Directory.systemTemp.createTempSync('ob').path}/db', factory: databaseFactoryFfi);

void main() {
  sqfliteFfiInit();
  test('a delete on one device removes it on the other; an edit made after the delete wins', () async {
    final pc = await fresh(), phone = await fresh();
    final gone = CatalogProduct(name: 'Gone', barcode: '1'), kept = CatalogProduct(name: 'Kept', barcode: '2');
    final sup = CatalogSupplier(name: 'Old Supplier');
    final shop = Shop(name: 'Closed shop');
    for (final d in [pc, phone]) {
      await d.saveProduct(CatalogProduct.fromJson(gone.toJson()), touch: false);
      await d.saveProduct(CatalogProduct.fromJson(kept.toJson()), touch: false);
      await d.saveSupplier(sup);
      await d.saveShop(shop);
    }
    await pc.deleteProduct(gone.uid);
    await pc.deleteProduct(kept.uid);
    await pc.deleteSupplier(sup.uid);
    await pc.deleteShop(shop.uid);
    // on the phone, Kept was changed after the PC deleted it: the change wins
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final k = (await phone.product(kept.uid))!..selling = '9';
    await phone.saveProduct(k);

    await importBackup(phone, await exportBackup(pc));
    expect([for (final p in await phone.products()) p.name], ['Kept']);
    expect(await phone.suppliers(), isEmpty);
    expect(await phone.shops(), isEmpty);

    await importBackup(pc, await exportBackup(phone));
    expect([for (final p in await pc.products()) p.name], ['Kept'], reason: 'Kept comes back to the PC: edited after its delete');
    expect(await pc.suppliers(), isEmpty, reason: 'deleted stays deleted');
  });
}
