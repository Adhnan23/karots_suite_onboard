import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state.dart';
import '../sync/alternatives.dart';
import '../sync/match.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// A shop's Alternatives groups (from its pull); make a new one, or copy one from
/// another shop with the members matched by name.
class AlternativesScreen extends StatefulWidget {
  const AlternativesScreen({super.key, required this.shop});
  final Shop shop;
  @override
  State<AlternativesScreen> createState() => _AlternativesScreenState();
}

class _AlternativesScreenState extends State<AlternativesScreen> {
  Shop get s => widget.shop;
  List<AltGroup> get groups => [for (final g in (s.snapshot['alternatives'] as List? ?? [])) AltGroup.fromJson(g as Map)];

  Future<void> refresh() async {
    final app = AppScope.of(context);
    final c = app.session(s);
    if (c == null) return;
    s.snapshot['alternatives'] = await c.alternatives();
    await app.db.saveShop(s);
    if (mounted) setState(() {});
  }

  Future<void> create(String name, String tier, List<int> ids) async {
    final c = AppScope.of(context).session(s);
    if (c == null) return toast(context, 'Connect to ${s.name} first', error: true);
    if (!s.has('alternatives')) return toast(context, '${s.name} doesn\'t have the Alternatives plugin', error: true);
    final ok = await guard(context, () => c.createAlternative(name, tier, ids));
    if (ok != null) {
      await refresh();
      if (mounted) toast(context, '“$name” made in ${s.name}');
    }
  }

  Future<void> newGroup() async {
    final rows = await AppScope.of(context).db.shopProducts(s.uid);
    if (!mounted) return;
    final r = await showModalBottomSheet<(String, String, List<int>)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewGroup(rows: rows),
    );
    if (r != null) await create(r.$1, r.$2, r.$3);
  }

  Future<void> copyFrom() async {
    final app = AppScope.of(context);
    final others = [
      for (final x in await app.db.shops())
        if (x.uid != s.uid) x,
    ];
    final mine = await app.db.shopProducts(s.uid);
    if (!mounted) return;
    final pick = await showModalBottomSheet<(AltGroup, AltTier)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .7,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Copy a group from another shop', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            for (final o in others)
              for (final g in [for (final x in (o.snapshot['alternatives'] as List? ?? [])) AltGroup.fromJson(x as Map)])
                for (final t in g.tiers)
                  ListTile(
                    title: Text('${g.name} · ${t.name}'),
                    subtitle: Text('${o.name} · ${matchMembers(t, mine).found.length} of ${t.members.length} found in ${s.name}'),
                    onTap: () => Navigator.pop(ctx, (g, t)),
                  ),
          ],
        ),
      ),
    );
    if (pick == null || !mounted) return;
    final m = matchMembers(pick.$2, mine);
    if (m.found.length < 2) return toast(context, 'Fewer than two of its products are in ${s.name}', error: true);
    if (m.missing.isNotEmpty) toast(context, 'Not in ${s.name}: ${m.missing.join(', ')}');
    await create(pick.$1.name, pick.$2.name, m.found);
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final on = AppScope.of(context).connected(s);
    final list = groups;
    return Scaffold(
      appBar: AppBar(title: Text('${s.name} · Alternatives')),
      floatingActionButton: on
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'copy',
                  onPressed: copyFrom,
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('Copy from a shop'),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'new',
                  backgroundColor: c.brand,
                  foregroundColor: c.brandForeground,
                  onPressed: newGroup,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New group'),
                ),
              ],
            )
          : null,
      body: list.isEmpty
          ? Empty(
              icon: Icons.swap_horiz_rounded,
              title: 'No groups yet',
              sub: on ? 'Make one, or copy one from another shop.' : 'Connect to make groups here.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 160),
              children: [
                for (final g in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Section(
                      title: g.name,
                      children: [
                        for (final t in g.tiers) ...[
                          Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 6, children: [for (final m in t.members) Tag(m.name)]),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _NewGroup extends StatefulWidget {
  const _NewGroup({required this.rows});
  final List<Map<String, Object?>> rows;
  @override
  State<_NewGroup> createState() => _NewGroupState();
}

class _NewGroupState extends State<_NewGroup> {
  final name = TextEditingController();
  final tier = TextEditingController(text: 'All');
  final picked = <int>{};
  String q = '';

  @override
  Widget build(BuildContext context) {
    final n = normName(q);
    final list = [
      for (final r in widget.rows)
        if (n.isEmpty || normName('${r['name']}').contains(n)) r,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New Alternatives group', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Group (e.g. Paracetamol 500)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: tier,
                    decoration: const InputDecoration(labelText: 'Tier'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: 'Find products · ${picked.length} picked'),
              onChanged: (v) => setState(() => q = v),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final r in list.take(200))
                    CheckboxListTile(
                      value: picked.contains(r['remote_id']),
                      title: Text('${r['name']}'),
                      onChanged: (v) => setState(() => v == true ? picked.add(r['remote_id'] as int) : picked.remove(r['remote_id'])),
                    ),
                ],
              ),
            ),
            FilledButton(
              onPressed: name.text.trim().isEmpty || picked.length < 2
                  ? null
                  : () => Navigator.pop(context, (name.text.trim(), tier.text.trim().isEmpty ? 'All' : tier.text.trim(), picked.toList())),
              child: const Text('Make it'),
            ),
          ],
        ),
      ),
    );
  }
}
