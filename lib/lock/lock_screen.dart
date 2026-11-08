import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../settings/secure.dart';
import '../theme/tokens.dart';
import 'app_lock.dart';

/// First run: choose the app PIN and paste the support secret. After: the PIN
/// (or a fingerprint on Android) opens the app.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.store, required this.onOpen});
  final KeyStore store;
  final VoidCallback onOpen;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  late final lock = AppLock(widget.store);
  final pin = TextEditingController();
  final secret = TextEditingController();
  bool? firstRun;
  String error = '';

  @override
  void initState() {
    super.initState();
    lock.hasPin().then((has) {
      setState(() => firstRun = !has);
      if (has) _bio();
    });
  }

  Future<void> _bio() async {
    if (!Platform.isAndroid) return;
    try {
      final auth = LocalAuthentication();
      if (await auth.canCheckBiometrics && await auth.authenticate(localizedReason: 'Open Karots Suite Onboard')) widget.onOpen();
    } catch (_) {}
  }

  Future<void> _go() async {
    if (firstRun == true) {
      if (pin.text.length < 4) return setState(() => error = 'Choose a PIN of 4 or more digits');
      if (secret.text.trim().isEmpty) return setState(() => error = 'Paste the support secret (POS_SUPPORT_SECRET)');
      await lock.setPin(pin.text);
      await widget.store.write(supportSecretKey, secret.text.trim());
      widget.onOpen();
    } else if (await lock.check(pin.text)) {
      widget.onOpen();
    } else {
      setState(() => error = 'Wrong PIN');
      pin.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    if (firstRun == null) return const Scaffold();
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(KsTokens.radius)),
                child: Icon(Icons.inventory_2_rounded, color: c.brandForeground),
              ),
              const SizedBox(height: 18),
              Text('Karots Suite Onboard', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(firstRun! ? 'Set up this device. The secret opens every shop, so the app keeps it behind your PIN.' : 'Enter your PIN',
                  style: TextStyle(color: c.mutedForeground)),
              const SizedBox(height: 22),
              TextField(
                controller: pin, autofocus: true, obscureText: true, keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: firstRun! ? 'Choose a PIN' : 'PIN'),
                onSubmitted: (_) => _go(),
              ),
              if (firstRun!) ...[
                const SizedBox(height: 12),
                TextField(controller: secret, obscureText: true, decoration: const InputDecoration(labelText: 'Support secret')),
              ],
              if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error, style: TextStyle(color: c.danger))),
              const SizedBox(height: 18),
              FilledButton(onPressed: _go, child: Text(firstRun! ? 'Save and open' : 'Open')),
              if (!firstRun! && Platform.isAndroid) TextButton.icon(onPressed: _bio, icon: const Icon(Icons.fingerprint), label: const Text('Use fingerprint')),
            ]),
          ),
        ),
      ),
    );
  }
}
