import 'package:flutter/material.dart';

import 'cost_code.dart';
import 'field_kind.dart';
import 'ks_field.dart';
import 'prices.dart';

/// A cost box: digits, or the shop's code letters when it has one (Onboard
/// only). Each letter turns into its digit as it is typed, so the box shows the
/// number, and the letters typed show under it to check against the goods. A
/// letter not in the code stays, with the error under it.
class CostField extends StatefulWidget {
  const CostField({super.key, required this.label, required this.controller, this.code, this.helper, this.onChanged});
  final String label;
  final TextEditingController controller;
  final CostCode? code;
  final String? helper;
  final ValueChanged<String>? onChanged;
  @override
  State<CostField> createState() => _CostFieldState();
}

class _CostFieldState extends State<CostField> {
  /// What was typed, one character for each in the box (letters kept).
  late String typed = widget.controller.text;
  late String _last = widget.controller.text;

  void _changed(String v) {
    // carry the typed characters across the edit: same start, same end, the middle is new
    var p = 0;
    while (p < v.length && p < _last.length && v[p] == _last[p]) {
      p++;
    }
    var q = 0;
    while (q < v.length - p && q < _last.length - p && v[v.length - 1 - q] == _last[_last.length - 1 - q]) {
      q++;
    }
    final keep = typed.length == _last.length ? typed : _last;
    typed = keep.substring(0, p) + v.substring(p, v.length - q) + keep.substring(keep.length - q);
    final c = widget.code;
    if (c != null && c.hasLetters(v)) {
      final d = c.decode(v);
      if (d.error == null) {
        widget.controller.value = TextEditingValue(
          text: d.value,
          selection: TextSelection.collapsed(offset: d.value.length),
        );
        v = d.value;
      }
    }
    _last = widget.controller.text;
    setState(() {});
    widget.onChanged?.call(v);
  }

  /// The letters typed (to check against the goods), then any line the caller adds.
  String? _helper(CostCode? c) {
    final h = [if (c != null && c.hasLetters(typed)) typed.toUpperCase(), ?widget.helper].join('  ');
    return h.isEmpty ? null : h;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.controller,
    builder: (context, v, _) {
      final c = widget.code;
      if (v.text != _last) typed = _last = v.text; // set from outside (a photo read, a restored draft)
      final error = c != null && c.hasLetters(v.text) ? c.decode(v.text).error : null;
      return KsField(
        label: widget.label,
        controller: widget.controller,
        kind: c == null ? FieldKind.number : FieldKind.text,
        keyboard: c == null ? null : TextInputType.visiblePassword,
        suggestions: c == null,
        onChanged: _changed,
        errorText: error,
        helper: _helper(c),
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
  var _markupTyped = false, _costWorkedOut = false;

  PriceInput get _input =>
      PriceInput(cost: cost.text, selling: selling.text, markup: markup.text, per: per.text, markupTyped: _markupTyped, costWorkedOut: _costWorkedOut);

  /// Exactly what's in the cost and selling boxes (letters kept), for a kept draft.
  ({String cost, String selling}) get typed => (cost: cost.text.trim(), selling: selling.text.trim());

  /// The cost and selling price to save (decoded, ÷ applied), or an error.
  ({String cost, String selling, String? error}) read() => resolve(_input, widget.code);

  void _edit(String field, String value) {
    final next = editPrice(_input, field, value, widget.code);
    _markupTyped = next.markupTyped;
    _costWorkedOut = next.costWorkedOut;
    if (field != 'cost' && cost.text != next.cost) cost.text = next.cost;
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
    final each = per.text.trim().isNotEmpty && (double.tryParse(plain(per.text)) ?? 0) != 0 && r.error == null;
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
            errorText: r.error == howManyError ? r.error : null,
            onChanged: (v) => _edit('per', v),
          ),
        ),
      ],
    );
  }
}
