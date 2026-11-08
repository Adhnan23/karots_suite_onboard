import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state.dart';
import '../sync/match.dart';
import '../sync/push.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
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
class ShopProductEditor extends StatefulWidget {
  const ShopProductEditor({super.key, required this.shop, required this.draft});
  final Shop shop;
  final Draft draft;
  @override
  State<ShopProductEditor> createState() => _ShopProductEditorState();
}

class _ShopProductEditorState extends State<ShopProductEditor> {
  var form = GlobalKey<ProductFormState>(); // a new key when another product is picked, so the form starts over
  final stock = GlobalKey<StockEditorState>();
  late Draft d = widget.draft;
  late String supplierChoice = d.supplierId > 0 ? 'shop:${d.supplierId}' : 'none';
  final newSupplier = TextEditingController();
  List<CatalogSupplier> catalogSuppliers = [];
  bool busy = false;
  Shop get s => widget.shop;
  bool get isNew => d.remoteId == 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.of(context).db.suppliers().then((x) => mounted ? setState(() => catalogSuppliers = x) : null);
    if (isNew && supplierChoice == 'none' && d.product.supplier.isNotEmpty) {
      final hit = _shopSuppliers.where((x) => normName('${x['name']}') == normName(d.product.supplier)).firstOrNull;
      if (hit != null) supplierChoice = 'shop:${hit['id']}';
    }
  }

  List<Map> get _shopSuppliers => [for (final x in (s.snapshot['suppliers'] as List? ?? [])) x as Map];

  Future<void> pickFromCatalogue() async {
    final all = await AppScope.of(context).db.products();
    if (!mounted) return;
    final p = await showModalBottomSheet<CatalogProduct>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CatalogPick(all: all, kind: s.kind),
    );
    if (p != null) {
      setState(() {
        d = Draft(product: CatalogProduct.fromJson({...p.toJson()}), mode: d.mode, batches: d.batches);
        form = GlobalKey<ProductFormState>();
      });
    }
  }

  Future<void> save() async {
    final app = AppScope.of(context);
    final p = form.currentState!.read();
    if (p.name.isEmpty) return toast(context, 'Give it a name', error: true);
    stock.currentState?.apply();
    d.product = p;
    d.supplierId = 0;
    d.newSupplier = null;
    if (supplierChoice.startsWith('shop:')) d.supplierId = int.parse(supplierChoice.substring(5));
    if (supplierChoice.startsWith('cat:')) d.newSupplier = catalogSuppliers.firstWhere((x) => x.uid == supplierChoice.substring(4));
    if (supplierChoice == 'new' && newSupplier.text.trim().isNotEmpty) d.newSupplier = CatalogSupplier(name: newSupplier.text.trim());
    final c = app.session(s);
    setState(() => busy = true);
    try {
      if (c == null) {
        await queue(app.db, s, isNew ? 'create' : 'update', d);
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
        if (mounted) toast(context, '${p.name} is in ${s.name}');
      } else {
        await pushUpdate(app.db, c, s, d);
        if (mounted) toast(context, '${p.name} changed in ${s.name}');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
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
    final inShop = {for (final x in _shopSuppliers) normName('${x['name']}')};
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New product for ${s.name}' : 'Change in ${s.name}'),
        actions: [
          if (isNew) TextButton.icon(onPressed: pickFromCatalogue, icon: const Icon(Icons.inventory_2_outlined), label: const Text('From catalogue')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          if (editorTools.isNotEmpty) Wrap(spacing: 8, children: [for (final t in editorTools) t(context, s, form)]),
          const SizedBox(height: 8),
          ProductForm(
            key: form,
            product: d.product,
            fieldLabels: labels,
            categories: [for (final n in cats) _path(cats, n as Map)],
            units: [for (final u in (s.snapshot['units'] as List? ?? [])) '${(u as Map)['abbreviation']}'],
          ),
          const SizedBox(height: 12),
          Section(
            title: 'Supplier',
            children: [
              DropdownButtonFormField<String>(
                initialValue: supplierChoice,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Usually from'),
                items: [
                  const DropdownMenuItem(value: 'none', child: Text('None')),
                  for (final x in _shopSuppliers) DropdownMenuItem(value: 'shop:${x['id']}', child: Text('${x['name']}')),
                  for (final x in catalogSuppliers.where((x) => !inShop.contains(normName(x.name))))
                    DropdownMenuItem(
                      value: 'cat:${x.uid}',
                      child: Text('${x.name}  · from the catalogue', style: TextStyle(color: c.mutedForeground)),
                    ),
                  const DropdownMenuItem(value: 'new', child: Text('A new supplier…')),
                ],
                onChanged: (v) => setState(() => supplierChoice = v ?? 'none'),
              ),
              if (supplierChoice == 'new') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: newSupplier,
                  decoration: const InputDecoration(labelText: 'New supplier\'s name'),
                ),
              ],
            ],
          ),
          if (isNew) ...[
            const SizedBox(height: 12),
            Section(
              title: 'Old stock',
              children: [StockEditor(key: stock, draft: d)],
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : save,
        backgroundColor: c.brand,
        foregroundColor: c.brandForeground,
        icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload_rounded),
        label: Text(AppScope.of(context).connected(s) ? (isNew ? 'Put in ${s.name}' : 'Save in ${s.name}') : 'Save to push later'),
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
    final n = normName(q);
    final list = [
      for (final p in widget.all)
        if (n.isEmpty || normName(p.name).contains(n) || p.allCodes.any((x) => x.contains(q.trim()))) p,
    ]..sort((a, b) => (b.kinds.contains(widget.kind) ? 1 : 0) - (a.kinds.contains(widget.kind) ? 1 : 0));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Name or barcode'),
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
