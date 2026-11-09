import 'package:flutter/material.dart';

import '../input/cost_code.dart';
import '../input/field_kind.dart';
import '../input/ks_field.dart';
import '../input/price_fields.dart';
import '../sync/push.dart';
import '../theme/tokens.dart';

/// Old stock: none, one batch, or several batches each with expiry and prices.
class StockEditor extends StatefulWidget {
  const StockEditor({super.key, required this.draft, this.code});
  final Draft draft;

  /// The shop's cost letters (Onboard only), for the batches' cost boxes.
  final CostCode? code;
  @override
  State<StockEditor> createState() => StockEditorState();
}

class _B {
  _B(StockBatch b)
    : qty = TextEditingController(text: b.qty),
      expiry = TextEditingController(text: b.expiry),
      cost = TextEditingController(text: b.cost),
      selling = TextEditingController(text: b.selling);
  final TextEditingController qty, expiry, cost, selling;
  StockBatch read(CostCode? code) => StockBatch(
    qty: qty.text.trim(),
    expiry: expiry.text.trim(),
    cost: code == null ? cost.text.trim() : code.decode(cost.text).value,
    selling: selling.text.trim(),
  );
}

class StockEditorState extends State<StockEditor> {
  late StockMode mode = widget.draft.mode;
  late final rows = [
    for (final b in widget.draft.batches.isEmpty ? [StockBatch()] : widget.draft.batches) _B(b),
  ];

  /// Writes the editor's state into the draft; raw keeps cost letters as typed
  /// (a kept draft), else costs are decoded for saving.
  void apply({bool raw = false}) {
    widget.draft
      ..mode = mode
      ..batches = [for (final r in rows) r.read(raw ? null : widget.code)];
  }

  /// A batch cost the shop's code can't read, else null.
  String? problem() {
    final c = widget.code;
    if (c == null || mode == StockMode.none) return null;
    for (final r in mode == StockMode.one ? rows.take(1) : rows) {
      final e = c.decode(r.cost.text).error;
      if (e != null) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final shown = mode == StockMode.none ? <_B>[] : (mode == StockMode.one ? rows.take(1).toList() : rows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<StockMode>(
          segments: const [
            ButtonSegment(value: StockMode.none, label: Text('No stock')),
            ButtonSegment(value: StockMode.one, label: Text('One batch')),
            ButtonSegment(value: StockMode.several, label: Text('Several')),
          ],
          selected: {mode},
          onSelectionChanged: (v) => setState(() => mode = v.first),
        ),
        const SizedBox(height: 6),
        Text(
          mode == StockMode.none ? 'Only the product: stock is counted later at the shop.' : 'Old stock the shop already has: no bill, no money, nothing owed.',
          style: TextStyle(color: c.mutedForeground, fontSize: 13),
        ),
        for (final (i, r) in shown.indexed)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(KsTokens.radiusSm)),
            child: Column(
              children: [
                Row(
                  children: [
                    if (mode == StockMode.several)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    Expanded(
                      child: KsField(label: 'Quantity', controller: r.qty, kind: FieldKind.number),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: KsField(label: 'Expiry', controller: r.expiry, kind: FieldKind.date),
                    ),
                    if (mode == StockMode.several && rows.length > 1)
                      IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => rows.remove(r))),
                  ],
                ),
                if (mode == StockMode.several && i > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: CostField(label: 'Cost (blank = product\'s)', controller: r.cost, code: widget.code),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: KsField(label: 'Price (blank = product\'s)', controller: r.selling, kind: FieldKind.number),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        if (mode == StockMode.several)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(
                onPressed: () => setState(() => rows.add(_B(StockBatch()))),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add batch'),
              ),
            ),
          ),
      ],
    );
  }
}
