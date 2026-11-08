import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../input/field_kind.dart';
import '../input/ks_field.dart';
import '../state.dart';
import '../sync/push.dart';
import '../sync/quick.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'shop_product_editor.dart';

/// Setting up a shop fast: scan or search, the catalogue fills the rest, type
/// cost, price and quantity, next.
class QuickAddScreen extends StatefulWidget {
  const QuickAddScreen({super.key, required this.shop});
  final Shop shop;
  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  final q = TextEditingController();
  final focus = FocusNode();
  List<CatalogProduct> all = [];
  List<Map<String, Object?>> mine = [];
  ({List<CatalogProduct> catalogue, Map<String, Object?>? inShop})? found;
  int added = 0;
  Shop get s => widget.shop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final db = AppScope.of(context).db;
    () async {
      final a = await db.products(), m = await db.shopProducts(s.uid);
      if (!mounted) return;
      setState(() {
        all = a;
        mine = m;
      });
    }();
  }

  void search() => setState(() => found = quickFind(all, mine, q.text));

  void next() {
    q.clear();
    setState(() => found = null);
    focus.requestFocus();
  }

  Future<void> openExisting(Map<String, Object?> r) async {
    final p = CatalogProduct.fromJson(jsonDecode('${r['json']}') as Map);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopProductEditor(
          shop: s,
          draft: Draft(product: p, remoteId: r['remote_id'] as int),
        ),
      ),
    );
    next();
  }

  Future<void> add(CatalogProduct p) async {
    final cost = TextEditingController(), price = TextEditingController(text: p.selling); // cost differs by supplier: typed here
    final qty = TextEditingController(), expiry = TextEditingController();
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (p.supplier.isNotEmpty) Text('from ${p.supplier}', style: TextStyle(color: KsTokens.of(ctx).mutedForeground, fontSize: 13)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: KsField(label: 'Cost', controller: cost, kind: FieldKind.number),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: KsField(label: 'Price', controller: price, kind: FieldKind.number),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: KsField(label: 'Quantity', controller: qty, kind: FieldKind.number),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: KsField(label: 'Expiry', controller: expiry, kind: FieldKind.date),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Add to ${s.name}')),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    final app = AppScope.of(context);
    final d = quickDraft(p, cost: cost.text, price: price.text, qty: qty.text, expiry: expiry.text);
    final c = app.session(s);
    if (c == null) {
      await queue(app.db, s, 'create', d);
      if (mounted) toast(context, '${p.name}: saved to push later');
    } else {
      if (d.stock.isNotEmpty && s.snapshot['stockTake'] == false) {
        final on = await showDialog<bool>(
          context: context,
          builder: (x) => AlertDialog(
            title: Text('Turn on Stock-take in ${s.name}?'),
            content: const Text('Old stock goes in through stock intake, which works only with Stock-take on.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Turn on')),
            ],
          ),
        );
        if (on != true) return;
        await c.enableStockTake();
        s.snapshot['stockTake'] = true;
        await app.db.saveShop(s);
      }
      if (!mounted) return;
      final r = await guard(context, () => pushCreate(app.db, c, s, d));
      if (r == null) return;
      app.pushed(s);
      mine = await app.db.shopProducts(s.uid);
      if (mounted) {
        toast(context, r.notes.isEmpty ? '${p.name} is in ${s.name}' : '${p.name} is in, but: ${r.notes.join('; ')}', error: r.notes.isNotEmpty);
      }
    }
    if (!mounted) return;
    setState(() => added++);
    next();
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final f = found;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quick add'),
            Text('${s.name} · $added added', style: TextStyle(fontSize: 13, color: c.mutedForeground)),
          ],
        ),
      ),
      body: Narrow(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            KsField(
              label: 'Scan or type a barcode or name',
              controller: q,
              kind: FieldKind.barcode,
              focusNode: focus,
              autofocus: true,
              onChanged: (_) => search(),
              onSubmitted: (_) {
                search();
                final x = found;
                if (x != null && x.inShop == null && x.catalogue.length == 1) add(x.catalogue.single);
              },
            ),
            const SizedBox(height: 12),
            if (f != null && f.inShop != null)
              Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline_rounded, color: c.warning),
                  title: Text('Already in ${s.name}: ${f.inShop!['name']}'),
                  subtitle: const Text('Open it to add stock'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openExisting(f.inShop!),
                ),
              ),
            if (f != null)
              for (final p in f.catalogue.take(30))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Card(
                    child: ListTile(
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([if (p.barcode.isNotEmpty) p.barcode, if (p.supplier.isNotEmpty) 'from ${p.supplier}'].join(' · ')),
                      trailing: const Icon(Icons.add_circle_outline_rounded),
                      onTap: () => add(p),
                    ),
                  ),
                ),
            if (f != null && f.catalogue.isEmpty && q.text.trim().isNotEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('Not in the catalogue'),
                  subtitle: const Text('Open the full editor with this filled in'),
                  onTap: () async {
                    final t = q.text.trim();
                    final isCode = RegExp(r'^\d{6,}$').hasMatch(t);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ShopProductEditor(
                          shop: s,
                          draft: Draft(
                            product: newShopProduct(s, name: isCode ? '' : t, barcode: isCode ? t : ''),
                          ),
                        ),
                      ),
                    );
                    next();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
