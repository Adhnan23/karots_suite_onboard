import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/backup.dart';
import '../lock/app_identity.dart';
import '../settings/secrets.dart';
import '../state.dart';
import '../suite/support_pin.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'backup_file.dart';

typedef SaveBackup = Future<bool> Function(String text, String name);

/// Wipe what's ticked (or everything): this hour's install-ID code first, then a
/// backup the person saves, then the wipe. A backup that isn't saved stops it.
Future<void> showWipe(BuildContext context, {SaveBackup? save}) async {
  final app = AppScope.of(context);
  final n = await app.db.counts();
  final secrets = (await Secrets(app.store).all()).length;
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _WipeSheet(app: app, n: n, secrets: secrets, save: save),
  );
}

class _WipeSheet extends StatefulWidget {
  const _WipeSheet({required this.app, required this.n, required this.secrets, this.save});
  final AppState app;
  final ({int products, int suppliers, int review, int shops, int pending}) n;
  final int secrets;
  final SaveBackup? save;
  @override
  State<_WipeSheet> createState() => _WipeSheetState();
}

class _WipeSheetState extends State<_WipeSheet> {
  var products = false, suppliers = false, review = false, shops = false, secrets = false;
  bool get any => products || suppliers || review || shops || secrets;

  Future<void> _wipe() async {
    if (!any || !await _code() || !mounted) return;
    final db = widget.app.db;
    final text = await exportBackup(db);
    final name = backupName('before-wipe');
    await keepInsideCopy(text, name);
    if (!mounted) return;
    final saved = await (widget.save ?? (t, nm) => saveBackupFile(context, t, nm))(text, name);
    if (!mounted) return;
    if (!saved) return toast(context, 'Nothing wiped: the backup wasn\'t saved', error: true);
    final r = await db.wipe(products: products, suppliers: suppliers, review: review, shops: shops);
    if (secrets) await Secrets(widget.app.store).clear();
    widget.app.changed();
    if (!mounted) return;
    Navigator.pop(context);
    toast(
      context,
      'Wiped: ${[if (products) '${r.products} products', if (suppliers) '${r.suppliers} suppliers', if (review) '${r.review} review items', if (shops) '${r.shops} shops', if (secrets) 'support secrets'].join(', ')}',
    );
  }

  /// This hour's code for the app's install ID, as at the lock screen.
  Future<bool> _code() async {
    final code = TextEditingController();
    String error = '';
    return await showDialog<bool>(
          context: context,
          builder: (d) => StatefulBuilder(
            builder: (d, set) => AlertDialog(
              title: const Text('Wipe: enter the code'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('This hour\'s code for install $appInstallId. A backup is saved first.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: code,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: 'Code', counterText: '', errorText: error.isEmpty ? null : error),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () {
                    if (validPin(hex.decode(appSeedHex), code.text, DateTime.now())) return Navigator.pop(d, true);
                    set(() => error = 'That isn\'t this hour\'s code');
                    code.clear();
                  },
                  child: const Text('Wipe'),
                ),
              ],
            ),
          ),
        ) ==
        true;
  }

  Widget _tick(String label, int count, bool value, ValueChanged<bool> on, [String? note]) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    value: value,
    onChanged: (v) => setState(() => on(v ?? false)),
    title: Text('$label ($count)'),
    subtitle: note == null ? null : Text(note),
  );

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final n = widget.n;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Wipe', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Only what you tick goes. It needs this hour\'s code, and a backup is saved first: if you don\'t save it, nothing is wiped.',
              style: TextStyle(color: c.mutedForeground),
            ),
            const SizedBox(height: 8),
            _tick('Catalogue products', n.products, products, (v) {
              products = v;
              if (v) review = true; // so the next pull lists the shop's products again
            }),
            _tick('Suppliers', n.suppliers, suppliers, (v) => suppliers = v),
            _tick('Review list', n.review, review, (v) => review = v, 'Clear it with the products, so the next pull lists the shop\'s products again'),
            _tick('Shops', n.shops, shops, (v) => shops = v, n.pending > 0 ? '${n.pending} changes waiting to push will be lost' : null),
            _tick('Support secrets', widget.secrets, secrets, (v) => secrets = v, 'Never in a backup: you add them again with the key icon'),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: c.danger),
                  onPressed: () {
                    setState(() => products = suppliers = review = shops = secrets = true);
                    _wipe();
                  },
                  child: const Text('Wipe all'),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: c.danger),
                  onPressed: any ? _wipe : null,
                  child: const Text('Back up and wipe'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
