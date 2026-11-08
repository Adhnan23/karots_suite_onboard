import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Db db;
  setUp(() async => db = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi));
  tearDown(() => db.close());

  test('a catalogue product round trips with its barcodes, packs and fields', () async {
    final p = CatalogProduct(
      name: 'Panadol 500mg',
      barcode: '111',
      category: 'Medicine > Pain',
      unit: 'pcs',
      cost: '8.50',
      selling: '10.00',
      kinds: {'pharmacy'},
      sources: {'shop-1'},
      barcodes: ['222', '333'],
      packs: [Pack(name: 'Card', size: '12', selling: '115.00', barcode: 'C1')],
      fields: {'Generic name': 'Paracetamol'},
    );
    await db.saveProduct(p);
    final got = (await db.products()).single;
    expect(got.name, 'Panadol 500mg');
    expect(got.cost, '8.50');
    expect(got.kinds, {'pharmacy'});
    expect(got.barcodes, ['222', '333']);
    expect(got.packs.single.size, '12');
    expect(got.fields['Generic name'], 'Paracetamol');
    expect((await db.productByBarcode('333'))?.uid, p.uid);
    expect((await db.productByBarcode('111'))?.uid, p.uid);
    expect(await db.productByBarcode('999'), isNull);
  });

  test('suppliers, shops, review and pending round trip', () async {
    await db.saveSupplier(CatalogSupplier(name: 'Hemas', phone: '0771', kinds: {'pharmacy'}));
    expect((await db.suppliers()).single.phone, '0771');
    final s = Shop(name: 'Iman', kind: 'pharmacy', address: 'http://100.64.0.5:3000');
    await db.saveShop(s);
    s.snapshot = {
      'plugins': ['productplus'],
    };
    await db.saveShop(s);
    expect((await db.shops()).single.snapshot['plugins'], ['productplus']);
    await db.addReview(ReviewItem(shopUid: s.uid, kind: 'product', data: {'name': 'X'}));
    expect((await db.reviews(status: 'new')).single.data['name'], 'X');
    await db.addPending(PendingOp(shopUid: s.uid, op: 'create', data: {'a': 1}));
    expect((await db.pending(s.uid)).single.op, 'create');
  });

  test('a database made before named secrets gains the column and keeps its shops', () async {
    final path = '${Directory.systemTemp.createTempSync('ob').path}/v1.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, _) async {
          await d.execute(
            'CREATE TABLE shops(uid TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT, address TEXT, install_id TEXT, last_pull TEXT, snapshot TEXT)',
          );
          await d.insert('shops', {'uid': 'a', 'name': 'Iman', 'snapshot': '{}'});
        },
      ),
    );
    await old.close();
    final db = await Db.openWith(path: path, factory: databaseFactoryFfi);
    final s = (await db.shops()).single;
    expect(s.name, 'Iman');
    s.secretName = 'Reseller A';
    await db.saveShop(s);
    expect((await db.shops()).single.secretName, 'Reseller A');
    await db.close();
  });
}
