import '../data/models.dart';

/// A new product from an existing one (another flavour or size): every detail
/// copied, but its own id, and no barcodes (its packs' too).
CatalogProduct copyAsVariant(CatalogProduct p) {
  final c = CatalogProduct.fromJson({...p.toJson(), 'uid': newUid(), 'name': '${p.name} (copy)', 'barcode': '', 'barcodes': []});
  for (final k in c.packs) {
    k.barcode = '';
  }
  return c;
}
