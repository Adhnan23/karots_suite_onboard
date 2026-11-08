import 'package:flutter/material.dart';

import '../data/models.dart';
import '../input/field_kind.dart';
import '../input/ks_field.dart';
import '../state.dart';
import '../suite/client.dart';
import '../sync/lots.dart';
import '../sync/push.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// A product the shop has: its lots, live from the shop. Change a lot's count,
/// expiry or price, or add a batch of old stock (intake: no bill, no money).
class LotsSection extends StatefulWidget {
  const LotsSection({super.key, required this.shop, required this.productId, required this.product});
  final Shop shop;
  final int productId;
  final CatalogProduct product;
  @override
  State<LotsSection> createState() => _LotsSectionState();
}

class _LotsSectionState extends State<LotsSection> {
  ProductStock? stock;
  String error = '';
  SuiteClient? get c => AppScope.of(context).session(widget.shop);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  Future<void> load() async {
    final cl = c;
    if (cl == null) return;
    try {
      final s = await productStock(cl, widget.productId);
      if (mounted) {
        setState(() {
          stock = s;
          error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  /// Old stock needs Stock-take on in the shop: offers to turn it on.
  Future<bool> stockTakeOn(SuiteClient cl) async {
    if (widget.shop.snapshot['stockTake'] != false) return true;
    final on = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: Text('Turn on Stock-take in ${widget.shop.name}?'),
        content: const Text('Old stock goes in through stock intake, which works only with Stock-take on (Settings → Stock-take).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Turn on')),
        ],
      ),
    );
    if (on != true) return false;
    await cl.enableStockTake();
    widget.shop.snapshot['stockTake'] = true;
    if (mounted) await AppScope.of(context).db.saveShop(widget.shop);
    return true;
  }

  Future<Map<String, String>?> form(String title, {Lot? lot}) {
    final qty = TextEditingController(text: lot?.qty ?? '');
    final expiry = TextEditingController(text: lot?.expiry ?? '');
    final cost = TextEditingController();
    final price = TextEditingController(text: lot?.price ?? '');
    return showDialog<Map<String, String>>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              KsField(label: lot == null ? 'Quantity' : 'Count now', controller: qty, kind: FieldKind.number),
              const SizedBox(height: 10),
              KsField(label: 'Expiry', controller: expiry, kind: FieldKind.date),
              if (lot == null) ...[
                const SizedBox(height: 10),
                KsField(label: 'Cost (blank = the product\'s)', controller: cost, kind: FieldKind.number),
              ],
              const SizedBox(height: 10),
              KsField(label: 'Price (blank = the product\'s)', controller: price, kind: FieldKind.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(d, {'qty': qty.text.trim(), 'expiry': expiry.text.trim(), 'cost': cost.text.trim(), 'price': price.text.trim()}),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> add() async {
    final cl = c;
    if (cl == null) return;
    final v = await form('Add a batch of old stock');
    if (v == null || v['qty']!.isEmpty || !mounted) return;
    if (!await stockTakeOn(cl) || !mounted) return;
    final p = widget.product;
    final ok = await guard(
      context,
      () => cl.intakeRestock(
        widget.productId,
        quantity: v['qty']!,
        expiry: v['expiry']!,
        cost: v['cost']!.isEmpty ? p.cost : v['cost']!,
        selling: v['price']!.isEmpty ? p.selling : v['price']!,
        wholesale: p.wholesale,
      ),
    );
    if (ok != null) {
      if (mounted) toast(context, 'Batch added');
      load();
    }
  }

  Future<void> addLater() async {
    final app = AppScope.of(context);
    final v = await form('Add a batch of old stock');
    if (v == null || v['qty']!.isEmpty) return;
    await queueBatch(
      app.db,
      widget.shop,
      widget.productId,
      widget.product,
      StockBatch(qty: v['qty']!, expiry: v['expiry']!, cost: v['cost']!, selling: v['price']!),
    );
    if (mounted) toast(context, 'Saved to push when ${widget.shop.name} is connected');
  }

  Future<void> edit(Lot lot) async {
    final cl = c, s = stock;
    if (cl == null || s == null) return;
    final v = await form('Change this batch', lot: lot);
    if (v == null || !mounted) return;
    final ok = await guard(context, () async {
      await editLot(cl, widget.productId, s, lot, count: v['qty'], expiry: v['expiry'], price: v['price']);
      return true;
    });
    if (ok == true) {
      if (mounted) toast(context, 'Batch changed');
      load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = KsTokens.of(context);
    if (c == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Connect to ${widget.shop.name} to see and change its batches. A new batch can wait to be pushed.',
            style: TextStyle(color: k.mutedForeground),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(onPressed: addLater, icon: const Icon(Icons.schedule_rounded), label: const Text('Add batch (push later)')),
          ),
        ],
      );
    }
    final s = stock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error.isNotEmpty) Text(error, style: TextStyle(color: k.danger)),
        if (s == null && error.isEmpty) const LinearProgressIndicator(),
        if (s != null) ...[
          Text('${s.total} in stock · ${s.lots.length} batch${s.lots.length == 1 ? '' : 'es'}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final l in s.lots)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: k.muted,
                borderRadius: BorderRadius.circular(KsTokens.radiusSm),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KsTokens.radiusSm)),
                  title: Text(
                    '${l.qty} · ${l.expiry.isEmpty ? 'no expiry' : 'expires ${l.expiry}'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      'cost ${l.cost}',
                      l.price.isEmpty ? 'price follows the product' : 'price ${l.price}',
                      if (l.source.isNotEmpty) l.source,
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => edit(l),
                ),
              ),
            ),
          Text('A count changed here is booked as a stock correction, as on the shop\'s Stock page.', style: TextStyle(color: k.faint, fontSize: 12)),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(onPressed: add, icon: const Icon(Icons.add_rounded), label: const Text('Add batch')),
        ),
      ],
    );
  }
}
