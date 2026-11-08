import 'package:flutter/material.dart';

import '../data/models.dart';
import '../input/field_kind.dart';
import '../input/ks_field.dart';
import '../ui/kit.dart';
import 'packs_editor.dart';

/// The product's own details, shared by the catalogue and a shop's editor. Every
/// field reads from a photo too. fieldLabels: the custom fields to show.
class ProductForm extends StatefulWidget {
  const ProductForm({super.key, required this.product, this.fieldLabels = const [], this.categories = const [], this.units = const []});
  final CatalogProduct product;
  final List<String> fieldLabels;
  final List<String> categories, units;
  @override
  State<ProductForm> createState() => ProductFormState();
}

class ProductFormState extends State<ProductForm> {
  CatalogProduct get p => widget.product;
  late final name = TextEditingController(text: p.name);
  late final local = TextEditingController(text: p.nameLocal);
  late final barcode = TextEditingController(text: p.barcode);
  late final extra = TextEditingController(text: p.barcodes.join(' '));
  late final category = TextEditingController(text: p.category);
  late final unit = TextEditingController(text: p.unit);
  late final cost = TextEditingController(text: p.cost);
  late final selling = TextEditingController(text: p.selling);
  late final wholesale = TextEditingController(text: p.wholesale);
  late final warranty = TextEditingController(text: p.warrantyMonths == 0 ? '' : '${p.warrantyMonths}');
  late final fields = {
    for (final l in {...widget.fieldLabels, ...p.fields.keys}) l: TextEditingController(text: p.fields[l] ?? ''),
  };
  final packs = GlobalKey<PacksEditorState>();

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

  /// The product as edited (same uid).
  CatalogProduct read() => CatalogProduct.fromJson({
    ...p.toJson(),
    'name': name.text.trim(),
    'name_local': local.text.trim(),
    'barcode': barcode.text.trim(),
    'category': category.text.trim(),
    'unit': unit.text.trim().isEmpty ? 'pcs' : unit.text.trim(),
    'cost': cost.text.trim(),
    'selling': selling.text.trim(),
    'wholesale': wholesale.text.trim(),
    'warranty_months': int.tryParse(warranty.text.trim()) ?? 0,
    'barcodes': [
      for (final b in extra.text.split(RegExp(r'[\s,;]+')))
        if (b.isNotEmpty && b != barcode.text.trim()) b,
    ],
    'packs': [for (final k in packs.currentState?.read() ?? p.packs) k.toMap()],
    'fields': {
      for (final e in fields.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    },
  });

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
          _pair(
            KsField(label: 'Barcode', controller: barcode, kind: FieldKind.barcode),
            KsField(label: 'Other barcodes', controller: extra, kind: FieldKind.barcode),
          ),
          const SizedBox(height: 10),
          _pair(_pick('Category', category, widget.categories, helper: 'A > B'), _pick('Unit', unit, widget.units)),
        ],
      ),
      const SizedBox(height: 12),
      Section(
        title: 'Prices',
        children: [
          _pair(
            KsField(label: 'Cost price', controller: cost, kind: FieldKind.number),
            KsField(label: 'Selling price', controller: selling, kind: FieldKind.number),
          ),
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
