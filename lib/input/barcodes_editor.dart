import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'field_kind.dart';
import 'ks_field.dart';

/// A product's other barcodes, one at a time (typed, scanned or read from a photo).
class BarcodesEditor extends StatefulWidget {
  const BarcodesEditor({super.key, required this.codes});
  final List<String> codes;
  @override
  State<BarcodesEditor> createState() => BarcodesEditorState();
}

class BarcodesEditorState extends State<BarcodesEditor> {
  late final codes = [...widget.codes];
  final input = TextEditingController();

  void add() {
    final c = input.text.trim();
    if (c.isEmpty) return;
    setState(() {
      if (!codes.contains(c)) codes.add(c);
      input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final k = KsTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (codes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in codes)
                  InputChip(
                    label: Text(
                      c,
                      style: TextStyle(color: k.foreground, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    deleteButtonTooltipMessage: 'Remove $c',
                    onDeleted: () => setState(() => codes.remove(c)),
                  ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: KsField(label: 'Add a barcode', controller: input, kind: FieldKind.barcode),
            ),
            IconButton(tooltip: 'Add', icon: const Icon(Icons.add_circle_rounded), color: k.brand, onPressed: add),
          ],
        ),
      ],
    );
  }
}
