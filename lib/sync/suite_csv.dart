import 'package:csv/csv.dart';

import '../data/models.dart';

/// One row of a shop's products sheet (export ?ids=1): its id there and the product.
class SheetRow {
  SheetRow(this.id, this.product, this.openingQty);
  final int id;
  final CatalogProduct product;
  final String openingQty;
}

List<Map<String, String>> _rows(String text) {
  final all = Csv(autoDetect: false).decode(text.startsWith('﻿') ? text.substring(1) : text);
  if (all.isEmpty) return [];
  final head = [for (final h in all.first) '$h'.trim()];
  return [
    for (final r in all.skip(1))
      if (r.any((c) => '$c'.trim().isNotEmpty)) {for (final (i, h) in head.indexed) h: i < r.length ? '${r[i]}' : ''},
  ];
}

/// The Suite's products export (internal/api/admin_import.go columns) with custom
/// field columns named by their labels.
List<SheetRow> readProductSheet(String text, List<String> fieldLabels) => [
  for (final r in _rows(text))
    SheetRow(
      int.tryParse(r['id'] ?? '') ?? 0,
      CatalogProduct(
        name: r['name']!.trim(),
        nameLocal: r['name_local'] ?? '',
        barcode: r['barcode'] ?? '',
        barcodes: [
          for (final b in (r['extra_barcodes'] ?? '').split(';'))
            if (b.trim().isNotEmpty) b.trim(),
        ],
        category: r['category'] ?? '',
        unit: r['unit'] ?? 'pcs',
        cost: r['cost_price'] ?? '',
        selling: r['selling_price'] ?? '',
        wholesale: r['wholesale_price'] ?? '',
        taxRate: r['tax_rate'] ?? '',
        supplier: r['supplier'] ?? '',
        trackSerial: r['track_serial'] == 'true',
        warrantyMonths: int.tryParse(r['warranty_months'] ?? '') ?? 0,
        fields: {
          for (final l in fieldLabels)
            if ((r[l] ?? '').trim().isNotEmpty) l: r[l]!.trim(),
        },
      ),
      r['opening_qty'] ?? '',
    ),
];

/// The Suite's suppliers export (name, contact_person, phone, address, credit_days, opening_balance).
List<CatalogSupplier> readSupplierSheet(String text) => [
  for (final r in _rows(text))
    CatalogSupplier(
      name: r['name']!.trim(),
      contact: r['contact_person'] ?? '',
      phone: r['phone'] ?? '',
      address: r['address'] ?? '',
      creditDays: int.tryParse(r['credit_days'] ?? '') ?? 0,
    ),
];
