import 'dart:async';

import 'package:flutter/material.dart';

import '../state.dart';
import '../sync/device_sync.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// This device open for another on the same Wi-Fi: its address and a code, while
/// the screen stays open.
class SyncHostScreen extends StatefulWidget {
  const SyncHostScreen({super.key});
  @override
  State<SyncHostScreen> createState() => _SyncHostScreenState();
}

class _SyncHostScreenState extends State<SyncHostScreen> {
  SyncHost? host;
  AppState? app;
  Timer? tick; // notices when it closed itself after wrong codes
  List<String> addresses = [];
  String error = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    app = AppScope.of(context);
    if (host != null || error.isNotEmpty) return;
    final db = app!.db;
    () async {
      try {
        final h = await SyncHost.start(db, port: 8767); // the team's sync keeps 8765
        final a = await SyncHost.addresses();
        if (!mounted) {
          await h.stop();
          return;
        }
        setState(() {
          host = h;
          addresses = a;
        });
        tick = Timer.periodic(const Duration(seconds: 2), (_) => mounted ? setState(() {}) : null);
      } catch (e) {
        if (mounted) setState(() => error = 'Couldn\'t open for syncing: ${errText(e)}');
      }
    }();
  }

  @override
  void dispose() {
    tick?.cancel();
    host?.stop();
    app?.changed(); // what the other device sent shows in the lists
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final h = host;
    return Scaffold(
      appBar: AppBar(title: const Text('Let another device sync')),
      body: Narrow(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (error.isNotEmpty) Text(error, style: TextStyle(color: c.danger)),
            if (h == null && error.isEmpty) const LinearProgressIndicator(),
            if (h != null && h.closed) Text('Closed after 5 wrong codes. Go back and open it again for a new code.', style: TextStyle(color: c.danger)),
            if (h != null && !h.closed) ...[
              Text('On the other device: Shops → Backup → Sync with a device, and type these.', style: TextStyle(color: c.mutedForeground)),
              const SizedBox(height: 16),
              Section(
                title: 'Address',
                children: [
                  for (final a in addresses) SelectableText('$a:${h.port}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  if (addresses.isEmpty) const Text('Not on a network'),
                ],
              ),
              const SizedBox(height: 12),
              Section(
                title: 'Code',
                children: [
                  Text(
                    h.code,
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 6, color: c.foreground),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StepLine(
                h.step,
                idle: Text('Waiting for the other device…', style: TextStyle(color: c.mutedForeground)),
              ),
              const SizedBox(height: 12),
              Text(
                'Open only while this screen is: going back closes it. Support secrets never travel here (send them sealed under the key icon).',
                style: TextStyle(color: c.faint, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sync with the device showing its address and code.
Future<void> syncWithDevice(BuildContext context) async {
  final app = AppScope.of(context);
  final address = TextEditingController();
  final code = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Sync with a device'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: address,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Its address (e.g. 10.61.223.227:8765)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: code,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Its 6-digit code'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sync')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final r = await withSteps(
    context,
    'Syncing',
    (step) => syncWith(app.db, address.text.trim(), code.text.trim(), step: step),
    note: 'A whole catalogue takes a few minutes. Keep the other device on its sync screen.',
  );
  if (r == null || !context.mounted) return;
  app.changed();
  toast(
    context,
    'Synced: took ${r.got.products} products, ${r.got.suppliers} suppliers, ${r.got.shops} shops · '
    'gave ${r.sent.products} products, ${r.sent.suppliers} suppliers, ${r.sent.shops} shops',
  );
}
