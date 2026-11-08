import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/sync/review.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Db db;
  setUp(() async => db = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi));
  tearDown(() => db.close());

  test('accept puts the product in the catalogue with its kind and shop; drop never comes back', () async {
    final p = CatalogProduct(name: 'Amoxil 250', barcode: '555', kinds: {'pharmacy'}, sources: {'shop-1'});
    final r = ReviewItem(shopUid: 'shop-1', kind: 'product', data: p.toJson());
    await db.addReview(r, key: '555');
    await acceptReview(db, r.uid, edited: {...p.toJson(), 'name': 'Amoxil 250mg Capsules'});
    final got = (await db.products()).single;
    expect(got.name, 'Amoxil 250mg Capsules');
    expect(got.kinds, {'pharmacy'});
    expect(got.sources, {'shop-1'});
    expect(await db.reviews(), isEmpty);

    final d = ReviewItem(
      shopUid: 'shop-1',
      kind: 'product',
      data: CatalogProduct(name: 'Junk').toJson(),
    );
    await db.addReview(d, key: 'junk');
    await dropReview(db, d.uid);
    expect(
      await db.addReview(
        ReviewItem(shopUid: 'shop-2', kind: 'product', data: d.data),
        key: 'junk',
      ),
      isFalse,
    );
  });

  test('the same new product from a second shop joins the first instead of doubling', () async {
    final a = ReviewItem(
      shopUid: 's1',
      kind: 'product',
      data: CatalogProduct(name: 'X 1', barcode: '9', kinds: {'grocery'}, sources: {'s1'}).toJson(),
    );
    final b = ReviewItem(
      shopUid: 's2',
      kind: 'product',
      data: CatalogProduct(name: 'x  1', barcodes: ['9'], kinds: {'hardware'}, sources: {'s2'}).toJson(),
    );
    await db.addReview(a, key: 'a');
    await db.addReview(b, key: 'b');
    await acceptReview(db, a.uid);
    await acceptReview(db, b.uid);
    final all = await db.products();
    expect(all.length, 1);
    expect(all.single.sources, {'s1', 's2'});
    expect(all.single.kinds, {'grocery', 'hardware'});
  });

  test('suppliers are accepted into the catalogue', () async {
    final r = ReviewItem(
      shopUid: 's1',
      kind: 'supplier',
      data: CatalogSupplier(name: 'Hemas', phone: '077').toRow(),
    );
    await db.addReview(r, key: 'hemas');
    await acceptReview(db, r.uid);
    expect((await db.suppliers()).single.phone, '077');
  });

  test('accepting many at once: one pass, twins still join', () async {
    final rows = [
      for (var i = 0; i < 300; i++)
        ReviewItem(
          shopUid: 's1',
          kind: 'product',
          data: CatalogProduct(name: 'P $i', barcode: 'B$i', sources: {'s1'}).toJson(),
        ),
      ReviewItem(
        shopUid: 's2',
        kind: 'product',
        data: CatalogProduct(name: 'p  0', sources: {'s2'}).toJson(),
      ),
    ];
    for (final (i, r) in rows.indexed) {
      await db.addReview(r, key: 'k$i');
    }
    final t = Stopwatch()..start();
    await acceptReviews(db, [for (final r in rows) r.uid]);
    expect(t.elapsed.inSeconds, lessThan(5));
    final all = await db.products();
    expect(all.length, 300);
    expect(all.firstWhere((p) => p.barcode == 'B0').sources, {'s1', 's2'});
    expect(await db.reviews(), isEmpty);
  });
}
