import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../input/barcodes_editor.dart';
import '../input/category_field.dart';
import '../input/cost_code.dart';
import '../input/field_kind.dart';
import '../input/ks_field.dart';
import '../input/price_fields.dart';
import '../input/supplier_field.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'packs_editor.dart';

/// The product's own details, shared by the catalogue and a shop's editor. Every
/// field reads from a photo too. fieldLabels: the custom fields to show.
class ProductForm extends StatefulWidget {
  const ProductForm({super.key, required this.product, this.fieldLabels = const [], this.categories, this.units = const [], this.suppliers, this.costCode});
  final CatalogProduct product;
  final List<String> fieldLabels;

  /// The shop's category tree (paths). Null in the catalogue: it keeps products
  /// only, and each shop has its own tree.
  final List<String>? categories;
  final List<String> units;

  /// The catalogue's suppliers, to pick the product's usual one (catalogue only;
  /// a shop's editor has its own).
  final List<CatSupplier>? suppliers;

  /// The shop's cost letters (Onboard at a shop; null in the catalogue and Shelf).
  final CostCode? costCode;
  @override
  State<ProductForm> createState() => ProductFormState();
}

class ProductFormState extends State<ProductForm> {
  CatalogProduct get p => widget.product;
  late final name = TextEditingController(text: p.name);
  late final local = TextEditingController(text: p.nameLocal);
  late final barcode = TextEditingController(text: p.barcode);
  final extra = GlobalKey<BarcodesEditorState>();
  late final category = TextEditingController(text: p.category);
  late final unit = TextEditingController(text: p.unit);
  final prices = GlobalKey<PriceFieldsState>();
  late final wholesale = TextEditingController(text: p.wholesale);
  late final warranty = TextEditingController(text: p.warrantyMonths == 0 ? '' : '${p.warrantyMonths}');
  late final fields = {
    for (final l in {...widget.fieldLabels, ...p.fields.keys}) l: TextEditingController(text: p.fields[l] ?? ''),
  };
  final packs = GlobalKey<PacksEditorState>();
  late String supplierChoice = () {
    final name = p.supplier.trim();
    if (name.isEmpty) return 'none';
    final hit = (widget.suppliers ?? []).where((x) => x.name.toLowerCase() == name.toLowerCase()).firstOrNull;
    return hit == null ? 'new:$name' : 'cat:${hit.uid}';
  }();

  String get _supplierName => supplierChoice.startsWith('new:')
      ? supplierChoice.substring(4)
      : supplierChoice.startsWith('cat:')
      ? (widget.suppliers ?? []).where((x) => 'cat:${x.uid}' == supplierChoice).firstOrNull?.name ?? p.supplier
      : '';

  late final String _initial;

  @override
  void initState() {
    super.initState();
    _initial = jsonEncode(read().toJson());
  }

  /// Anything typed or picked since the form opened.
  bool get changed => jsonEncode(read().toJson()) != _initial;

  /// The AI answer picked, for the shop to learn on save (AI Assistant's extra).
  Map<String, dynamic>? aiPick;

  /// Fills fields from outside (AI Identify); custom fields by label.
  void fill({String? name, String? category, Map<String, String>? fieldValues, Map<String, dynamic>? pick}) {
    setState(() {
      aiPick = pick ?? aiPick;
      if (name != null && name.isNotEmpty) this.name.text = name;
      if (category != null && category.isNotEmpty) this.category.text = category;
      for (final e in (fieldValues ?? {}).entries) {
        (fields[e.key] ??= TextEditingController()).text = e.value;
      }
    });
  }

  /// Why the prices can't be saved yet (a cost the shop's code can't read), else null.
  String? problem() => prices.currentState?.read().error;

  /// The product as edited (same uid).
  CatalogProduct read() {
    final pr = prices.currentState?.read();
    return CatalogProduct.fromJson({
      ...p.toJson(),
      'name': name.text.trim(),
      'name_local': local.text.trim(),
      'barcode': barcode.text.trim(),
      'category': category.text.trim(),
      'unit': unit.text.trim().isEmpty ? 'pcs' : unit.text.trim(),
      'cost': pr?.cost ?? p.cost,
      'selling': pr?.selling ?? p.selling,
      'wholesale': wholesale.text.trim(),
      'warranty_months': int.tryParse(warranty.text.trim()) ?? 0,
      'supplier': widget.suppliers == null ? p.supplier : _supplierName,
      'barcodes': [
        for (final b in extra.currentState?.codes ?? p.barcodes)
          if (b != barcode.text.trim()) b,
      ],
      'packs': [for (final k in packs.currentState?.read() ?? p.packs) k.toMap()],
      'fields': {
        for (final e in fields.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
      },
    });
  }

  Widget _pair(Widget a, Widget b) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: a),
      const SizedBox(width: 10),
      Expanded(child: b),
    ],
  );

  Widget _pick(String label, TextEditingController ctl, List<String> options, {String? helper}) => options.isEmpty
      ? KsField(label: label, controller: ctl, helper: helper)
      : Autocomplete<String>(
          initialValue: ctl.value,
          optionsBuilder: (v) => options.where((o) => o.toLowerCase().contains(v.text.toLowerCase())).take(30),
          onSelected: (v) => ctl.text = v,
          fieldViewBuilder: (context, textCtl, focus, submit) {
            textCtl.addListener(() => ctl.text = textCtl.text);
            return TextField(
              controller: textCtl,
              focusNode: focus,
              decoration: InputDecoration(labelText: label, helperText: helper),
            );
          },
        );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Section(
        title: 'Product',
        children: [
          KsField(label: 'Name', controller: name),
          const SizedBox(height: 10),
          KsField(label: 'Local name', controller: local, helper: 'Sinhala or Tamil, as the shop says it'),
          const SizedBox(height: 10),
          KsField(label: 'Barcode', controller: barcode, kind: FieldKind.barcode),
          const SizedBox(height: 10),
          Text('Other barcodes', style: TextStyle(fontSize: 13, color: KsTokens.of(context).mutedForeground)),
          const SizedBox(height: 6),
          BarcodesEditor(key: extra, codes: p.barcodes),
          const SizedBox(height: 10),
          if (widget.categories != null) ...[CategoryField(controller: category, paths: widget.categories!), const SizedBox(height: 10)],
          _pick('Unit', unit, widget.units),
          if (widget.suppliers != null) ...[
            const SizedBox(height: 10),
            SupplierField(value: supplierChoice, shop: const [], catalogue: widget.suppliers!, onChanged: (v) => setState(() => supplierChoice = v)),
          ],
        ],
      ),
      const SizedBox(height: 12),
      Section(
        title: 'Prices',
        children: [
          PriceFields(key: prices, cost: p.cost, selling: p.selling, code: widget.costCode),
          const SizedBox(height: 10),
          _pair(
            KsField(label: 'Wholesale price', controller: wholesale, kind: FieldKind.number),
            KsField(label: 'Warranty months', controller: warranty, kind: FieldKind.number),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Section(
        title: 'Packs',
        children: [PacksEditor(key: packs, packs: p.packs)],
      ),
      if (fields.isNotEmpty) ...[
        const SizedBox(height: 12),
        Section(
          title: 'More details',
          children: [
            for (final e in fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: KsField(label: e.key, controller: e.value),
              ),
          ],
        ),
      ],
    ],
  );
}
