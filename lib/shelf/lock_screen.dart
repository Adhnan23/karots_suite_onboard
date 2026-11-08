import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'account.dart';

/// The page a Shelf phone opens on: the person's PIN, checked on the phone so it
/// works offline. 5 wrong in a row and only an online sign-in opens it.
class ShelfLockScreen extends StatefulWidget {
  const ShelfLockScreen({super.key, required this.account, required this.accounts, required this.onOpen, required this.onSignIn});
  final ShelfAccount account;
  final ShelfAccounts accounts;

  /// Unlocked, with the PIN typed (kept in memory to sign in to the shop).
  final void Function(String pin) onOpen;

  /// To the sign-in page: someone else, or this person again online (phone given).
  final void Function({String? phone}) onSignIn;
  @override
  State<ShelfLockScreen> createState() => _ShelfLockScreenState();
}

class _ShelfLockScreenState extends State<ShelfLockScreen> {
  final pin = TextEditingController();
  String error = '';
  bool busy = false;
  ShelfAccount get a => widget.account;

  Future<void> _go() async {
    if (a.lockedOut || pin.text.isEmpty || busy) return;
    setState(() => busy = true);
    final ok = await a.checkPin(pin.text);
    a.wrongTries = ok ? 0 : a.wrongTries + 1;
    await widget.accounts.save(a);
    if (!mounted) return;
    final typed = pin.text;
    pin.clear();
    setState(() {
      busy = false;
      error = ok || a.lockedOut ? '' : 'Wrong PIN';
    });
    if (ok) widget.onOpen(typed);
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return Scaffold(
      body: Center(
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
                Text('${a.name} · ${a.phone}', style: TextStyle(color: c.mutedForeground)),
                const SizedBox(height: 22),
                if (a.lockedOut) ...[
                  Text('Too many wrong PINs: sign in again with the shop in reach.', style: TextStyle(color: c.danger)),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => widget.onSignIn(phone: a.phone),
                    child: const Text('Sign in again'),
                  ),
                ] else ...[
                  TextField(
                    controller: pin,
                    autofocus: true,
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
                  FilledButton(onPressed: busy ? null : _go, child: const Text('Open')),
                ],
                TextButton(onPressed: () => widget.onSignIn(), child: const Text('Someone else')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
