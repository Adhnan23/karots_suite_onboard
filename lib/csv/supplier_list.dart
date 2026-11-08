import 'package:csv/csv.dart';

import '../data/models.dart';

/// The standard supplier list: these columns (any case); any other column is an
/// extra detail kept on the product under its header (Generic name, Strength…).
/// No cost: it differs by supplier and changes, and is typed at the shop.
const supplierListColumns = ['name', 'barcode', 'extra_barcodes', 'unit', 'price', 'pack_name', 'pack_size', 'pack_price'];

/// The template: the columns, two example details, and one example row.
String supplierListTemplate() => Csv(autoDetect: false).encode([
  [...supplierListColumns, 'Generic name', 'Strength'],
  ['Panadol 500mg Tablets', '4792210100015', '4792210100022', 'pcs', '10.00', 'Card', '12', '115.00', 'Paracetamol', '500 mg'],
]);

/// The products on a supplier's list.
List<CatalogProduct> readSupplierList(String text) {
  final all = Csv(autoDetect: false).decode(text.startsWith('\uFEFF') ? text.substring(1) : text);
  if (all.isEmpty) return [];
  final head = [for (final h in all.first) '$h'.trim()];
  final key = [for (final h in head) h.toLowerCase().replaceAll(' ', '_')];
  if (!key.contains('name')) throw const FormatException('The list needs a "name" column: download the template to see the shape');
  final out = <CatalogProduct>[];
  for (final r in all.skip(1)) {
    String get(String k) {
      final i = key.indexOf(k);
      return i < 0 || i >= r.length ? '' : '${r[i]}'.trim();
    }

    final name = get('name');
    if (name.isEmpty) continue;
    final packName = get('pack_name'), packSize = get('pack_size');
    out.add(
      CatalogProduct(
        name: name,
        barcode: get('barcode'),
        barcodes: [
          for (final b in get('extra_barcodes').split(RegExp(r'[;,]')))
            if (b.trim().isNotEmpty) b.trim(),
        ],
        unit: get('unit').isEmpty ? 'pcs' : get('unit'),
        selling: get('price'),
        packs: [if (packName.isNotEmpty && packSize.isNotEmpty) Pack(name: packName, size: packSize, selling: get('pack_price'))],
        fields: {
          for (final (i, h) in head.indexed)
            if (h.isNotEmpty && !supplierListColumns.contains(key[i]) && i < r.length && '${r[i]}'.trim().isNotEmpty) h: '${r[i]}'.trim(),
        },
      ),
    );
  }
  return out;
}
