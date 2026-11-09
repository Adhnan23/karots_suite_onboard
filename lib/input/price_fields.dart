import 'package:flutter/material.dart';

import 'cost_code.dart';
import 'field_kind.dart';
import 'ks_field.dart';
import 'prices.dart';

/// A cost box: digits, or the shop's code letters when it has one (Onboard
/// only), with the number it reads shown under it. [helper] replaces that line.
class CostField extends StatelessWidget {
  const CostField({super.key, required this.label, required this.controller, this.code, this.helper, this.onChanged});
  final String label;
  final TextEditingController controller;
  final CostCode? code;
  final String? helper;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller,
    builder: (context, v, _) {
      final c = code;
      final coded = c != null && c.hasLetters(v.text);
      final d = coded ? c.decode(v.text) : null;
      return KsField(
        label: label,
        controller: controller,
        kind: c == null ? FieldKind.number : FieldKind.text,
        keyboard: c == null ? null : TextInputType.text,
        onChanged: onChanged,
        errorText: d?.error,
        helper: helper ?? (d != null && d.error == null ? '= ${d.value}' : null),
      );
    },
  );
}

/// Cost and selling price with Markup × and the optional ÷ how many (a box's
/// price → one piece). read() gives what to save.
class PriceFields extends StatefulWidget {
  const PriceFields({super.key, required this.cost, required this.selling, this.code});
  final String cost, selling;
  final CostCode? code;
  @override
  State<PriceFields> createState() => PriceFieldsState();
}

class PriceFieldsState extends State<PriceFields> {
  late final cost = TextEditingController(text: widget.cost);
  late final selling = TextEditingController(text: widget.selling);
  late final markup = TextEditingController(text: markupOf(widget.code == null ? widget.cost : widget.code!.decode(widget.cost).value, widget.selling));
  final per = TextEditingController();

  PriceInput get _input => PriceInput(cost: cost.text, selling: selling.text, markup: markup.text, per: per.text);

  /// The cost and selling price to save (decoded, ÷ applied), or an error.
  ({String cost, String selling, String? error}) read() => resolve(_input, widget.code);

  void _edit(String field, String value) {
    final next = editPrice(_input, field, value, widget.code);
    if (field != 'selling' && selling.text != next.selling) selling.text = next.selling;
    if (field != 'markup' && markup.text != next.markup) markup.text = next.markup;
    setState(() {});
  }

  @override
  void dispose() {
    for (final c in [cost, selling, markup, per]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _pair(Widget a, Widget b) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: a),
      const SizedBox(width: 10),
      Expanded(child: b),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final r = read();
    final each = per.text.trim().isNotEmpty && (double.tryParse(per.text.trim()) ?? 0) != 0 && r.error == null;
    return Column(
      children: [
        _pair(
          CostField(
            label: 'Cost price',
            controller: cost,
            code: widget.code,
            helper: each && r.cost.isNotEmpty ? '= ${r.cost} each' : null,
            onChanged: (v) => _edit('cost', v),
          ),
          KsField(
            label: 'Selling price',
            controller: selling,
            kind: FieldKind.number,
            helper: each && r.selling.isNotEmpty ? '= ${r.selling} each' : null,
            onChanged: (v) => _edit('selling', v),
          ),
        ),
        const SizedBox(height: 10),
        _pair(
          KsField(label: 'Markup ×', controller: markup, kind: FieldKind.number, onChanged: (v) => _edit('markup', v)),
          KsField(
            label: '÷ how many',
            controller: per,
            kind: FieldKind.number,
            helper: 'optional',
            errorText: r.error == 'How many must be a number' ? r.error : null,
            onChanged: (v) => _edit('per', v),
          ),
        ),
      ],
    );
  }
}
