import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../csv/export.dart';
import '../data/models.dart';
import '../state.dart';
import '../sync/match.dart';
import '../sync/push.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// Sheets for a shop that can't be reached: its products (what waits to push, or
/// the catalogue's for its kind) and suppliers, in the Suite's import format.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.shop});
  final Shop shop;
  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  List<Draft> waiting = [], ofKind = [];
  List<CatalogSupplier> suppliers = [];
  bool useWaiting = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  Future<void> load() async {
    final db = AppScope.of(context).db;
    final s = widget.shop;
    final w = [
      for (final o in await db.pending(s.uid))
        if (o.op == 'create') Draft.fromJson(o.data),
    ];
    final k = [
      for (final p in await db.products())
        if (s.kind.isEmpty || p.kinds.contains(s.kind)) fromCatalogue(p),
    ];
    final sup = [
      for (final x in await db.suppliers())
        if (s.kind.isEmpty || x.kinds.contains(s.kind)) x,
    ];
    for (final d in w) {
      final n = d.newSupplier;
      if (n != null && !sup.any((x) => normName(x.name) == normName(n.name))) sup.add(n);
    }
    if (mounted) {
      setState(() {
        waiting = w;
        ofKind = k;
        suppliers = sup;
        useWaiting = w.isNotEmpty;
      });
    }
  }

  Future<void> save(String name, String text) async {
    final bytes = Uint8List.fromList(utf8.encode('﻿$text')); // Excel reads Sinhala / Tamil with the BOM
    if (Platform.isAndroid) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: name, mimeType: 'text/csv')],
          fileNameOverrides: [name],
        ),
      );
      return;
    }
    final at = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (at == null) return;
    await File(at.path).writeAsBytes(bytes);
    if (mounted) toast(context, 'Saved $name');
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final s = widget.shop;
    final list = useWaiting ? waiting : ofKind;
    final slug = s.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return Scaffold(
      appBar: AppBar(title: Text('${s.name} · export sheets')),
      body: Narrow(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Section(
              title: 'Products',
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: true, label: Text('Waiting to push · ${waiting.length}')),
                    ButtonSegment(value: false, label: Text('Catalogue · ${s.kind.isEmpty ? 'all' : s.kind} · ${ofKind.length}')),
                  ],
                  selected: {useWaiting},
                  onSelectionChanged: (v) => setState(() => useWaiting = v.first),
                ),
                const SizedBox(height: 8),
                Text(
                  'In the shop: Products → Sheets ▾ → tick Include custom fields → Import. One opening quantity per product: several batches add up.',
                  style: TextStyle(color: c.mutedForeground, fontSize: 13),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: list.isEmpty ? null : () => save('$slug-products.csv', productsCsv(list, s)),
                  icon: const Icon(Icons.download_rounded),
                  label: Text('Export ${list.length} products'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Section(
              title: 'Suppliers',
              children: [
                Text('In the shop: Suppliers → Sheets ▾ → Import.', style: TextStyle(color: c.mutedForeground, fontSize: 13)),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: suppliers.isEmpty ? null : () => save('$slug-suppliers.csv', suppliersCsv(suppliers)),
                  icon: const Icon(Icons.download_rounded),
                  label: Text('Export ${suppliers.length} suppliers'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
