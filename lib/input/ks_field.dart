import 'dart:io';

import 'package:flutter/material.dart';

import 'field_kind.dart';
import 'ocr.dart';
import 'ocr_sheet.dart';
import 'scan.dart';

/// A text field with "scan it" for a barcode and, where asked, "read it from a photo".
class KsField extends StatelessWidget {
  const KsField({
    super.key,
    required this.label,
    required this.controller,
    this.kind = FieldKind.text,
    this.helper,
    this.onChanged,
    this.maxLines = 1,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.errorText,
    this.keyboard,
    this.suggestions = true,
    this.ocr = false,
  });

  /// Shows "read it from a photo" (a product's name and local name only: the user, 2026-11-15 —
  /// a barcode is scanned, prices and the rest are typed faster than read).
  final bool ocr;

  /// false: no keyboard suggestions or autocorrect (a box whose text the app rewrites).
  final bool suggestions;
  final String? errorText;

  /// Overrides the keyboard [kind] picks (a coded cost takes letters).
  final TextInputType? keyboard;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final String label;
  final TextEditingController controller;
  final FieldKind kind;
  final String? helper;
  final ValueChanged<String>? onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: Ocr.available(),
    builder: (context, ocr) => TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      focusNode: focusNode,
      autofocus: autofocus,
      enableSuggestions: suggestions,
      autocorrect: suggestions,
      keyboardType:
          keyboard ??
          switch (kind) {
            FieldKind.number => const TextInputType.numberWithOptions(decimal: true),
            FieldKind.date => TextInputType.datetime,
            _ => TextInputType.text,
          },
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: errorText,
        hintText: kind == FieldKind.date ? 'YYYY-MM-DD' : null,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (kind == FieldKind.barcode && Platform.isAndroid)
              IconButton(tooltip: 'Scan', icon: const Icon(Icons.qr_code_scanner_rounded), onPressed: () async => _set(await scanBarcode(context))),
            if (this.ocr && ocr.data == true)
              IconButton(
                tooltip: 'Read from a photo',
                icon: const Icon(Icons.document_scanner_outlined),
                onPressed: () async => _set(await ocrInto(context, label, kind)),
              ),
          ],
        ),
      ),
    ),
  );

  void _set(String? v) {
    if (v == null || v.isEmpty) return;
    controller.text = v;
    onChanged?.call(v);
  }
}
