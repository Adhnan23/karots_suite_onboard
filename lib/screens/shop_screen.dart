import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../state.dart';
import '../sync/pull.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'connect_sheet.dart';
import 'shops_screen.dart';

/// Extra actions on a shop (the product list, new product, Alternatives, export…),
/// added by the screens that do them.
typedef ShopAction = ({IconData icon, String label, bool needsConnection, void Function(BuildContext, Shop) open});
final shopActions = <ShopAction>[];

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.shop});
  final Shop shop;
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  String step = '';
  Shop get s => widget.shop;

  Future<void> doPull() async {
    final app = AppScope.of(context);
    final c = app.session(s);
    if (c == null) return;
    final r = await guard(context, () => pull(app.db, c, s, step: (x) => setState(() => step = x)));
    setState(() => step = '');
    app.changed();
    if (r != null && mounted) {
      toast(context, '${r.known + r.toReview} products: ${r.toReview} new for Review · ${r.suppliersToReview} new suppliers');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = KsTokens.of(context);
    final on = app.connected(s);
    final snap = s.snapshot;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async => (await editShop(context, s)) != null ? setState(() {}) : null,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text('Delete ${s.name}?'),
                  content: const Text('Only this profile goes. The catalogue keeps everything it took from the shop.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (yes == true) {
                await app.db.deleteShop(s.uid);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Narrow(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Section(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s.address, style: TextStyle(color: c.mutedForeground)),
                    ),
                    on ? Tag('Connected', tone: c.success) : Tag('Not connected'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (s.kind.isNotEmpty) s.kind,
                    if (s.installId.isNotEmpty) 'install ${s.installId}',
                    s.lastPull == null ? 'never pulled' : 'pulled ${DateFormat('d MMM, HH:mm').format(s.lastPull!)}',
                  ].join(' · '),
                  style: TextStyle(color: c.faint, fontSize: 13),
                ),
                if (s.plugins.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final p in s.plugins) Tag(p)]),
                ],
                if (snap['stockTake'] == false) ...[const SizedBox(height: 10), Tag('Stock-take is off: old stock can\'t be added', tone: c.warning)],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: on
                          ? OutlinedButton.icon(
                              onPressed: () {
                                app.disconnect(s);
                                setState(() {});
                              },
                              icon: const Icon(Icons.link_off_rounded),
                              label: const Text('Disconnect'),
                            )
                          : FilledButton.icon(
                              onPressed: () async {
                                if (await connectShop(context, s)) setState(() {});
                              },
                              icon: const Icon(Icons.link_rounded),
                              label: const Text('Connect'),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: on && step.isEmpty ? doPull : null,
                        icon: step.isEmpty
                            ? const Icon(Icons.download_rounded)
                            : const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        label: Text(step.isEmpty ? 'Pull' : step),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final a in shopActions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(a.icon, color: c.foreground),
                    title: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: a.needsConnection && !on ? const Text('Connect first') : null,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    enabled: !a.needsConnection || on,
                    onTap: () => a.open(context, s),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
