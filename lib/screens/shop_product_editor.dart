import 'package:flutter/material.dart';

import '../data/drafts.dart';
import '../data/models.dart';
import '../sync/search.dart';
import '../input/cost_code.dart';
import '../flavor.dart';
import '../input/supplier_field.dart';
import '../state.dart';
import '../suite/client.dart';
import '../sync/match.dart';
import '../sync/push.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../sync/variant.dart';
import 'lots_section.dart';
import 'product_form.dart';
import 'stock_editor.dart';

/// Hooks other screens add to the editor's header (AI Identify): given the form.
final editorTools = <Widget Function(BuildContext, Shop, GlobalKey<ProductFormState>)>[];

String _path(List cats, Map n) {
  final byId = {for (final c in cats) (c as Map)['id']: c};
  final parts = [for (final id in (n['path'] as List? ?? [])) '${byId[id]?['name'] ?? ''}', '${n['name']}'];
  return parts.where((p) => p.isNotEmpty).join(' > ');
}

/// A product for one shop: from the catalogue or new, or one the shop has
/// (remoteId set: a change, no stock). Save pushes now when connected, else waits.
///
/// keepDraft: the shop's New product page, whose unsaved work is kept when going
/// back ([ShopProductEditor.newProduct] opens it).
class ShopProductEditor extends StatefulWidget {
  const ShopProductEditor({super.key, required this.shop, required this.draft, this.keepDraft = false, this.supplier, this.restored = false});
  final Shop shop;
  final Draft draft;
  final bool keepDraft, restored;
  final String? supplier;

  /// The shop's New product: its kept draft if there is one, else a fresh one.
  factory ShopProductEditor.newProduct(Shop s) {
    final kept = shopNewDrafts[s.uid];
    return ShopProductEditor(
      shop: s,
      draft: kept?.draft ?? Draft(product: newShopProduct(s)),
      supplier: kept?.supplier,
      keepDraft: true,
      restored: kept != null,
    );
  }
  @override
  State<ShopProductEditor> createState() => _ShopProductEditorState();
}

class _ShopProductEditorState extends State<ShopProductEditor> with WidgetsBindingObserver {
  var form = GlobalKey<ProductFormState>(); // a new key when another product is picked, so the form starts over
  var stock = GlobalKey<StockEditorState>();
  late Draft d = widget.draft;
  late String supplierChoice = widget.supplier ?? (d.supplierId > 0 ? 'shop:${d.supplierId}' : 'none');
  List<CatalogSupplier> catalogSuppliers = [];
  bool busy = false;
  late bool restored = widget.restored;
  Shop get s => widget.shop;
  bool get isNew => d.remoteId == 0;

  /// Only the shop's New product page goes on to the next (Quick add has its own scan loop).
  bool get saveNext => isNew && widget.keepDraft;

  /// Keeps unsaved New product work as the shop's draft (on leaving, or the app going to the background).
  void _keep() {
    final f = form.currentState;
    if (!widget.keepDraft || f == null || !(f.changed || f.read().name.isNotEmpty || supplierChoice != 'none')) return;
    stock.currentState?.apply(raw: true);
    shopNewDrafts[s.uid] = (draft: d..product = f.readDraft(), supplier: supplierChoice);
    keepDrafts();
  }

  void _drop() {
    if (!widget.keepDraft) return;
    shopNewDrafts.remove(s.uid);
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.of(context).db.suppliers().then((x) => mounted ? setState(() => catalogSuppliers = x) : null);
    if (supplierChoice == 'none' && d.product.supplier.isNotEmpty) {
      final hit = _shopSuppliers.where((x) => normName('${x['name']}') == normName(d.product.supplier)).firstOrNull;
      if (hit != null) supplierChoice = 'shop:${hit['id']}';
    }
  }

  List<Map> get _shopSuppliers => [for (final x in (s.snapshot['suppliers'] as List? ?? [])) x as Map];

  /// After Save & next: what the last product had, for the next one on the same shelf.
  ({String category, String unit})? carry;

  /// Save & next: a fresh New product with the last one's category and unit
  /// (a shop is set up one category at a time).
  void _startNext(CatalogProduct last) => setState(() {
    carry = (category: last.category, unit: last.unit);
    d = Draft(
      product: newShopProduct(s)
        ..category = last.category
        ..unit = last.unit,
      mode: d.mode,
    );
    supplierChoice = 'none';
    form = GlobalKey<ProductFormState>();
    stock = GlobalKey<StockEditorState>();
    restored = false;
  });

