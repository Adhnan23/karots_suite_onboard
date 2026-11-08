import '../data/models.dart';
import 'match.dart';
import 'push.dart';

/// What a scan or search finds: catalogue products, and the shop's own copy if it
/// already has one (by barcode or name) so stock goes there instead of a twin.
({List<CatalogProduct> catalogue, Map<String, Object?>? inShop}) quickFind(List<CatalogProduct> all, List<Map<String, Object?>> shop, String q) {
  final t = q.trim();
  if (t.isEmpty) return (catalogue: <CatalogProduct>[], inShop: null);
  var hits = [
    for (final p in all)
      if (p.allCodes.contains(t)) p,
  ];
  if (hits.isEmpty) {
    final n = normName(t);
    hits = [
      for (final p in all)
        if (normName(p.name).contains(n)) p,
    ];
  }
  Map<String, Object?>? mine;
  for (final r in shop) {
    final code = '${r['barcode'] ?? ''}';
    if ((code.isNotEmpty && (code == t || hits.any((p) => p.allCodes.contains(code)))) ||
        (hits.length == 1 && normName('${r['name']}') == normName(hits.single.name))) {
      mine = r;
      break;
    }
  }
  return (catalogue: hits, inShop: mine);
}

/// The catalogue product for a shop with what was typed: no category (the shop
/// files it), its prices, and one batch of old stock when there's a quantity.
Draft quickDraft(CatalogProduct p, {required String cost, required String price, required String qty, required String expiry}) {
  final d = fromCatalogue(p);
  d.product
    ..cost = cost.trim()
    ..selling = price.trim();
  if (qty.trim().isNotEmpty) {
    d
      ..mode = StockMode.one
      ..batches = [StockBatch(qty: qty.trim(), expiry: expiry.trim())];
  }
  return d;
}
