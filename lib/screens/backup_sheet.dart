import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup.dart';
import '../state.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// Export the app's data to a file, or merge one in (another device's, or a backup).
Future<void> showBackup(BuildContext context) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  builder: (ctx) {
    final c = KsTokens.of(ctx);
    final app = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Backup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'The catalogue, suppliers and shop profiles in one file: keep it safe, or import it on your other device. '
            'Support secrets are never in it: add them again on a new device (the key icon).',
            style: TextStyle(color: c.mutedForeground),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Export backup'),
            onPressed: () async {
              final text = await exportBackup(app.db);
              final name = 'karots-onboard-backup-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.json';
              final bytes = Uint8List.fromList(utf8.encode(text));
              if (Platform.isAndroid) {
                await SharePlus.instance.share(
                  ShareParams(
                    files: [XFile.fromData(bytes, name: name, mimeType: 'application/json')],
                    fileNameOverrides: [name],
                  ),
                );
              } else {
                final at = await getSaveLocation(
                  suggestedName: name,
                  acceptedTypeGroups: [
                    const XTypeGroup(label: 'Backup', extensions: ['json']),
                  ],
                );
                if (at == null) return;
                await File(at.path).writeAsBytes(bytes);
                if (ctx.mounted) toast(ctx, 'Saved $name');
              }
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.download_rounded),
            label: const Text('Import backup'),
            onPressed: () async {
              final f = await openFile(
                acceptedTypeGroups: [
                  const XTypeGroup(label: 'Backup', extensions: ['json']),
                ],
              );
              if (f == null || !ctx.mounted) return;
              final r = await guard(ctx, () async => importBackup(app.db, await f.readAsString()));
              if (r == null || !ctx.mounted) return;
              app.changed();
              toast(ctx, 'Merged in: ${r.products} products, ${r.suppliers} suppliers, ${r.shops} shops changed or added');
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  },
);
