import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../settings/secret_transfer.dart';

import '../settings/secrets.dart';
import '../state.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// The support secrets, by name; each shop picks the one it was built with.
class SecretsScreen extends StatefulWidget {
  const SecretsScreen({super.key});
  @override
  State<SecretsScreen> createState() => _SecretsScreenState();
}

class _SecretsScreenState extends State<SecretsScreen> {
  List<Secret> list = [];
  Secrets get store => Secrets(AppScope.of(context).store);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    store.all().then((x) => mounted ? setState(() => list = x) : null);
  }

  Future<void> edit([int? i]) async {
    final name = TextEditingController(text: i == null ? '' : list[i].name);
    final secret = TextEditingController(text: i == null ? '' : list[i].secret);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(i == null ? 'Add a support secret' : 'Edit ${list[i].name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name (e.g. Main, Reseller A)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: secret,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Secret (POS_SUPPORT_SECRET)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || secret.text.trim().isEmpty) return;
    if (list.indexed.any((e) => e.$1 != i && e.$2.name == name.text.trim())) {
      if (mounted) toast(context, 'There is already a secret called ${name.text.trim()}', error: true);
      return;
    }
    final x = (name: name.text.trim(), secret: secret.text.trim());
    final next = [...list];
    i == null ? next.add(x) : next[i] = x;
    await store.save(next);
    setState(() => list = next);
  }

  /// Asks for the passphrase (and, when adding, the pasted copy). Null when cancelled.
  Future<({String pass, String text})?> _ask({required bool adding}) async {
    final text = TextEditingController();
    final pass = TextEditingController();
    String err = '';
    return showDialog<({String pass, String text})>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(adding ? 'Add from another device' : 'Send to another device'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                adding
                    ? 'Paste the copy made on the other device and type its passphrase.'
                    : 'Choose a passphrase (8 or more characters). The copy can only be opened with it: tell it to the other device by voice, not in the same message.',
              ),
              if (adding) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: text,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Copy (KSEC1:…)',
                    suffixIcon: IconButton(
                      tooltip: 'Paste',
                      icon: const Icon(Icons.content_paste_rounded),
                      onPressed: () async => text.text = (await Clipboard.getData('text/plain'))?.text ?? '',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: pass,
                obscureText: true,
                decoration: InputDecoration(labelText: 'Passphrase', errorText: err.isEmpty ? null : err),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (!adding && pass.text.length < 8) return set(() => err = '8 or more characters');
                if (adding && (text.text.trim().isEmpty || pass.text.isEmpty)) return set(() => err = 'Paste the copy and type its passphrase');
                Navigator.pop(d, (pass: pass.text, text: text.text));
              },
              child: Text(adding ? 'Add' : 'Make the copy'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> send() async {
    final a = await _ask(adding: false);
    if (a == null) return;
    final copy = await sealSecrets(list, a.pass);
    await Clipboard.setData(ClipboardData(text: copy));
    if (Platform.isAndroid) await SharePlus.instance.share(ShareParams(text: copy, subject: 'Karots Onboard secrets'));
    if (mounted) toast(context, 'Copied (sealed). Open Support secrets → Add from another device there.');
  }

  Future<void> receive() async {
    final a = await _ask(adding: true);
    if (a == null) return;
    try {
      final got = await openSecrets(a.text, a.pass);
      final next = mergeSecrets(list, got);
      await store.save(next);
      setState(() => list = next);
      if (mounted) toast(context, 'Added ${got.length} secret${got.length == 1 ? '' : 's'}');
    } on WrongPassphrase {
      if (mounted) toast(context, 'Wrong passphrase', error: true);
    } on FormatException {
      if (mounted) toast(context, 'That isn\'t a secrets copy from Karots Onboard', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support secrets'),
        actions: [
          if (list.isNotEmpty) IconButton(tooltip: 'Send to another device', icon: const Icon(Icons.ios_share_rounded), onPressed: send),
          IconButton(tooltip: 'Add from another device', icon: const Icon(Icons.download_rounded), onPressed: receive),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.brand,
        foregroundColor: c.brandForeground,
        onPressed: edit,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add secret'),
      ),
      body: Narrow(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            Text(
              'A shop opens with the secret it was built with. The first one is used when a shop picks none.',
              style: TextStyle(color: c.mutedForeground),
            ),
            const SizedBox(height: 12),
            for (final (i, x) in list.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(Icons.key_rounded, color: c.foreground),
                    title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('••••••••${x.secret.length > 4 ? x.secret.substring(x.secret.length - 4) : ''}${i == 0 ? ' · default' : ''}'),
                    onTap: () => edit(i),
                    trailing: list.length > 1
                        ? IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final next = [...list]..removeAt(i);
                              await store.save(next);
                              setState(() => list = next);
                            },
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
