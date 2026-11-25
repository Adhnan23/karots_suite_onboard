import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state.dart';
import '../sync/catalogue_app.dart';
import '../ui/kit.dart';

/// Sync with the Catalogue app (catalogue repo docs/plans/onboard-sync.md; decisions README "Piece 4"): connect by
/// address + the app's PIN, see the lists, tick, Apply. Nothing moves without a tick. Fixes and moving your own
/// products start unticked (your choice); prices and barcodes start ticked.
class CatalogueSyncPage extends StatefulWidget {
  const CatalogueSyncPage({super.key});
  @override
  State<CatalogueSyncPage> createState() => _CatalogueSyncPageState();
}

const _addressKey = 'catalogue_app_address';

class _CatalogueSyncPageState extends State<CatalogueSyncPage> {
  final address = TextEditingController(), pin = TextEditingController();
  SyncPlan? plan;
  CatalogueApp? app;
  Map<String, String> shopNames = {};
  final fixes = <String>{}, move = <String>{}, up = <String>{}, down = <String>{}; // ticked, by product uid
  bool busy = false;
  String error = '', done = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final a = await AppScope.of(context).store.read(_addressKey);
      if (a != null && mounted) address.text = a;
    });
  }

  @override
  void dispose() {
    address.dispose();
    pin.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    final s = AppScope.of(context);
    setState(() {
      busy = true;
      error = '';
      done = '';
    });
    try {
      final c = CatalogueApp(address.text);
      await c.signIn(pin.text);
      await s.store.write(_addressKey, address.text.trim());
      final mine = await s.db.products();
      final p = planSync(mine, await c.match([for (final x in mine) x.name]));
      shopNames = {for (final x in await s.db.shops()) x.uid: x.name};
      if (!mounted) return;
      setState(() {
        app = c;
        plan = p;
        fixes.clear();
        move.clear();
        up
          ..clear()
          ..addAll([for (final x in p.pricesUp) x.product.uid, for (final x in p.codesUp) x.product.uid]);
        down
          ..clear()
          ..addAll([for (final x in p.pricesDown) x.product.uid, for (final x in p.codesDown) x.product.uid]);
      });
    } catch (e) {
      if (mounted) setState(() => error = e is CatalogueAppError ? e.message : 'The Catalogue app can\'t be reached at that address');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> apply() async {
    final p = plan!, db = AppScope.of(context).db;
    setState(() => busy = true);
    try {
      // Onboard's side first: fixes taken, the catalogue's prices and barcodes for products that had none.
      final changed = <String, CatalogProduct>{};
      for (final f in p.fixes.where((f) => fixes.contains(f.product.uid))) {
        takeFix(f);
        changed[f.product.uid] = f.product;
      }
      for (final x in p.pricesDown.where((x) => down.contains(x.product.uid))) {
        x.product
          ..selling = x.selling
          ..updatedAt = catalogueNow();
        changed[x.product.uid] = x.product;
      }
      for (final x in p.codesDown.where((x) => down.contains(x.product.uid))) {
        x.product
          ..barcodes.addAll(x.codes)
          ..updatedAt = catalogueNow();
        if (x.product.barcode.isEmpty) x.product.barcode = x.product.barcodes.removeAt(0);
        changed[x.product.uid] = x.product;
      }
      await db.saveProducts(changed.values.toList(), touch: false);
      // Then what goes up.
      String shopOf(CatalogProduct x) => [for (final u in x.sources) ?shopNames[u]].join(', ');
      final r = await app!.up(
        upBody(
          move: [
            for (final x in p.handMade)
              if (move.contains(x.uid)) x,
          ],
          prices: [
            for (final x in p.pricesUp)
              if (up.contains(x.product.uid)) x.product,
          ],
          codes: [
            for (final x in p.codesUp)
              if (up.contains(x.product.uid)) x,
          ],
          shopOf: shopOf,
        ),
      );
      final refused = [for (final x in (r['refused'] as List? ?? [])) '${(x as Map)['name']}: ${x['why']}'];
      setState(() {
        done = [
          '${changed.length} of your products updated from the catalogue',
          '${(r['added'] as List? ?? []).length} moved to the catalogue',
          '${r['prices'] ?? 0} prices and ${r['barcodes'] ?? 0} barcodes sent',
          if (refused.isNotEmpty) 'Not moved:\n${refused.join('\n')}',
        ].join('\n');
        plan = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e is CatalogueAppError ? e.message : 'Stopped: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget section(String title, String sub, List<String> uids, Set<String> ticked, List<Widget> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final all = uids.every(ticked.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Text('$title (${rows.length})', style: Theme.of(context).textTheme.titleMedium)),
            TextButton(onPressed: () => setState(() => all ? ticked.removeAll(uids) : ticked.addAll(uids)), child: Text(all ? 'Untick all' : 'Tick all')),
          ],
        ),
        Text(sub, style: Theme.of(context).textTheme.bodySmall),
        ...rows,
      ],
    );
  }

  Widget tick(Set<String> set, CatalogProduct p, String title, String sub) => CheckboxListTile(
    value: set.contains(p.uid),
    onChanged: (v) => setState(() => v == true ? set.add(p.uid) : set.remove(p.uid)),
    title: Text(title),
    subtitle: Text(sub),
    dense: true,
  );

  @override
  Widget build(BuildContext context) {
    final p = plan;
    final n = p == null ? 0 : fixes.length + move.length + up.length + down.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync with the Catalogue app')),
      bottomNavigationBar: p == null || p.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(onPressed: busy || n == 0 ? null : apply, child: Text(busy ? 'Working…' : 'Apply what\'s ticked')),
              ),
            ),
      body: Narrow(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (p == null) ...[
              TextField(
                controller: address,
                decoration: const InputDecoration(labelText: 'The Catalogue app\'s address', hintText: '192.168.1.5 or the PC\'s Tailscale name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pin,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Its PIN (PIN Vault, install id 7586DBF6)'),
                onSubmitted: (_) => connect(),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: busy ? null : connect, child: Text(busy ? 'Connecting…' : 'Connect')),
            ],
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (done.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(done)),
            if (p != null && p.isEmpty) const Padding(padding: EdgeInsets.only(top: 24), child: Text('Onboard and the catalogue agree: nothing to do.')),
            if (p != null) ...[
              section(
                'Catalogue fixes',
                'The catalogue says these differently. Tick the ones to take; only those values change.',
                [for (final f in p.fixes) f.product.uid],
                fixes,
                [
                  for (final f in p.fixes)
                    tick(fixes, f.product, f.product.name, [for (final c in f.changes) '${c.what}: ${c.mine.isEmpty ? '—' : c.mine} → ${c.theirs}'].join('\n')),
                ],
              ),
              section(
                'Your products, not in the catalogue',
                'Made by you in Onboard. Tick the ones to move to the catalogue (with their selling price and barcodes).',
                [for (final x in p.handMade) x.uid],
                move,
                [
                  for (final x in p.handMade) tick(move, x, x.name, [x.unit, ...x.kinds, if (x.selling.isNotEmpty) 'Rs ${x.selling}'].join(' · ')),
                ],
              ),
              section(
                'Send to the catalogue',
                'Your selling prices and barcodes the catalogue hasn\'t got. Never a cost.',
                [for (final x in p.pricesUp) x.product.uid, for (final x in p.codesUp) x.product.uid],
                up,
                [
                  for (final x in p.pricesUp)
                    tick(up, x.product, x.product.name, 'Rs ${x.product.selling}${x.catalogue.isEmpty ? '' : ' (catalogue: Rs ${x.catalogue})'}'),
                  for (final x in p.codesUp) tick(up, x.product, x.product.name, 'Barcodes ${x.codes.join(', ')}'),
                ],
              ),
              section(
                'From the catalogue',
                'Selling prices and barcodes for your products that have none.',
                [for (final x in p.pricesDown) x.product.uid, for (final x in p.codesDown) x.product.uid],
                down,
                [
                  for (final x in p.pricesDown) tick(down, x.product, x.product.name, 'Rs ${x.selling}'),
                  for (final x in p.codesDown) tick(down, x.product, x.product.name, 'Barcodes ${x.codes.join(', ')}'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
