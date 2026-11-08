import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// How the app reaches this shop, and whether the sign-in is protected on the way.
class ConnectInfo extends StatelessWidget {
  const ConnectInfo({super.key, required this.shop});
  final Shop shop;
  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final ts = shop.viaTailscale;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: (ts ? c.success : c.warning).withValues(alpha: .1), borderRadius: BorderRadius.circular(KsTokens.radiusSm)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ts ? Icons.lock_rounded : Icons.wifi_rounded, color: ts ? c.success : c.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ts
                  ? 'Through Tailscale: the sign-in travels encrypted.'
                  : 'Through the shop\'s Wi-Fi: the system user\'s sign-in is not encrypted on the way. Use Tailscale when you can.',
              style: TextStyle(color: c.foreground, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Signs in to the shop; returns true when connected.
Future<bool> connectShop(BuildContext context, Shop shop) async {
  final app = AppScope.of(context);
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ConnectSheet(shop: shop, app: app),
  );
  return ok == true;
}

class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet({required this.shop, required this.app});
  final Shop shop;
  final AppState app;
  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  bool busy = false;
  String error = '';

  Future<void> go() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final c = await widget.app.connect(widget.shop);
      final me = await c.me();
      widget.shop.snapshot = {...widget.shop.snapshot, 'plugins': me.plugins, 'stockTake': me.stockTakeEnabled, 'shopName': me.shopName};
      await widget.app.db.saveShop(widget.shop);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        busy = false;
        error = errText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Connect to ${widget.shop.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${widget.shop.address} · as the system user', style: TextStyle(color: c.mutedForeground)),
          const SizedBox(height: 14),
          ConnectInfo(shop: widget.shop),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error, style: TextStyle(color: c.danger)),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : go,
            icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded),
            label: Text(busy ? 'Signing in…' : 'Connect'),
          ),
        ],
      ),
    );
  }
}
