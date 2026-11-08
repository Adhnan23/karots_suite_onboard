import '../csv/supplier_list.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'match.dart';

class ListImport {
  ListImport(this.matched, this.toReview);
  final int matched, toReview;
}

/// A supplier's list into the catalogue: a product it already has (any barcode,
/// else the name) gets this supplier's code and prices and its gaps filled (the
/// catalogue's own name and details stay); a new one waits in Review.
Future<ListImport> importSupplierList(Db db, CatalogSupplier sup, String text) async {
  final rows = readSupplierList(text);
  final match = await Matcher.load(db);
  var matched = 0, review = 0;
  for (final r in rows) {
    final offer = Offer(supplierUid: sup.uid, supplierName: sup.name, code: r.code, cost: r.cost, price: r.price);
    final hit = match.find(codes: r.product.allCodes, name: r.product.name);
    if (hit != null) {
      final p = (await db.product(hit.uid))!;
      for (final c in r.product.allCodes) {
        if (!p.allCodes.contains(c)) p.barcode.isEmpty ? p.barcode = c : p.barcodes.add(c);
      }
      for (final e in r.product.fields.entries) {
        p.fields.putIfAbsent(e.key, () => e.value);
      }
      if (p.packs.isEmpty) p.packs = r.product.packs;
      p.offers
        ..removeWhere((o) => o.supplierUid == sup.uid)
        ..add(offer);
      await db.saveProduct(p);
      match.add(p);
      matched++;
    } else {
      final p = r.product..offers = [offer];
      final key = p.allCodes.isNotEmpty ? p.allCodes.first : normName(p.name);
      if (await db.addReview(
        ReviewItem(shopUid: 'supplier:${sup.uid}', kind: 'product', data: p.toJson()),
        key: key,
      ))
        review++;
    }
  }
  return ListImport(matched, review);
}
