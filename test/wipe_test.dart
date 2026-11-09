import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/settings/secrets.dart';
import 'package:karots_suite_onboard/settings/secure.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Db> fresh() => Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);

void main() {
  sqfliteFfiInit();

  Future<(Db, Shop)> filled() async {
    final db = await fresh();
    final shop = Shop(name: 'Iman');
    await db.saveShop(shop);
    final p = CatalogProduct(
      name: 'Panadol',
      barcode: '111',
      barcodes: ['112'],
      packs: [Pack(name: 'Card', size: '12')],
      fields: {'Generic Name': 'Paracetamol'},
    );
    await db.saveProduct(p);
    await db.saveSupplier(CatalogSupplier(name: 'Hemas'));
    await db.replaceShopProducts(shop.uid, [
      {'remote_id': 7, 'catalog_uid': p.uid, 'name': 'Panadol', 'json': '{}'},
    ]);
    await db.addReview(
      ReviewItem(
        shopUid: shop.uid,
        kind: 'product',
        data: CatalogProduct(name: 'Piriton').toJson(),
      ),
      key: 'piriton',
    );
    return (db, shop);
  }

  test('wiping products clears them with their barcodes, packs and details; deletions travel; shops stay', () async {
    final (db, shop) = await filled();
    final r = await db.wipe(products: true);
    expect(r.products, 1);
    expect(await db.products(), isEmpty);
    expect(await db.productByBarcode('112'), isNull);
    expect((await db.deletedAt('product')).length, 1, reason: 'a team device follows');
    expect((await db.shops()).single.name, 'Iman');
    expect((await db.shopProducts(shop.uid)).single['catalog_uid'], isNull, reason: 'the shop\'s own list stays, unlinked');
    expect(await db.suppliers(), isNotEmpty, reason: 'suppliers only when ticked');
    expect(await db.reviews(), isNotEmpty, reason: 'review only when ticked');
    await db.close();
  });

  test('suppliers and the review list wipe on their own; a cleared review lets a pull list things again', () async {
    final (db, shop) = await filled();
    final r = await db.wipe(suppliers: true, review: true);
    expect((r.products, r.suppliers, r.review), (0, 1, 1));
    expect(await db.suppliers(), isEmpty);
    expect(await db.reviews(), isEmpty);
    expect(await db.products(), isNotEmpty);
    expect(
      await db.addReview(
        ReviewItem(
          shopUid: shop.uid,
          kind: 'product',
          data: CatalogProduct(name: 'Piriton').toJson(),
        ),
        key: 'piriton',
      ),
      isTrue,
    );
    await db.close();
  });

  test('wiping shops removes them with their lists and waiting changes; deletions travel', () async {
    final (db, shop) = await filled();
    await queue(db, shop, 'create', Draft(product: CatalogProduct(name: 'X')));
    expect(await db.pendingCount(), 1);
    final r = await db.wipe(shops: true);
    expect(r.shops, 1);
    expect(await db.shops(), isEmpty);
    expect(await db.shopProducts(shop.uid), isEmpty);
    expect(await db.pendingCount(), 0);
    expect((await db.deletedAt('shop')).length, 1);
    expect(await db.products(), isNotEmpty);
    await db.close();
  });

  test('support secrets clear, including an old single secret', () async {
    final store = MemoryStore();
    await store.write(supportSecretKey, 'old');
    await Secrets(store).save([(name: 'Main', secret: 'abc')]);
    await Secrets(store).clear();
    expect(await Secrets(store).all(), isEmpty);
  });
}
