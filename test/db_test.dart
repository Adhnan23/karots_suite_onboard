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
      name: 'Panadol 500mg', barcode: '111', category: 'Medicine > Pain', unit: 'pcs',
      cost: '8.50', selling: '10.00', kinds: {'pharmacy'}, sources: {'shop-1'},
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
    s.snapshot = {'plugins': ['productplus']};
    await db.saveShop(s);
    expect((await db.shops()).single.snapshot['plugins'], ['productplus']);
    await db.addReview(ReviewItem(shopUid: s.uid, kind: 'product', data: {'name': 'X'}));
    expect((await db.reviews(status: 'new')).single.data['name'], 'X');
    await db.addPending(PendingOp(shopUid: s.uid, op: 'create', data: {'a': 1}));
    expect((await db.pending(s.uid)).single.op, 'create');
  });
}
