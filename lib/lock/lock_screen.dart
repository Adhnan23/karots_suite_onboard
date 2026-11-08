import 'dart:io';

import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../settings/secure.dart';
import '../suite/support_pin.dart';
import '../theme/tokens.dart';
import 'app_identity.dart';

/// Opens with this hour's code for the app's own install ID (from the PIN app),
/// like a shop's system user or the Demo Room. Nothing to set up first: support
/// secrets are added afterwards, under the key icon. Fingerprint on Android.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.store, required this.onOpen});
  final KeyStore store;
  final VoidCallback onOpen;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final code = TextEditingController();
  String error = '';
  static final _seed = hex.decode(appSeedHex);

  @override
  void initState() {
    super.initState();
    _bio();
  }

  Future<void> _bio() async {
    if (!Platform.isAndroid) return;
    try {
      final auth = LocalAuthentication();
      if (await auth.canCheckBiometrics && await auth.authenticate(localizedReason: 'Open Karots Onboard')) widget.onOpen();
    } catch (_) {}
  }

  void _go() {
    if (validPin(_seed, code.text, DateTime.now())) return widget.onOpen();
    setState(() => error = 'That isn\'t this hour\'s code');
    code.clear();
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
                  child: Image.asset('assets/icon.png', width: 64, height: 64, alignment: Alignment.centerLeft),
                ),
                const SizedBox(height: 18),
                Text('Karots Suite Onboard', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    style: TextStyle(color: c.mutedForeground),
                    children: [
                      const TextSpan(text: 'Enter this hour\'s code for install '),
                      TextSpan(
                        text: appInstallId,
                        style: TextStyle(fontWeight: FontWeight.w800, color: c.foreground),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: code,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Code', counterText: ''),
                  onSubmitted: (_) => _go(),
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error, style: TextStyle(color: c.danger)),
                  ),
                const SizedBox(height: 18),
                FilledButton(onPressed: _go, child: const Text('Open')),
                if (Platform.isAndroid) TextButton.icon(onPressed: _bio, icon: const Icon(Icons.fingerprint), label: const Text('Use fingerprint')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
