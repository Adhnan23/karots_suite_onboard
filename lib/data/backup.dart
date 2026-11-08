import 'dart:convert';

import '../sync/match.dart';
import 'db.dart';
import 'models.dart';

/// The app's own data as one file: the catalogue's products and suppliers, and
/// the shop profiles with their last pulls. Never the support secrets.
Future<String> exportBackup(Db db) async {
  final shops = <Map<String, Object?>>[];
  for (final s in await db.shops()) {
    shops.add({...s.toRow(), 'products': await db.shopProducts(s.uid)});
  }
  return const JsonEncoder.withIndent(' ').convert({
    'kind': 'karots_onboard.backup',
    'schema': 1,
    'at': DateTime.now().toIso8601String(),
    'products': [for (final p in await db.products()) p.toJson()],
    'suppliers': [for (final x in await db.suppliers()) x.toRow()],
    'shops': shops,
    'deleted': await db.deletions(),
  });
}

class ImportResult {
  ImportResult(this.products, this.suppliers, this.shops);
  final int products, suppliers, shops;
}

/// Merges a backup in: what's missing is added; the same product (by id, barcode
/// or name) takes the newer edit; a supplier already here (by name) stays; a shop
/// takes the newer pull. Counts what changed.
Future<ImportResult> importBackup(Db db, String text) async {
  final m = jsonDecode(text);
  if (m is! Map || m['kind'] != 'karots_onboard.backup') throw const FormatException('That isn\'t a Karots Onboard backup');
  var products = 0, suppliers = 0, shops = 0;

  // Deletions first: what the other device deleted goes here too, unless it was
  // changed here after that (a product's own time says so).
  for (final r in (m['deleted'] as List? ?? [])) {
    final kind = '${r['kind']}', uid = '${r['uid']}', at = DateTime.parse('${r['at']}');
    final mine = (await db.deletedAt(kind))[uid];
    if (mine != null && !at.isAfter(mine)) continue;
    if (kind == 'product') {
      final p = await db.product(uid);
      if (p != null && p.updatedAt.isAfter(at)) continue;
      if (p != null) await db.deleteProduct(uid);
    } else if (kind == 'supplier') {
      await db.deleteSupplier(uid);
    } else if (kind == 'shop') {
      await db.deleteShop(uid);
    }
    await db.markDeleted(kind, uid, at);
  }
  final goneProducts = await db.deletedAt('product'), goneSuppliers = await db.deletedAt('supplier'), goneShops = await db.deletedAt('shop');

  final match = await Matcher.load(db);
  for (final j in (m['products'] as List? ?? [])) {
    final p = CatalogProduct.fromJson(j as Map);
    final gone = goneProducts[p.uid];
    if (gone != null && !p.updatedAt.isAfter(gone)) continue; // deleted here after its last change
    final here = await db.product(p.uid) ?? match.find(codes: p.allCodes, name: p.name);
    if (here == null) {
      await db.saveProduct(p, touch: false);
      match.add(p);
      products++;
    } else if (p.updatedAt.isAfter(here.updatedAt)) {
      final x = CatalogProduct.fromJson({...p.toJson(), 'uid': here.uid})
        ..kinds.addAll(here.kinds)
        ..sources.addAll(here.sources);
      await db.saveProduct(x, touch: false);
      products++;
    }
  }

  final have = {for (final x in await db.suppliers()) normName(x.name)};
  for (final r in (m['suppliers'] as List? ?? [])) {
    final x = CatalogSupplier.fromRow(r as Map);
    if (goneSuppliers.containsKey(x.uid)) continue;
    if (have.add(normName(x.name))) {
      await db.saveSupplier(x);
      suppliers++;
    }
  }

  final mine = {for (final s in await db.shops()) s.uid: s};
  for (final r in (m['shops'] as List? ?? [])) {
    final s = Shop.fromRow(r as Map);
    if (goneShops.containsKey(s.uid)) continue;
    final here = mine[s.uid];
    final newer = here == null || (s.lastPull != null && (here.lastPull == null || s.lastPull!.isAfter(here.lastPull!)));
    if (!newer) continue;
    await db.saveShop(s);
    await db.replaceShopProducts(s.uid, [
      for (final p in (r['products'] as List? ?? [])) {...(p as Map).cast<String, Object?>()}..remove('shop_uid'),
    ]);
    shops++;
  }
  return ImportResult(products, suppliers, shops);
}