  Future<void> pickFromCatalogue() async {
    final all = await AppScope.of(context).db.products();
    if (!mounted) return;
    final p = await showModalBottomSheet<CatalogProduct>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CatalogPick(all: all, kind: s.kind),
    );
    if (p != null) {
      final now = form.currentState?.read();
      setState(() {
        d = fromCatalogue(p)
          ..mode = d.mode
          ..batches = d.batches;
        // The catalogue has no categories: keep the one already chosen; after Save & next, the unit too.
        if (now != null && now.category.isNotEmpty) d.product.category = now.category;
        if (now != null && carry != null) d.product.unit = now.unit;
        form = GlobalKey<ProductFormState>();
      });
    }
  }

  Future<void> save({bool next = false}) async {
    final app = AppScope.of(context);
    final problem = form.currentState!.problem() ?? stock.currentState?.problem();
    if (problem != null) return toast(context, problem, error: true);
    final p = form.currentState!.read();
    if (p.name.isEmpty) return toast(context, 'Give it a name', error: true);
    stock.currentState?.apply();
    d.product = p;
    d.aiPick = form.currentState!.aiPick ?? d.aiPick;
    d.supplierId = 0;
    d.newSupplier = null;
    if (supplierChoice.startsWith('shop:')) d.supplierId = int.parse(supplierChoice.substring(5));
    if (supplierChoice.startsWith('cat:')) d.newSupplier = catalogSuppliers.firstWhere((x) => x.uid == supplierChoice.substring(4));
    if (supplierChoice.startsWith('new:')) d.newSupplier = CatalogSupplier(name: supplierChoice.substring(4));
    // The shop's copy remembers the supplier, so the product opens with it again.
    // None on a change keeps the shop's own (pushUpdate never clears it).
    if (isNew || supplierChoice != 'none') {
      d.product.supplier = d.newSupplier?.name ?? (_shopSuppliers.where((x) => (x['id'] as num).toInt() == d.supplierId).firstOrNull?['name'] as String? ?? '');
    }
    final c = app.session(s);
    setState(() => busy = true);
    try {
      if (c == null) {
        await queue(app.db, s, isNew ? 'create' : 'update', d, who: app.who);
        if (mounted) toast(context, 'Saved to push when ${s.name} is connected');
      } else if (isNew) {
        var r = await pushCreate(app.db, c, s, d);
        while (r.failed.isNotEmpty) {
          if (!mounted) break;
          final again = await showDialog<bool>(
            context: context,
            builder: (x) => AlertDialog(
              title: const Text('Made, but some stock was refused'),
              content: Text([for (final f in r.failed) 'Batch ${f.index + 1}: ${f.message}'].join('\n')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Leave it')),
                FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Try again')),
              ],
            ),
          );
          if (again != true) break;
          r = await retryBatches(c, r);
        }
        if (mounted) {
          final msg = r.notes.isEmpty ? '${p.name} is in ${s.name}' : '${p.name} is in ${s.name}, but: ${r.notes.join('; ')}';
          toast(context, msg, error: r.notes.isNotEmpty);
        }
      } else {
        await pushUpdate(app.db, c, s, d);
        if (mounted) toast(context, '${p.name} changed in ${s.name}');
      }
      if (c != null) app.pushed(s);
      _drop();
      if (mounted) next ? _startNext(p) : Navigator.pop(context, true);
    } on PushError catch (e) {
      if (!mounted) return;
      if (e.message != stockTakeOff || c == null) return toast(context, e.message, error: true);
      if (!app.mayChangeSettings) return toast(context, 'Ask the owner to turn on Stock-take (Settings)', error: true);
      final on = await showDialog<bool>(
        context: context,
        builder: (x) => AlertDialog(
          title: Text('Turn on Stock-take in ${s.name}?'),
          content: const Text('Old stock goes in through stock intake, which works only with Stock-take on (Settings → Stock-take).'),
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
      if (mounted) {
        setState(() => busy = false);
        return save(next: next);
      }
    } catch (e) {
      // Shelf: walked out of the Wi-Fi. Nothing reached the shop yet (or it's a
      // change, safe to send again): it waits in the queue instead.
      if (isShelf && e is! SuiteError && (!isNew || d.remoteId == 0)) {
        await queue(app.db, s, isNew ? 'create' : 'update', d, who: app.who);
        _drop();
        if (mounted) {
          toast(context, 'Out of reach: saved to push when ${s.name} is back');
          next ? _startNext(p) : Navigator.pop(context, true);
        }
        return;
      }
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final cats = s.snapshot['categories'] as List? ?? [];
    final labels = [
      for (final f in (s.snapshot['fields'] as List? ?? []))
        if ((f as Map)['isActive'] != false) '${f['label']}',
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final f = form.currentState;
        leaveEditor(context, changed: f?.changed ?? false, keep: widget.keepDraft ? _keep : null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isNew ? 'New product' : 'Change product'),
              Text(s.name, style: TextStyle(fontSize: 13, color: c.mutedForeground)),
            ],
          ),
          actions: [
            if (isNew) TextButton.icon(onPressed: pickFromCatalogue, icon: const Icon(Icons.inventory_2_outlined), label: const Text('From catalogue')),
            if (!isNew)
              IconButton(
                tooltip: 'Disable in this shop',
                icon: const Icon(Icons.block_rounded),
                onPressed: () async {
                  final app = AppScope.of(context);
                  final c = app.session(s);
                  if (c == null) return toast(context, 'Connect to ${s.name} first', error: true);
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (x) => AlertDialog(
                      title: Text('Disable ${d.product.name} in ${s.name}?'),
                      content: const Text(
                        'It stops showing at the till. The shop keeps its sales and stock history, and can enable it again on its Products page.',
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Disable')),
                      ],
                    ),
                  );
                  if (yes != true || !context.mounted) return;
                  final ok = await guard(context, () async {
                    await disableInShop(app.db, c, s, d.remoteId);
                    return true;
                  });
                  if (ok == true && context.mounted) {
                    app.pushed(s);
                    Navigator.pop(context, true);
                  }
                },
              ),
            IconButton(
              tooltip: 'Make a copy (another flavour or size)',
              icon: const Icon(Icons.copy_all_rounded),
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ShopProductEditor(
                    shop: s,
                    draft: Draft(product: copyAsVariant(form.currentState!.read()), mode: StockMode.none),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Narrow(
          child: ListView(
            key: ObjectKey(form), // Save & next starts at the top
            padding: EdgeInsets.fromLTRB(16, 4, 16, saveNext ? 170 : 110),
            children: [
              if (restored)
                DraftBar(
                  onStartOver: () => setState(() {
                    shopNewDrafts.remove(s.uid);
                    keepDrafts();
                    d = Draft(product: newShopProduct(s));
                    supplierChoice = 'none';
                    form = GlobalKey<ProductFormState>();
                    stock = GlobalKey<StockEditorState>();
                    restored = false;
                  }),
                ),
              if (editorTools.isNotEmpty) Wrap(spacing: 8, children: [for (final t in editorTools) t(context, s, form)]),
              const SizedBox(height: 8),
              ProductForm(
                key: form,
                product: d.product,
                fieldLabels: labels,
                categories: [for (final n in cats) _path(cats, n as Map)],
                units: [for (final u in (s.snapshot['units'] as List? ?? [])) '${(u as Map)['abbreviation']}'],
                costCode: codeFor(s),
              ),
              const SizedBox(height: 12),
              Section(
                title: 'Supplier',
                children: [
                  SupplierField(
                    value: supplierChoice,
                    shop: [for (final x in _shopSuppliers) (id: (x['id'] as num).toInt(), name: '${x['name']}')],
                    catalogue: [for (final x in catalogSuppliers) (uid: x.uid, name: x.name)],
                    onChanged: (v) => setState(() => supplierChoice = v),
                  ),
                ],
              ),
              if (!isNew) ...[
                const SizedBox(height: 12),
                Section(
                  title: 'Stock',
                  children: [LotsSection(shop: s, productId: d.remoteId, product: d.product)],
                ),
              ],
              if (isNew) ...[
                const SizedBox(height: 12),
                Section(
                  title: 'Old stock',
                  children: [StockEditor(key: stock, draft: d, code: codeFor(s))],
                ),
              ],
            ],
          ),
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (saveNext) ...[
              FloatingActionButton.extended(
                heroTag: 'save-next',
                onPressed: busy ? null : () => save(next: true),
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('Save & next'),
              ),
              const SizedBox(height: 10),
            ],
            FloatingActionButton.extended(
              onPressed: busy ? null : save,
              backgroundColor: c.brand,
              foregroundColor: c.brandForeground,
              icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload_rounded),
              label: Text(AppScope.of(context).connected(s) ? (isNew ? 'Put in ${s.name}' : 'Save in ${s.name}') : 'Save to push later'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogPick extends StatefulWidget {
  const _CatalogPick({required this.all, required this.kind});
  final List<CatalogProduct> all;
  final String kind;
  @override
  State<_CatalogPick> createState() => _CatalogPickState();
}

class _CatalogPickState extends State<_CatalogPick> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final found = searchProducts(widget.all, q); // best first; this shop's kind first, keeping that order
    final list = [...found.where((p) => p.kinds.contains(widget.kind)), ...found.where((p) => !p.kinds.contains(widget.kind))];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Name, generic, company or barcode'),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final p in list.take(200))
                  ListTile(
                    title: Text(p.name),
                    subtitle: Text([p.category, if (p.kinds.isNotEmpty) p.kinds.join(', ')].where((x) => x.isNotEmpty).join(' · ')),
                    trailing: p.selling.isEmpty ? null : Text('Rs ${p.selling}'),
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
