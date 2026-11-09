import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'field_kind.dart';
import 'ocr.dart';

/// Photo → the lines and words read → tap the ones for this field → its value.
Future<String?> ocrInto(BuildContext context, String label, FieldKind kind) async {
  List<String>? lines;
  try {
    lines = await Ocr.readLines();
  } catch (e) {
    if (context.mounted) toast(context, 'Couldn\'t read the photo: ${errText(e)}', error: true);
    return null;
  }
  if (lines == null || !context.mounted) return null;
  if (lines.isEmpty) {
    toast(context, 'No text found: try again, closer and in good light.', error: true);
    return null;
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _Pick(label: label, kind: kind, lines: lines!),
  );
}

class _Pick extends StatefulWidget {
  const _Pick({required this.label, required this.kind, required this.lines});
  final String label;
  final FieldKind kind;
  final List<String> lines;
  @override
  State<_Pick> createState() => _PickState();
}

class _PickState extends State<_Pick> {
  final value = TextEditingController();

  void add(String piece) {
    final joined = value.text.isEmpty ? piece : (widget.kind == FieldKind.text ? '${value.text} $piece' : '${value.text}$piece');
    final v = widget.kind == FieldKind.text ? joined : filterFor(widget.kind, joined);
    setState(() => value.text = v.isEmpty ? joined : v);
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final words = {for (final l in widget.lines) ...l.split(RegExp(r'\s+'))}.where((w) => w.isNotEmpty).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Tap what goes in “${widget.label}”', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: value,
                decoration: InputDecoration(
                  labelText: widget.label,
                  suffixIcon: IconButton(icon: const Icon(Icons.backspace_outlined), onPressed: () => setState(value.clear)),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'LINES',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.faint),
                  ),
                  const SizedBox(height: 6),
                  for (final l in widget.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KsTokens.radiusSm)),
                        ),
                        onPressed: () => add(l),
                        child: Text(l),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'WORDS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.faint),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final w in words) ActionChip(label: Text(w), onPressed: () => add(w))],
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: FilledButton.icon(
                  onPressed: value.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          filterFor(widget.kind, value.text).isEmpty && widget.kind != FieldKind.text ? value.text.trim() : filterFor(widget.kind, value.text),
                        ),
                  icon: const Icon(Icons.check_rounded),
                  label: Text('Use for ${widget.label}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
