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
  // An older shop (before 2026-11-08) has no packs call and no ids in its sheet: its
  // products come without packs, and can't be changed from here until it updates.
  var packs = <int, List<Map>>{};
  try {
    packs = await c.allPacks();
  } on SuiteError catch (e) {
    if (e.status != 404 && e.status != 400) rethrow;
  }
  final match = await Matcher.load(db);
  final kinds = {if (shop.kind.isNotEmpty) shop.kind};
  var known = 0, review = 0;
  final mine = <Map<String, Object?>>[];
  for (final (i, r) in rows.indexed) {
    final remoteId = r.id > 0 ? r.id : -(i + 1);
    final shopCost = r.product.cost; // the shop's own list here keeps it; the catalogue never does
    final p = r.product
      ..cost = ''
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
      'remote_id': remoteId,
      'catalog_uid': hit?.uid,
      'name': p.name,
      'barcode': p.barcode,
      'category': p.category,
      'json': jsonEncode({...p.toJson(), 'cost': shopCost, 'openingQty': r.openingQty}),
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
