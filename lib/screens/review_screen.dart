import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state.dart';
import '../sync/review.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// What pulls found that the catalogue hasn't got: accept, fix or drop.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  List<ReviewItem> rows = [];
  Map<String, String> shopNames = {};
  final picked = <String>{};
  String kind = 'product';
  bool busy = false;

  Future<void> load() async {
    final db = AppScope.of(context).db;
    final r = await db.reviews();
    final s = {for (final x in await db.shops()) x.uid: x.name};
    if (!mounted) return;
    setState(() {
      rows = r;
      shopNames = s;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  List<ReviewItem> get shown => rows.where((r) => r.kind == kind).toList();

  Future<void> act(bool accept, Iterable<String> uids) async {
    final db = AppScope.of(context).db;
    setState(() => busy = true);
    if (accept) {
      await acceptReviews(db, uids.toList());
    } else {
      for (final u in uids.toList()) {
        await dropReview(db, u);
      }
    }
    picked.clear();
    busy = false;
    await load();
    if (mounted) AppScope.of(context).changed();
  }

  Future<void> editOne(ReviewItem r) async {
    final db = AppScope.of(context).db;
    final name = TextEditingController(text: '${r.data['name'] ?? ''}');
    final sell = TextEditingController(text: '${r.data['selling'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Fix before accepting'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            if (r.kind == 'product') ...[
              const SizedBox(height: 10),
              TextField(
                controller: sell,
                decoration: const InputDecoration(labelText: 'Selling price'),
                keyboardType: TextInputType.number,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Accept')),
        ],
      ),
    );
    if (ok != true) return;
    await acceptReview(
      db,
      r.uid,
      edited: {
        ...r.data,
        'name': name.text.trim(),
        if (r.kind == 'product') ...{'selling': sell.text.trim()},
      },
    );
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final list = shown;
    final byShop = <String, List<ReviewItem>>{};
    for (final r in list) {
      byShop.putIfAbsent(r.shopUid, () => []).add(r);
    }
    final products = rows.where((r) => r.kind == 'product').length;
    return Scaffold(
      body: Column(
        children: [
          PageHead(
            title: 'Review',
            sub: 'New from your shops: accept into the catalogue, fix, or drop',
            actions: [
              if (picked.isNotEmpty) ...[
                OutlinedButton(onPressed: busy ? null : () => act(false, picked), child: Text('Drop ${picked.length}')),
                const SizedBox(width: 8),
                FilledButton(onPressed: busy ? null : () => act(true, picked), child: Text('Accept ${picked.length}')),
              ] else if (list.isNotEmpty)
                FilledButton(onPressed: busy ? null : () => act(true, list.map((r) => r.uid)), child: Text('Accept all ${list.length}')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'product', label: Text('Products · $products')),
                ButtonSegment(value: 'supplier', label: Text('Suppliers · ${rows.length - products}')),
              ],
              selected: {kind},
              onSelectionChanged: (v) => setState(() {
                kind = v.first;
                picked.clear();
              }),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? const Empty(
                    icon: Icons.fact_check_rounded,
                    title: 'Nothing to review',
                    sub: 'Pull a shop: what the catalogue hasn\'t got lands here.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      for (final e in byShop.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                          child: Text(
                            '${shopNames[e.key] ?? 'Shop'} · ${e.value.length}',
                            style: TextStyle(fontWeight: FontWeight.w700, color: c.mutedForeground),
                          ),
                        ),
                        Card(
                          child: Column(
                            children: [
                              for (final (i, r) in e.value.indexed) ...[
                                if (i > 0) const Divider(height: 1),
                                CheckboxListTile(
                                  value: picked.contains(r.uid),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  onChanged: (v) => setState(() => v == true ? picked.add(r.uid) : picked.remove(r.uid)),
                                  title: Text('${r.data['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(_line(r), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  secondary: IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Fix and accept',
                                    onPressed: () => editOne(r),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _line(ReviewItem r) {
    final d = r.data;
    if (r.kind == 'supplier') return [d['phone'], d['contact']].where((x) => '${x ?? ''}'.isNotEmpty).join(' · ');
    final packs = (d['packs'] as List? ?? []).map((k) => '${k['name']} ×${k['size']}');
    final fields = (d['fields'] as Map? ?? {}).entries.map((e) => '${e.key}: ${e.value}');
    return [
      if ('${d['barcode'] ?? ''}'.isNotEmpty) d['barcode'],
      if ('${d['selling'] ?? ''}'.isNotEmpty) 'Rs ${d['selling']}',
      ...packs,
      ...fields,
    ].join(' · ');
  }
}
