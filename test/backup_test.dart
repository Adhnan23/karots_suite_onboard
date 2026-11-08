import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/backup.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Db> fresh() => Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);

void main() {
  sqfliteFfiInit();
  test('a backup carries the catalogue, suppliers and shops; importing merges, newer wins, no twins', () async {
    final a = await fresh();
    final shop = Shop(
      name: 'Iman',
      kind: 'pharmacy',
      address: 'http://100.101.5.2:3000',
      secretName: 'Main',
      snapshot: {
        'plugins': ['productplus'],
      },
    );
    await a.saveShop(shop);
    await a.replaceShopProducts(shop.uid, [
      {'remote_id': 7, 'name': 'Panadol', 'json': '{}'},
    ]);
    final p = CatalogProduct(
      name: 'Panadol 500mg',
      barcode: '111',
      selling: '12',
      packs: [Pack(name: 'Card', size: '12')],
      fields: {'Generic name': 'Paracetamol'},
    );
    await a.saveProduct(p);
    await a.saveSupplier(CatalogSupplier(name: 'Hemas', phone: '077'));
    final file = await exportBackup(a);
    expect(file, isNot(contains('secret":')), reason: 'no support secrets in a backup');
    await a.close();

    final b = await fresh();
    // b has its own older copy of the same product, a twin by barcode, and its own supplier
    final old = CatalogProduct(uid: p.uid, name: 'Panadol old', barcode: '111', updatedAt: DateTime(2020));
    await b.raw.insert('catalog_products', old.toRow());
    await b.saveProduct(CatalogProduct(name: 'Something else', barcode: '999'));
    await b.saveSupplier(CatalogSupplier(name: 'HEMAS', phone: ''));
    final r = await importBackup(b, file);
    expect((r.products, r.suppliers, r.shops), (1, 0, 1));
    final all = await b.products();
    expect(all.length, 2);
    final got = all.firstWhere((x) => x.uid == p.uid);
    expect(got.name, 'Panadol 500mg');
    expect(got.packs.single.name, 'Card');
    expect(got.fields['Generic name'], 'Paracetamol');
    expect((await b.suppliers()).length, 1, reason: 'Hemas matched by name');
    final s = (await b.shops()).single;
    expect((s.name, s.secretName), ('Iman', 'Main'));
    expect(s.plugins, ['productplus']);
    expect((await b.shopProducts(s.uid)).single['remote_id'], 7);
    // importing again changes nothing
    final again = await importBackup(b, file);
    expect((again.products, again.suppliers, again.shops), (0, 0, 0));
    await b.close();
  });

  test('a file that isn\'t a backup is refused', () async {
    final b = await fresh();
    await expectLater(importBackup(b, '{"hello":1}'), throwsA(isA<FormatException>()));
    await b.close();
  });
}
