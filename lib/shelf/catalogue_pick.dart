import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../suite/client.dart';
import '../sync/push.dart';

/// Karots Shelf's From catalogue: the shop PC's copy of the Karots catalogue (the suite's Catalogue plugin,
/// rule CTL-13). Shelf keeps no catalogue of its own.

const needsCataloguePlugin = 'From catalogue needs the Catalogue in this shop. It comes with the Karots service plan: ask Karots to add it.';
const catalogueOutOfReach = "The catalogue is on the shop's PC: connect to the shop's Wi-Fi, or type the product in.";

/// The product a pick fills: its name, the shop's unit for it and the shop's own fields (by label), keeping the
/// category already chosen. The pick's id goes with the draft, so the product is linked when it's made.
Draft draftFromShopPick(Shop s, Map pick, {String category = ''}) {
  final units = [for (final u in (s.snapshot['units'] as List? ?? [])) u as Map];
  final unitId = (pick['unitId'] as num? ?? 0).toInt();
  final unit = units.where((u) => (u['id'] as num?)?.toInt() == unitId).firstOrNull?['abbreviation'] as String?;
  final labels = {for (final f in (s.snapshot['fields'] as List? ?? [])) '${(f as Map)['key']}': '${f['label']}'};
  final values = ((pick['sections'] as Map?)?['productplus'] as Map?)?['values'] as Map? ?? {};
  return Draft(
    product: CatalogProduct(
      name: '${pick['name'] ?? ''}',
      category: category,
      unit: (unit != null && unit.isNotEmpty) ? unit : shopDefaultUnit(s),
      fields: {
        for (final e in values.entries)
          if (labels[e.key] != null && '${e.value}'.trim().isNotEmpty) labels[e.key]!: '${e.value}'.trim(),
      },
    ),
    catalogueItem: (pick['id'] as num? ?? 0).toInt(),
  );
}

/// Searches the shop PC's catalogue as the person types; a tap hands the pick back.
class ShopCataloguePick extends StatefulWidget {
  const ShopCataloguePick({super.key, required this.client, this.first = ''});
  final SuiteClient client;
  final String first;
  @override
  State<ShopCataloguePick> createState() => _ShopCataloguePickState();
}

class _ShopCataloguePickState extends State<ShopCataloguePick> {
  late final q = TextEditingController(text: widget.first);
  Timer? wait;
  List<Map> found = [];
  String note = 'Type a name, a generic or a company.';
  int asked = 0;

  @override
  void initState() {
    super.initState();
    if (widget.first.trim().isNotEmpty) search(widget.first);
  }

  @override
  void dispose() {
    wait?.cancel();
    q.dispose();
    super.dispose();
  }

  void typed(String v) {
    wait?.cancel();
    wait = Timer(const Duration(milliseconds: 250), () => search(v));
  }

  void show(List<Map> r, String n) => setState(() {
    found = r;
    note = n;
  });

  Future<void> search(String v) async {
    final term = v.trim();
    final mine = ++asked; // only the newest answer shows
    if (term.isEmpty) return show([], 'Type a name, a generic or a company.');
    try {
      final r = [
        for (final x in (await widget.client.get('/x/catalogue/search', {'q': term}) as List? ?? [])) x as Map,
      ];
      if (!mounted || mine != asked) return;
      show(r, r.isEmpty ? 'Nothing in the catalogue for “$term”: type it in.' : '');
    } catch (e) {
      if (!mounted || mine != asked) return;
      show([], e is SuiteError ? e.message : catalogueOutOfReach);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: q,
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.menu_book_outlined), hintText: 'Search the catalogue: name, generic, company'),
              onChanged: typed,
            ),
          ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(note, style: t.textTheme.bodyMedium),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final p in found)
                  ListTile(
                    title: Text('${p['name']}'),
                    subtitle: Text(
                      [
                        '${p['unit'] ?? ''}',
                        ...((p['fields'] as Map?)?.values.map((v) => '$v') ?? const <String>[]),
                        if (p['have'] != null) 'You have it: ${(p['have'] as Map)['name']}',
                      ].where((x) => x.trim().isNotEmpty).join(' · '),
                    ),
                    onTap: () => Navigator.pop(context, p),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
