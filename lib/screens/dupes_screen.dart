import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../dupes/find.dart';
import '../state.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// Products listed twice: in the catalogue, or inside a connected shop (merged
/// there by the Suite's own merge, so every plugin fixes its own rows).
class DupesScreen extends StatefulWidget {
  const DupesScreen({super.key});
  @override
  State<DupesScreen> createState() => _DupesScreenState();
}

class _DupesScreenState extends State<DupesScreen> {
  List<Shop> shops = [];
  String where = 'catalog'; // or a shop uid
  List<DupPair> pairs = [];
  final notSame = <String>{};
  bool busy = false;

  Future<void> load() async {
    final db = AppScope.of(context).db;
    shops = await db.shops();
    List<CatalogProduct> list;
    if (where == 'catalog') {
      list = await db.products();
    } else {
      list = [
        for (final r in await db.shopProducts(where)) CatalogProduct.fromJson({...jsonDecode('${r['json']}') as Map, 'uid': 'r${r['remote_id']}'}),
      ];
    }
    final found = [
      for (final p in findDupes(list))
        if (!notSame.contains(_key(p))) p,
    ];
    if (mounted) setState(() => pairs = found);
  }

  String _key(DupPair p) => '$where|${([p.a.uid, p.b.uid]..sort()).join('|')}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  Future<void> merge(DupPair p, CatalogProduct keep, CatalogProduct drop) async {
    final app = AppScope.of(context);
    if (where == 'catalog') {
      await mergeCatalog(app.db, keep.uid, drop.uid);
      return load();
    }
    final shop = shops.firstWhere((s) => s.uid == where);
    final c = app.session(shop);
    if (c == null) return toast(context, 'Connect to ${shop.name} first', error: true);
    final from = int.parse(drop.uid.substring(1)), into = int.parse(keep.uid.substring(1));
    final pv = await guard(context, () => c.mergePreview(from, into));
    if (pv == null || !mounted) return;
    if ('${pv['refusal'] ?? ''}'.isNotEmpty) return toast(context, '${pv['refusal']}', error: true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Merge in ${shop.name}?'),
        content: Text(
          '“${pv['fromName']}” goes into “${pv['intoName']}”: ${pv['stock']} in stock, ${pv['sales']} sales, '
          '${pv['purchases']} purchases and ${pv['barcodes']} barcodes move over.${pv['priceClash'] == true ? '\nPrices differ: ${pv['fromPrice']} vs ${pv['intoPrice']}; the kept product\'s price stays.' : ''}\n\nThis can\'t be undone in the shop.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Merge')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await guard(context, () async {
      await c.merge(from, into);
      return true;
    });
    if (done == true) {
      await app.db.raw.delete('shop_products', where: 'shop_uid = ? AND remote_id = ?', whereArgs: [where, from]);
      app.pushed(shop);
      if (mounted) toast(context, 'Merged in ${shop.name}');
      load();
    }
  }

  Widget side(DupPair p, CatalogProduct x, CatalogProduct other) {
    final c = KsTokens.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(x.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
            [x.category, if (x.allCodes.isNotEmpty) x.allCodes.join(', '), if (x.selling.isNotEmpty) 'Rs ${x.selling}'].where((s) => s.isNotEmpty).join(' · '),
            style: TextStyle(color: c.mutedForeground, fontSize: 13),
          ),
          const SizedBox(height: 6),
          OutlinedButton(onPressed: () => merge(p, x, other), child: const Text('Keep this')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return Scaffold(
      body: Column(
        children: [
          PageHead(title: 'Duplicates', sub: 'The same product listed twice: keep one, the other folds into it'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: where,
              decoration: const InputDecoration(labelText: 'Look in'),
              items: [
                const DropdownMenuItem(value: 'catalog', child: Text('The catalogue')),
                for (final s in shops) DropdownMenuItem(value: s.uid, child: Text('${s.name} (its last pull)')),
              ],
              onChanged: (v) {
                where = v ?? 'catalog';
                load();
              },
            ),
          ),
          Expanded(
            child: pairs.isEmpty
                ? const Empty(icon: Icons.merge_type_rounded, title: 'No duplicates found')
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final p in pairs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Section(
                            title: p.why,
                            children: [
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [side(p, p.a, p.b), const SizedBox(width: 12), side(p, p.b, p.a)]),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    notSame.add(_key(p));
                                    load();
                                  },
                                  child: Text('Not the same', style: TextStyle(color: c.mutedForeground)),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
