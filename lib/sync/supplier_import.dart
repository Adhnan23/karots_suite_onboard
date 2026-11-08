import '../csv/supplier_list.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'match.dart';

class ListImport {
  ListImport(this.matched, this.toReview);
  final int matched, toReview;
}

/// A supplier's list into the catalogue: a product it already has (any barcode,
/// else the name) gets its gaps filled, and this supplier if it had none (the
/// catalogue's own name, price and details stay); a new one waits in Review.
Future<ListImport> importSupplierList(Db db, CatalogSupplier sup, String text) async {
  final match = await Matcher.load(db);
  var matched = 0, review = 0;
  for (final r in readSupplierList(text)) {
    final hit = match.find(codes: r.allCodes, name: r.name);
    if (hit != null) {
      final p = (await db.product(hit.uid))!;
      for (final c in r.allCodes) {
        if (!p.allCodes.contains(c)) p.barcode.isEmpty ? p.barcode = c : p.barcodes.add(c);
      }
      for (final e in r.fields.entries) {
        p.fields.putIfAbsent(e.key, () => e.value);
      }
      if (p.packs.isEmpty) p.packs = r.packs;
      if (p.selling.isEmpty) p.selling = r.selling;
      if (p.supplier.isEmpty) p.supplier = sup.name;
      await db.saveProduct(p);
      match.add(p);
      matched++;
    } else {
      r.supplier = sup.name;
      final key = r.allCodes.isNotEmpty ? r.allCodes.first : normName(r.name);
      final added = await db.addReview(
        ReviewItem(shopUid: 'supplier:${sup.uid}', kind: 'product', data: r.toJson()),
        key: key,
      );
      if (added) review++;
    }
  }
  return ListImport(matched, review);
}
