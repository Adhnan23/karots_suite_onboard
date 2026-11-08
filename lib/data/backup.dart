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

  final match = await Matcher.load(db);
  for (final j in (m['products'] as List? ?? [])) {
    final p = CatalogProduct.fromJson(j as Map);
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
    if (have.add(normName(x.name))) {
      await db.saveSupplier(x);
      suppliers++;
    }
  }

  final mine = {for (final s in await db.shops()) s.uid: s};
  for (final r in (m['shops'] as List? ?? [])) {
    final s = Shop.fromRow(r as Map);
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
