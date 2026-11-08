import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state.dart';
import '../sync/match.dart';
import '../sync/push.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'shop_product_editor.dart';

/// The shop's own products (from its last pull): open one to change it there.
class ShopProductsScreen extends StatefulWidget {
  const ShopProductsScreen({super.key, required this.shop});
  final Shop shop;
  @override
  State<ShopProductsScreen> createState() => _ShopProductsScreenState();
}

class _ShopProductsScreenState extends State<ShopProductsScreen> {
  List<Map<String, Object?>> rows = [];
  String q = '';

  Future<void> load() async {
    final x = await AppScope.of(context).db.shopProducts(widget.shop.uid);
    if (mounted) setState(() => rows = x);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final n = normName(q);
    final list = [
      for (final r in rows)
        if (n.isEmpty || normName('${r['name']}').contains(n) || '${r['barcode']}'.contains(q.trim())) r,
    ];
    return Scaffold(
      appBar: AppBar(title: Text('${widget.shop.name} · products')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: 'Search ${rows.length} products'),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Empty(icon: Icons.download_rounded, title: 'Pull this shop first', sub: 'Its products show here after a pull.')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final r = list[i];
                      final p = CatalogProduct.fromJson(jsonDecode('${r['json']}') as Map);
                      return Card(
                        child: ListTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [
                              p.category,
                              if (p.barcode.isNotEmpty) p.barcode,
                              if (r['catalog_uid'] == null) 'not in the catalogue',
                            ].where((x) => x.isNotEmpty).join(' · '),
                          ),
                          trailing: Text(
                            'Rs ${p.selling}',
                            style: TextStyle(fontWeight: FontWeight.w700, color: c.foreground),
                          ),
                          onTap: () async {
                            final ok = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ShopProductEditor(
                                  shop: widget.shop,
                                  draft: Draft(product: p, remoteId: r['remote_id'] as int),
                                ),
                              ),
                            );
                            if (ok == true) load();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Work saved while the shop was out of reach; Push now sends it.
class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key, required this.shop});
  final Shop shop;
  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  List<PendingOp> rows = [];
  bool busy = false;

  Future<void> load() async {
    final x = await AppScope.of(context).db.pending(widget.shop.uid);
    if (mounted) setState(() => rows = x);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = KsTokens.of(context);
    final client = app.session(widget.shop);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.shop.name} · waiting to push')),
      floatingActionButton: rows.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: c.brand,
              foregroundColor: c.brandForeground,
              onPressed: client == null || busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final left = await guard(context, () => flushPending(app.db, client, widget.shop, who: app.who));
                      app.pushed(widget.shop);
                      setState(() => busy = false);
                      await load();
                      if (left != null && context.mounted) toast(context, left == 0 ? 'All pushed' : '$left still waiting: see why on each');
                    },
              icon: const Icon(Icons.cloud_upload_rounded),
              label: Text(client == null ? 'Connect to push' : 'Push ${rows.where((o) => o.who == app.who).length} now'),
            ),
      body: rows.isEmpty
          ? const Empty(icon: Icons.cloud_done_rounded, title: 'Nothing waiting')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final o in rows)
                  Card(
                    child: ListTile(
                      enabled: o.who == app.who, // another Shelf person's: theirs to send
                      title: Text('${((o.data['product'] as Map?) ?? {})['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [
                          switch (o.op) {
                            'create' => 'New product',
                            'update' => 'Change',
                            'batches' => 'Refused stock to retry',
                            _ => o.op,
                          },
                          if (o.who != app.who) 'waiting for ${o.who} to sign in',
                          if (o.error.isNotEmpty) o.error,
                        ].join(' · '),
                        style: TextStyle(color: o.error.isEmpty ? null : c.danger),
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await app.db.donePending(o.uid);
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
