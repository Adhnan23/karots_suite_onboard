import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Support secrets')),
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
