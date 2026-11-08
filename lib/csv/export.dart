import 'dart:convert';

import 'package:csv/csv.dart';

import '../data/models.dart';
import '../sync/push.dart';

/// The Suite's product import columns (internal/api/admin_import.go).
const productColumns = [
  'name',
  'name_local',
  'barcode',
  'extra_barcodes',
  'category',
  'unit',
  'cost_price',
  'selling_price',
  'wholesale_price',
  'tax_rate',
  'reorder_level',
  'opening_qty',
  'supplier',
  'track_serial',
  'warranty_months',
];
const supplierColumns = ['name', 'contact_person', 'phone', 'address', 'credit_days', 'opening_balance'];

String _sum(List<StockBatch> b) {
  var t = 0.0;
  for (final x in b) {
    t += double.tryParse(x.qty) ?? 0;
  }
  if (t == 0) return '';
  return t == t.roundToDouble() ? t.toInt().toString() : t.toString();
}

/// Products for Products → Sheets → Import (tick "Include custom fields"). A
/// sheet has one opening quantity: several batches add up (their expiries are
/// entered at the shop).
String productsCsv(List<Draft> drafts, Shop s) {
  final labels = [
    for (final f in (s.snapshot['fields'] as List? ?? []))
      if ((f as Map)['isActive'] != false) '${f['label']}',
  ];
  return Csv(autoDetect: false).encode([
    [...productColumns, ...labels],
    for (final d in drafts)
      [
        d.product.name,
        d.product.nameLocal,
        d.product.barcode,
        d.product.barcodes.join(';'),
        d.product.category,
        d.product.unit,
        d.product.cost,
        d.product.selling,
        d.product.wholesale,
        d.product.taxRate,
        '0',
        _sum(d.stock),
        d.newSupplier?.name ?? d.product.supplier,
        '${d.product.trackSerial}',
        '${d.product.warrantyMonths}',
        for (final l in labels) d.product.fields[l] ?? '',
      ],
  ]);
}

/// Suppliers for Suppliers → Sheets → Import.
String suppliersCsv(List<CatalogSupplier> list) => Csv(autoDetect: false).encode([
  supplierColumns,
  for (final x in list) [x.name, x.contact, x.phone, x.address, '${x.creditDays}', ''],
]);

/// The Suite's stock-take sheet (Stock-take → Import), from the shop's last pull:
/// fill counted_qty at the shop. The stock is as of that pull.
String countSheetCsv(List<Map<String, Object?>> shopProducts) => Csv(autoDetect: false).encode([
      ['barcode', 'name', 'current_qty', 'counted_qty', 'cost', 'selling_price', 'wholesale_price', 'batch', 'expiry'],
      for (final r in shopProducts)
        () {
          final j = (jsonDecode('${r['json'] ?? '{}'}') as Map);
          return ['${r['barcode'] ?? ''}', '${r['name'] ?? ''}', '${j['openingQty'] ?? ''}', '', '${j['cost'] ?? ''}', '${j['selling'] ?? ''}', '${j['wholesale'] ?? ''}', '', ''];
        }(),
    ]);
