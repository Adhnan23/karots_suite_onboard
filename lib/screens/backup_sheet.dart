import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/backup.dart';
import '../state.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'backup_file.dart';
import 'sync_screen.dart';
import 'team_screen.dart';
import 'wipe_sheet.dart';

/// Export the app's data to a file, or merge one in (another device's, or a backup).
Future<void> showBackup(BuildContext context) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  isScrollControlled: true, // taller than a small phone: it scrolls
  builder: (ctx) {
    final c = KsTokens.of(ctx);
    final app = AppScope.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Backup and sync', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'The catalogue, suppliers and shop profiles in one file: keep it safe, or import it on your other device. '
            'Support secrets are never in it: add them again on a new device (the key icon).',
            style: TextStyle(color: c.mutedForeground),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.groups_rounded),
            label: const Text('Team: keep my devices the same'),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TeamScreen()));
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.wifi_tethering_rounded),
            label: const Text('Let another device sync'),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncHostScreen()));
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Sync with a device'),
            onPressed: () {
              Navigator.pop(ctx);
              syncWithDevice(context);
            },
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Export backup'),
            onPressed: () async {
              final name = backupName(), text = await exportBackup(app.db);
              if (!ctx.mounted) return;
              if (await saveBackupFile(ctx, text, name) && ctx.mounted && !Platform.isAndroid) toast(ctx, 'Saved $name');
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
          const SizedBox(height: 18),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: c.danger),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Wipe…'),
            onPressed: () {
              Navigator.pop(ctx);
              showWipe(context);
            },
          ),
        ],
      ),
    );
  },
);
