import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../csv/supplier_list.dart';
import '../data/models.dart';
import '../state.dart';
import '../sync/supplier_import.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'suppliers_screen.dart';

/// One supplier: their details, their list into the catalogue (the standard
/// CSV), and what they sell as the catalogue knows it.
class SupplierPage extends StatefulWidget {
  const SupplierPage({super.key, required this.supplier});
  final CatalogSupplier supplier;
  @override
  State<SupplierPage> createState() => _SupplierPageState();
}

class _SupplierPageState extends State<SupplierPage> {
  late CatalogSupplier s = widget.supplier;
  List<CatalogProduct> sells = [];
  String q = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  Future<void> load() async {
    final all = await AppScope.of(context).db.products();
    final x = [
      for (final p in all)
        if (p.supplier.toLowerCase() == s.name.toLowerCase()) p,
    ];
    if (mounted) setState(() => sells = x);
  }

  Future<void> template() async {
    final bytes = Uint8List.fromList(utf8.encode('﻿${supplierListTemplate()}'));
    const name = 'supplier-list-template.csv';
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

  Future<void> import() async {
    final app = AppScope.of(context);
    final f = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (f == null || !mounted) return;
    final r = await guard(context, () async => importSupplierList(app.db, s, await f.readAsString()));
    if (r == null || !mounted) return;
    app.changed();
    toast(context, '${r.matched} already in the catalogue got ${s.name}\'s prices · ${r.toReview} new wait in Review');
    load();
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final n = q.trim().toLowerCase();
    final list = [
      for (final x in sells)
        if (n.isEmpty || x.name.toLowerCase().contains(n) || x.allCodes.any((c) => c.contains(n))) x,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(s.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final db = AppScope.of(context).db;
              final x = await editSupplier(context, s);
              if (x == null) return;
              await db.saveSupplier(x);
              setState(() => s = x);
            },
          ),
        ],
      ),
      body: Narrow(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text(
              [s.contact, s.phone, s.address, if (s.creditDays > 0) '${s.creditDays} days credit'].where((x) => x.isNotEmpty).join(' · '),
              style: TextStyle(color: c.mutedForeground),
            ),
            const SizedBox(height: 12),
            Section(
              title: 'Their list',
              children: [
                Text(
                  'Shape their product list into the standard CSV (download the template), then import it. Products the catalogue has get their gaps filled; new ones wait in Review. '
                  'Extra columns (Generic name, Strength…) are kept as details.',
                  style: TextStyle(color: c.mutedForeground, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(onPressed: import, icon: const Icon(Icons.upload_file_rounded), label: const Text('Import list')),
                    OutlinedButton.icon(onPressed: template, icon: const Icon(Icons.description_outlined), label: const Text('Download template')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Section(
              title: 'Sells · ${sells.length}',
              children: [
                if (sells.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search name or barcode'),
                      onChanged: (v) => setState(() => q = v),
                    ),
                  ),
                if (sells.isEmpty) Text('Nothing yet: import their list.', style: TextStyle(color: c.faint)),
                for (final p in list.take(300))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name),
                    subtitle: p.barcode.isEmpty ? null : Text(p.barcode),
                    trailing: p.selling.isEmpty ? null : Text('Rs ${p.selling}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
