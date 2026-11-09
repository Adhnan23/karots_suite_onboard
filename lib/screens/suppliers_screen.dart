import 'package:flutter/material.dart';

import '../data/models.dart';
import '../input/field_kind.dart';
import '../input/ks_field.dart';
import '../state.dart';
import '../sync/match.dart';
import '../sync/push.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'supplier_page.dart';

/// Add or edit a supplier (every field reads from a photo too); returns it.
Future<CatalogSupplier?> editSupplier(BuildContext context, [CatalogSupplier? x]) {
  final name = TextEditingController(text: x?.name ?? '');
  final contact = TextEditingController(text: x?.contact ?? '');
  final phone = TextEditingController(text: x?.phone ?? '');
  final address = TextEditingController(text: x?.address ?? '');
  final days = TextEditingController(text: (x?.creditDays ?? 0) == 0 ? '' : '${x!.creditDays}');
  return showModalBottomSheet<CatalogSupplier>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(x == null ? 'New supplier' : 'Edit ${x.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            KsField(label: 'Name', controller: name),
            const SizedBox(height: 10),
            KsField(label: 'Contact person', controller: contact),
            const SizedBox(height: 10),
            KsField(label: 'Phone', controller: phone, kind: FieldKind.barcode),
            const SizedBox(height: 10),
            KsField(label: 'Address', controller: address),
            const SizedBox(height: 10),
            KsField(label: 'Credit days', controller: days, kind: FieldKind.number),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(
                  ctx,
                  CatalogSupplier(
                    uid: x?.uid,
                    name: name.text.trim(),
                    contact: contact.text.trim(),
                    phone: phone.text.trim(),
                    address: address.text.trim(),
                    creditDays: int.tryParse(days.text.trim()) ?? 0,
                    kinds: x?.kinds,
                    sources: x?.sources,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The catalogue's suppliers.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});
  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<CatalogSupplier> all = [];
  String q = '';

  Future<void> load() async {
    final x = await AppScope.of(context).db.suppliers();
    if (mounted) setState(() => all = x);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  Future<void> open([CatalogSupplier? x]) async {
    final db = AppScope.of(context).db;
    final saved = await editSupplier(context, x);
    if (saved == null) return;
    await db.saveSupplier(saved);
    load();
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final n = normName(q);
    final list = [
      for (final x in all)
        if (n.isEmpty || normName(x.name).contains(n) || x.phone.contains(q.trim())) x,
    ];
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.brand,
        foregroundColor: c.brandForeground,
        onPressed: open,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New supplier'),
      ),
      body: Column(
        children: [
          PageHead(title: 'Suppliers', sub: '${all.length} in the catalogue'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by name or phone'),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Empty(
                    icon: Icons.local_shipping_rounded,
                    title: all.isEmpty ? 'No suppliers yet' : 'Nothing matches',
                    sub: all.isEmpty ? 'Pull a shop, or add one.' : null,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final x = list[i];
                      return Card(
                        child: ListTile(
                          title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [x.contact, x.phone, if (x.creditDays > 0) '${x.creditDays} days credit'].where((s) => s.isNotEmpty).join(' · '),
                          ),
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => SupplierPage(supplier: x)));
                            load();
                          },
                          trailing: IconButton(
                            tooltip: 'Remove from the catalogue',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final db = AppScope.of(context).db;
                              if (!await confirm(
                                context,
                                'Remove ${x.name}?',
                                'They leave the catalogue\'s suppliers, on your team\'s devices too. Shops keep their own.',
                              )) {
                                return;
                              }
                              await db.deleteSupplier(x.uid);
                              load();
                            },
                          ),
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

/// A shop's suppliers (from its last pull, plus any added here); add one from the
/// catalogue or a new one.
class ShopSuppliersScreen extends StatefulWidget {
  const ShopSuppliersScreen({super.key, required this.shop});
  final Shop shop;
  @override
  State<ShopSuppliersScreen> createState() => _ShopSuppliersScreenState();
}

class _ShopSuppliersScreenState extends State<ShopSuppliersScreen> {
  Shop get s => widget.shop;
  List<Map> get list => [for (final x in (s.snapshot['suppliers'] as List? ?? [])) x as Map];

  Future<void> add() async {
    final app = AppScope.of(context);
    final c = app.session(s);
    if (c == null) return toast(context, 'Connect to ${s.name} first', error: true);
    final have = {for (final x in list) normName('${x['name']}')};
    final cat = [
      for (final x in await app.db.suppliers())
        if (!have.contains(normName(x.name))) x,
    ];
    if (!mounted) return;
    final pick = await showModalBottomSheet<CatalogSupplier>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _AddPick(catalogue: cat),
    );
    if (pick == null || !mounted) return;
    final id = await guard(context, () => pushSupplier(app.db, c, s, pick));
    if (id != null && mounted) {
      setState(() {});
      app.pushed(s);
      toast(context, '${pick.name} is in ${s.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${s.name} · suppliers')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.brand,
        foregroundColor: c.brandForeground,
        onPressed: add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add supplier'),
      ),
      body: list.isEmpty
          ? const Empty(icon: Icons.local_shipping_rounded, title: 'No suppliers known', sub: 'Pull the shop, or add one.')
          : Narrow(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                children: [
                  for (final x in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Card(child: ListTile(title: Text('${x['name']}'))),
                    ),
                ],
              ),
            ),
    );
  }
}

class _AddPick extends StatefulWidget {
  const _AddPick({required this.catalogue});
  final List<CatalogSupplier> catalogue;
  @override
  State<_AddPick> createState() => _AddPickState();
}

class _AddPickState extends State<_AddPick> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final n = normName(q);
    final list = [
      for (final x in widget.catalogue)
        if (n.isEmpty || normName(x.name).contains(n)) x,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search the catalogue\'s suppliers'),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('A new supplier…'),
            onTap: () async {
              final x = await editSupplier(context, q.trim().isEmpty ? null : CatalogSupplier(name: q.trim()));
              if (x != null && context.mounted) Navigator.pop(context, x);
            },
          ),
          Expanded(
            child: ListView(
              children: [
                for (final x in list)
                  ListTile(title: Text(x.name), subtitle: x.phone.isEmpty ? null : Text(x.phone), onTap: () => Navigator.pop(context, x)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
