import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../settings/secrets.dart';
import '../state.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'backup_sheet.dart';
import 'secrets_screen.dart';
import 'shop_screen.dart';

const shopKinds = ['pharmacy', 'grocery', 'hardware', 'motor spares', 'phone shop', 'stationery', 'textile', 'other'];

class ShopsScreen extends StatefulWidget {
  const ShopsScreen({super.key});
  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  List<Shop>? shops;

  Future<void> load() async {
    final s = await AppScope.of(context).db.shops();
    if (mounted) setState(() => shops = s);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  Future<void> edit([Shop? s]) async {
    final saved = await editShop(context, s);
    if (saved != null) load();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = KsTokens.of(context);
    final list = shops;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: edit,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Add shop'),
        backgroundColor: c.brand,
        foregroundColor: c.brandForeground,
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                PageHead(
                  title: 'Shops',
                  sub: '${list.length} shop${list.length == 1 ? '' : 's'} · set up, pull and push',
                  actions: [
                    IconButton(tooltip: 'Backup', icon: const Icon(Icons.cloud_sync_outlined), onPressed: () => showBackup(context)),
                    IconButton(
                      tooltip: 'Support secrets',
                      icon: const Icon(Icons.key_rounded),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecretsScreen())),
                    ),
                  ],
                ),
                if (list.isEmpty)
                  const Empty(
                    icon: Icons.storefront_rounded,
                    title: 'No shops yet',
                    sub: 'Add a shop running Karots Suite: its address on Tailscale or its Wi-Fi.',
                  ),
                for (final s in list)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: CircleAvatar(
                          backgroundColor: c.brandSoft,
                          child: Text(
                            s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                            style: TextStyle(color: c.foreground, fontWeight: FontWeight.w800),
                          ),
                        ),
                        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          [
                            if (s.kind.isNotEmpty) s.kind,
                            s.lastPull == null ? 'never pulled' : 'pulled ${DateFormat('d MMM, HH:mm').format(s.lastPull!)}',
                          ].join(' · '),
                        ),
                        trailing: app.connected(s) ? Tag('Connected', tone: c.success) : const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => ShopScreen(shop: app.live(s))));
                          load();
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Add or edit a shop's profile; returns the saved shop.
Future<Shop?> editShop(BuildContext context, Shop? s) async {
  final app = AppScope.of(context);
  final secrets = await Secrets(app.store).all();
  var secretName = s?.secretName ?? '';
  if (!context.mounted) return null;
  final name = TextEditingController(text: s?.name ?? '');
  final address = TextEditingController(text: s?.address ?? 'http://');
  var kind = s?.kind ?? shopKinds.first;
  return showModalBottomSheet<Shop>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s == null ? 'Add a shop' : 'Edit ${s.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Shop name'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: shopKinds.contains(kind) ? kind : 'other',
              decoration: const InputDecoration(labelText: 'Kind of shop'),
              items: [for (final k in shopKinds) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => set(() => kind = v ?? kind),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: address,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Address', helperText: 'e.g. http://100.101.5.2:3000 (Tailscale) or http://192.168.1.20:3000'),
            ),
            if (secrets.length > 1) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: secrets.any((x) => x.name == secretName) ? secretName : secrets.first.name,
                decoration: const InputDecoration(labelText: 'Support secret'),
                items: [for (final x in secrets) DropdownMenuItem(value: x.name, child: Text(x.name))],
                onChanged: (v) => set(() => secretName = v ?? ''),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty || !address.text.contains('://')) return;
                final shop = s ?? Shop(name: '');
                shop
                  ..name = name.text.trim()
                  ..kind = kind
                  ..address = address.text.trim()
                  ..secretName = secretName
                  ..secretName = secretName;
                await app.db.saveShop(shop);
                if (ctx.mounted) Navigator.pop(ctx, shop);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ),
  );
}
