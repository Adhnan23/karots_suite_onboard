import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state.dart';
import '../sync/match.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'product_form.dart';

/// Search by name or any barcode; kind: only products seen in that kind of shop.
List<CatalogProduct> filterCatalog(List<CatalogProduct> all, String q, String? kind) {
  final n = normName(q);
  return [
    for (final p in all)
      if ((kind == null || p.kinds.contains(kind)) && (n.isEmpty || normName(p.name).contains(n) || p.allCodes.any((c) => c.contains(q.trim())))) p,
  ];
}

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  List<CatalogProduct> all = [];
  String q = '';
  String? kind;

  Future<void> load() async {
    final x = await AppScope.of(context).db.products();
    if (mounted) setState(() => all = x);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  Future<void> open(CatalogProduct p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CatalogProductPage(product: p)));
    load();
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final kinds = {for (final p in all) ...p.kinds}.toList()..sort();
    final list = filterCatalog(all, q, kind);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => open(CatalogProduct(name: '')),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New product'),
        backgroundColor: c.brand,
        foregroundColor: c.brandForeground,
      ),
      body: Column(
        children: [
          PageHead(title: 'Catalogue', sub: '${all.length} products for every kind of shop'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by name or barcode'),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          if (kinds.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                children: [
                  for (final k in [null, ...kinds])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(label: Text(k ?? 'All'), selected: kind == k, onSelected: (_) => setState(() => kind = k)),
                    ),
                ],
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Empty(
                    icon: Icons.inventory_2_rounded,
                    title: all.isEmpty ? 'The catalogue is empty' : 'Nothing matches',
                    sub: all.isEmpty ? 'Pull a shop and accept its products in Review.' : null,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final p = list[i];
                      return Card(
                        child: ListTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [
                              if (p.barcode.isNotEmpty) p.barcode,
                              if (p.packs.isNotEmpty) p.packs.map((k) => '${k.name} ×${k.size}').join(', '),
                              ...p.fields.entries.map((e) => '${e.key}: ${e.value}'),
                              if (p.offers.isNotEmpty) '${p.offers.length} supplier${p.offers.length == 1 ? '' : 's'}',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: p.selling.isEmpty ? null : Text('Rs ${p.selling}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          onTap: () => open(p),
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

/// Edit a catalogue product (or a new one), save or delete it.
class CatalogProductPage extends StatelessWidget {
  CatalogProductPage({super.key, required this.product});
  final CatalogProduct product;
  final form = GlobalKey<ProductFormState>();

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    return Scaffold(
      appBar: AppBar(
        title: Text(product.name.isEmpty ? 'New product' : product.name),
        actions: [
          if (product.name.isNotEmpty)
            IconButton(
              tooltip: 'Delete from the catalogue',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await db.deleteProduct(product.uid);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: Narrow(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            ProductForm(key: form, product: product),
            if (product.offers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Section(
                title: 'Suppliers',
                children: [
                  for (final o in product.offers)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(o.supplierName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: o.code.isEmpty ? null : Text('Their code ${o.code}'),
                      trailing: Text(
                        [if (o.cost.isNotEmpty) 'cost ${o.cost}', if (o.price.isNotEmpty) 'price ${o.price}'].join('\n'),
                        textAlign: TextAlign.right,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final p = form.currentState!.read();
          if (p.name.isEmpty) return toast(context, 'Give it a name', error: true);
          await db.saveProduct(p);
          if (context.mounted) Navigator.pop(context);
        },
        icon: const Icon(Icons.save_rounded),
        label: const Text('Save'),
      ),
    );
  }
}
