import 'dart:io';

import 'package:flutter/material.dart';

import 'field_kind.dart';
import 'ocr.dart';
import 'ocr_sheet.dart';
import 'scan.dart';

/// A text field with "read it from a photo" (and, for a barcode, "scan it") so
/// nothing has to be typed.
class KsField extends StatelessWidget {
  const KsField({
    super.key,
    required this.label,
    required this.controller,
    this.kind = FieldKind.text,
    this.helper,
    this.onChanged,
    this.maxLines = 1,
  });
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
      keyboardType: switch (kind) {
        FieldKind.number => const TextInputType.numberWithOptions(decimal: true),
        FieldKind.date => TextInputType.datetime,
        _ => TextInputType.text,
      },
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        hintText: kind == FieldKind.date ? 'YYYY-MM-DD' : null,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (kind == FieldKind.barcode && Platform.isAndroid)
              IconButton(tooltip: 'Scan', icon: const Icon(Icons.qr_code_scanner_rounded), onPressed: () async => _set(await scanBarcode(context))),
            if (ocr.data == true)
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
