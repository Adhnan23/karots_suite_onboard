import 'package:flutter/material.dart';

import '../data/models.dart';
import '../input/field_kind.dart';
import '../input/ks_field.dart';
import '../theme/tokens.dart';

/// A product's packs (Card ×12, Box ×100): name, units in it, price, barcode.
class PacksEditor extends StatefulWidget {
  const PacksEditor({super.key, required this.packs});
  final List<Pack> packs;
  @override
  State<PacksEditor> createState() => PacksEditorState();
}

class _Row {
  _Row(Pack k)
    : name = TextEditingController(text: k.name),
      size = TextEditingController(text: k.size),
      selling = TextEditingController(text: k.selling),
      barcode = TextEditingController(text: k.barcode),
      wholesale = k.wholesale;
  final TextEditingController name, size, selling, barcode;
  final String wholesale;
  Pack read() => Pack(name: name.text.trim(), size: size.text.trim(), selling: selling.text.trim(), wholesale: wholesale, barcode: barcode.text.trim());
}

class PacksEditorState extends State<PacksEditor> {
  late final rows = [for (final k in widget.packs) _Row(k)];

  List<Pack> read() => [
    for (final r in rows)
      if (r.name.text.trim().isNotEmpty && r.size.text.trim().isNotEmpty) r.read(),
  ];

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in rows.indexed)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(KsTokens.radiusSm)),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: r.name,
                        decoration: const InputDecoration(labelText: 'Pack name'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: KsField(label: 'Units in it', controller: r.size, kind: FieldKind.number),
                    ),
                    IconButton(tooltip: 'Remove', icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => rows.removeAt(i))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: KsField(label: 'Pack price', controller: r.selling, kind: FieldKind.number),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: KsField(label: 'Pack barcode', controller: r.barcode, kind: FieldKind.barcode),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => rows.add(_Row(Pack(name: '', size: '')))),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add pack'),
          ),
        ),
      ],
    );
  }
}
