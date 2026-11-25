import 'package:flutter/material.dart';

import '../data/drafts.dart';
import '../data/models.dart';
import '../state.dart';
import '../sync/catalogue_online.dart';
import '../sync/search.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../sync/variant.dart';
import 'catalogue_new_page.dart';
import 'identify_sheet.dart';
import 'product_form.dart';

/// Search every field, typos allowed (searchProducts); kind: only products seen in that kind of shop.
List<CatalogProduct> filterCatalog(List<CatalogProduct> all, String q, String? kind) => searchProducts([
  for (final p in all)
    if (kind == null || p.kinds.contains(kind)) p,
], q);

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

  Future<void> open(CatalogProduct p, {bool keepDraft = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CatalogProductPage(product: p, keepDraft: keepDraft),
      ),
    );
    load();
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final kinds = {for (final p in all) ...p.kinds}.toList()..sort();
    final list = filterCatalog(all, q, kind);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => open(catalogNewDraft ?? CatalogProduct(name: ''), keepDraft: true),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New product'),
        backgroundColor: c.brand,
        foregroundColor: c.brandForeground,
      ),
      body: Column(
        children: [
          PageHead(
            title: 'Catalogue',
            sub: '${all.length} products for every kind of shop',
            actions: [
              if (catalogueAddress.isNotEmpty)
                IconButton(
                  tooltip: 'New from the Karots catalogue',
                  icon: const Icon(Icons.cloud_download_outlined),
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogueNewPage()));
                    load();
                  },
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search name, generic, company, barcode…'),
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
                              if (p.supplier.isNotEmpty) 'from ${p.supplier}',
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

/// Edit a catalogue product (or a new one), save or delete it. keepDraft: the
/// New product page, whose unsaved work is kept when going back.
class CatalogProductPage extends StatefulWidget {
  const CatalogProductPage({super.key, required this.product, this.keepDraft = false});
  final CatalogProduct product;
  final bool keepDraft;
  @override
  State<CatalogProductPage> createState() => _CatalogProductPageState();
}

class _CatalogProductPageState extends State<CatalogProductPage> with WidgetsBindingObserver {
  var form = GlobalKey<ProductFormState>();
  late CatalogProduct product = widget.product;

  /// Keeps unsaved New product work as the draft (on leaving, or the app going to the background).
  void _keep() {
    final f = form.currentState;
    if (!widget.keepDraft || f == null || !f.changed) return;
    catalogNewDraft = f.readDraft();
    keepDrafts();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _keep();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    final restored = widget.keepDraft && identical(product, catalogNewDraft);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final f = form.currentState;
        leaveEditor(context, changed: f?.changed ?? false, keep: widget.keepDraft ? _keep : null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(product.name.isEmpty ? 'New product' : product.name),
          actions: [
            if (product.name.isNotEmpty)
              IconButton(
                tooltip: 'Make a copy (another flavour or size)',
                icon: const Icon(Icons.copy_all_rounded),
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CatalogProductPage(product: copyAsVariant(form.currentState!.read())))),
              ),
            if (product.name.isNotEmpty)
              IconButton(
                tooltip: 'Delete from the catalogue',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await confirm(context, 'Delete ${product.name}?', 'It leaves the catalogue, on your team\'s devices too. Shops keep their own copy.')) {
                    return;
                  }
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
              if (restored)
                DraftBar(
                  onStartOver: () => setState(() {
                    catalogNewDraft = null;
                    keepDrafts();
                    product = CatalogProduct(name: '');
                    form = GlobalKey<ProductFormState>();
                  }),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: identifyButton(context, Shop(name: 'the catalogue'), form),
              ),
              const SizedBox(height: 8),
              FutureBuilder(
                future: Future.wait([db.knownUnits(), db.suppliers()]),
                builder: (context, snap) => snap.data == null
                    ? const LinearProgressIndicator()
                    : ProductForm(
                        key: form,
                        product: product,
                        units: snap.data![0] as List<String>,
                        suppliers: [for (final x in snap.data![1] as List<CatalogSupplier>) (uid: x.uid, name: x.name)],
                      ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final problem = form.currentState!.problem();
            if (problem != null) return toast(context, problem, error: true);
            final p = form.currentState!.read();
            if (p.name.isEmpty) return toast(context, 'Give it a name', error: true);
            for (final code in p.allCodes) {
              final other = await db.productByBarcode(code);
              if (other != null && other.uid != p.uid && context.mounted) {
                return toast(context, '$code is already on “${other.name}”: if they are the same product, merge them in Duplicates', error: true);
              }
            }
            if (p.supplier.isNotEmpty && !(await db.suppliers()).any((x) => x.name.toLowerCase() == p.supplier.toLowerCase())) {
              await db.saveSupplier(CatalogSupplier(name: p.supplier, kinds: {...p.kinds}));
            }
            await db.saveProduct(p);
            if (widget.keepDraft) {
              catalogNewDraft = null;
              keepDrafts();
            }
            if (context.mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.save_rounded),
          label: const Text('Save'),
        ),
      ),
    );
  }
}
