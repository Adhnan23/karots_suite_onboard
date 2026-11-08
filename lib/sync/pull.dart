import 'dart:convert';

import '../data/db.dart';
import '../data/models.dart';
import '../suite/client.dart';
import 'match.dart';
import 'suite_csv.dart';

class PullResult {
  PullResult(this.known, this.toReview, this.suppliersKnown, this.suppliersToReview);
  final int known, toReview, suppliersKnown, suppliersToReview;
}

/// Reads a whole shop (signed in already): what it runs and its lists. Products
/// and suppliers the catalogue knows are skipped (and linked); new ones wait in
/// Review. The shop's own list is kept for editing and merging there.
Future<PullResult> pull(Db db, SuiteClient c, Shop shop, {void Function(String)? step}) async {
  step?.call('Reading the shop');
  final me = await c.me();
  final has = me.plugins.contains;
  final fields = has('productplus') ? await c.fields() : <dynamic>[];
  final labels = [
    for (final f in fields)
      if ((f as Map)['isActive'] != false) '${f['label']}',
  ];
  shop.snapshot = {
    'shopName': me.shopName,
    'plugins': me.plugins,
    'stockTake': me.stockTakeEnabled,
    'categories': await c.categories(),
    'units': await c.units(),
    'suppliers': await c.supplierOptions(),
    'fields': fields,
    'alternatives': has('alternatives') ? await c.alternatives() : [],
    'ai': has('aicatalog') ? await c.aiSettings() : {},
  };

  step?.call('Reading products');
  final rows = readProductSheet(await c.productsCsv(customFields: has('productplus')), labels);
  final packs = await c.allPacks();
  final match = await Matcher.load(db);
  final kinds = {if (shop.kind.isNotEmpty) shop.kind};
  var known = 0, review = 0;
  final mine = <Map<String, Object?>>[];
  for (final r in rows) {
    final p = r.product
      ..kinds = {...kinds}
      ..sources = {shop.uid}
      ..packs = [
        for (final k in packs[r.id] ?? const <Map>[])
          Pack(
            name: '${k['name']}',
            size: '${k['size']}',
            selling: '${k['sellingPrice'] ?? ''}',
            wholesale: '${k['wholesalePrice'] ?? ''}',
            barcode: (k['barcodes'] as List? ?? []).isEmpty ? '' : '${(k['barcodes'] as List).first}',
          ),
      ];
    final hit = match.find(codes: p.allCodes, name: p.name);
    if (hit != null) {
      known++;
      if (!hit.sources.contains(shop.uid) || !hit.kinds.containsAll(kinds)) {
        hit.sources.add(shop.uid);
        hit.kinds.addAll(kinds);
        await db.saveProduct(hit);
      }
    } else if (await db.addReview(
      ReviewItem(shopUid: shop.uid, kind: 'product', data: p.toJson()),
      key: p.allCodes.isNotEmpty ? p.allCodes.first : normName(p.name),
    )) {
      review++;
    }
    mine.add({
      'remote_id': r.id,
      'catalog_uid': hit?.uid,
      'name': p.name,
      'barcode': p.barcode,
      'category': p.category,
      'json': jsonEncode({...p.toJson(), 'openingQty': r.openingQty}),
    });
  }
  await db.replaceShopProducts(shop.uid, mine);

  step?.call('Reading suppliers');
  final have = {for (final s in await db.suppliers()) normName(s.name)};
  var sKnown = 0, sReview = 0;
  for (final s in readSupplierSheet(await c.suppliersCsv())) {
    s.kinds = {...kinds};
    s.sources = {shop.uid};
    if (have.contains(normName(s.name))) {
      sKnown++;
    } else if (await db.addReview(
      ReviewItem(shopUid: shop.uid, kind: 'supplier', data: s.toRow()),
      key: normName(s.name),
    )) {
      sReview++;
    }
  }
  shop.lastPull = DateTime.now();
  await db.saveShop(shop);
  return PullResult(known, review, sKnown, sReview);
}
