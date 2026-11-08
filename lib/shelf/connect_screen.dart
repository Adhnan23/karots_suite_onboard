import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../suite/client.dart';
import '../theme/tokens.dart';

/// Signing in to Karots Shelf: the shop's address (once), then the person's own
/// phone number and PIN. Needs the shop in reach.
class ShelfConnectScreen extends StatefulWidget {
  const ShelfConnectScreen({super.key, required this.device, required this.onSignedIn, this.address = '', this.phone = '', this.onBack});
  final String device, address, phone;

  /// Signed in: the client, who, the PIN typed and the shop's name.
  final void Function(SuiteClient c, ShelfUser who, String phone, String pin, String shopName) onSignedIn;

  /// Back to the lock (when someone is already on this phone).
  final VoidCallback? onBack;
  @override
  State<ShelfConnectScreen> createState() => _ShelfConnectScreenState();
}

class _ShelfConnectScreenState extends State<ShelfConnectScreen> {
  late final address = TextEditingController(text: widget.address);
  late final phone = TextEditingController(text: widget.phone);
  final pin = TextEditingController();
  String error = '';
  bool busy = false;

  String get _base {
    var a = address.text.trim();
    if (!a.contains('://')) a = 'http://$a';
    if (!RegExp(r':\d+$').hasMatch(Uri.parse(a).authority)) a = '$a:3000';
    return a;
  }

  Future<void> _go() async {
    if (busy || address.text.trim().isEmpty || phone.text.trim().isEmpty || pin.text.isEmpty) {
      return setState(() => error = 'Fill in the shop, your phone number and your PIN');
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final c = SuiteClient(_base, app: 'shelf', device: widget.device);
      final who = await c.signInPerson(phone.text.trim(), pin.text);
      final me = await c.me();
      widget.onSignedIn(c, who, phone.text.trim(), pin.text, me.shopName);
    } on SuiteError catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = "Can't reach the shop: check the address and that this phone is on the shop's Wi-Fi");
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return Scaffold(
      appBar: widget.onBack == null ? null : AppBar(leading: BackButton(onPressed: widget.onBack)),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(KsTokens.radius),
                    child: Image.asset('assets/icon_shelf.png', width: 64, height: 64, alignment: Alignment.centerLeft),
                  ),
                  const SizedBox(height: 18),
                  Text('Karots Shelf', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Sign in with the phone number and PIN you use at the till.', style: TextStyle(color: c.mutedForeground)),
                  const SizedBox(height: 22),
                  TextField(
                    controller: address,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Shop address', hintText: '192.168.1.10'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Your phone number'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'PIN', counterText: ''),
                    onSubmitted: (_) => _go(),
                  ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(error, style: TextStyle(color: c.danger)),
                    ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: busy ? null : _go,
                    child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
