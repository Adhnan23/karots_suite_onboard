import 'package:flutter/material.dart';

import '../sync/match.dart';
import '../theme/tokens.dart';

typedef ShopSupplier = ({int id, String name});
typedef CatSupplier = ({String uid, String name});

/// Who a product usually comes from, searchable: the shop's suppliers, then the
/// catalogue's (made in the shop on push), or a new one by name, or none.
/// value: `none`, `shop:ID`, `cat:UID` or `new:NAME`.
class SupplierField extends StatelessWidget {
  const SupplierField({super.key, required this.value, required this.shop, required this.catalogue, required this.onChanged});
  final String value;
  final List<ShopSupplier> shop;
  final List<CatSupplier> catalogue;
  final ValueChanged<String> onChanged;

  String get label {
    if (value.startsWith('shop:')) return shop.where((x) => 'shop:${x.id}' == value).firstOrNull?.name ?? 'None';
    if (value.startsWith('cat:')) return '${catalogue.where((x) => 'cat:${x.uid}' == value).firstOrNull?.name ?? ''} · from the catalogue';
    if (value.startsWith('new:')) return '${value.substring(4)} · new';
    return 'None';
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(KsTokens.radiusSm),
      onTap: () async {
        final v = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _Sheet(field: this),
        );
        if (v != null) onChanged(v);
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Usually from', suffixIcon: Icon(Icons.expand_more_rounded)),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: value == 'none' ? c.faint : c.foreground),
        ),
      ),
    );
  }
}

class _Sheet extends StatefulWidget {
  const _Sheet({required this.field});
  final SupplierField field;
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final f = widget.field;
    final n = normName(q);
    final inShop = {for (final x in f.shop) normName(x.name)};
    final shop = [
      for (final x in f.shop)
        if (n.isEmpty || normName(x.name).contains(n)) x,
    ];
    final cat = [
      for (final x in f.catalogue)
        if (!inShop.contains(normName(x.name)) && (n.isEmpty || normName(x.name).contains(n))) x,
    ];
    final exact = [...f.shop.map((x) => x.name), ...f.catalogue.map((x) => x.name)].any((x) => normName(x) == n);
    Widget tile(String text, String v, {String? sub, IconData? icon}) => ListTile(
      leading: icon == null ? null : Icon(icon, color: c.mutedForeground),
      title: Text(text),
      subtitle: sub == null ? null : Text(sub),
      selected: f.value == v,
      selectedTileColor: c.brandSoft,
      selectedColor: c.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KsTokens.radiusSm)),
      onTap: () => Navigator.pop(context, v),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search suppliers'),
                onChanged: (v) => setState(() => q = v),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  if (q.trim().isNotEmpty && !exact) tile('Add “${q.trim()}” as a new supplier', 'new:${q.trim()}', icon: Icons.add_rounded),
                  if (n.isEmpty) tile('None', 'none'),
                  for (final x in shop) tile(x.name, 'shop:${x.id}'),
                  if (cat.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Text(
                        'FROM THE CATALOGUE · MADE IN THE SHOP ON PUSH',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.faint),
                      ),
                    ),
                  for (final x in cat) tile(x.name, 'cat:${x.uid}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
