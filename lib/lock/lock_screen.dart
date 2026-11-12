import 'dart:io';

import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../settings/secure.dart';
import '../suite/support_pin.dart';
import '../theme/tokens.dart';
import 'app_identity.dart';

/// When the install ID's code was last entered on this phone (ISO time).
const codeDayKey = 'code_at';

/// The phone's own unlock opens the app only within 24 hours of the code being
/// entered here: a fresh install or cleared storage needs the code, and so does
/// each new 24 hours, so a copied APK can't be opened with someone else's phone.
/// A clock set back doesn't stretch it.
bool phoneUnlockAllowed(String? codeAt, DateTime now) {
  final at = DateTime.tryParse(codeAt ?? '');
  if (at == null || now.isBefore(at)) return false;
  return now.difference(at) < const Duration(hours: 24);
}

/// Opens with this hour's code for the app's own install ID (from the PIN app),
/// like a shop's system user or the Demo Room. Nothing to set up first: support
/// secrets are added afterwards, under the key icon. On Android, for 24 hours
/// after the code, the phone's own unlock opens it too (fingerprint, or its
/// PIN / pattern).
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
  final _auth = LocalAuthentication();
  bool _canUnlock = false; // the phone has a fingerprint, face or screen lock

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isWindows) _offerPhoneUnlock(); // Windows: Windows Hello (PIN, face, fingerprint)
  }

  Future<void> _offerPhoneUnlock() async {
    if (!phoneUnlockAllowed(await widget.store.read(codeDayKey), DateTime.now())) return; // the code first, every 24 hours
    try {
      if (!await _auth.isDeviceSupported() || !mounted) return;
    } catch (_) {
      return;
    }
    setState(() => _canUnlock = true);
    _bio();
  }

  /// Fingerprint, or the phone's own PIN / pattern when there's none.
  Future<void> _bio() async {
    try {
      if (await _auth.authenticate(localizedReason: 'Open Karots Onboard')) widget.onOpen();
    } on LocalAuthException catch (e) {
      const quiet = {LocalAuthExceptionCode.userCanceled, LocalAuthExceptionCode.systemCanceled, LocalAuthExceptionCode.userRequestedFallback};
      if (mounted && !quiet.contains(e.code)) setState(() => error = 'Unlock didn\'t work (${e.code.name}). Use the code.');
    } catch (e) {
      if (mounted) setState(() => error = 'Unlock didn\'t work. Use the code.');
    }
  }

  Future<void> _go() async {
    if (validPin(_seed, code.text, DateTime.now())) {
      await widget.store.write(codeDayKey, DateTime.now().toIso8601String());
      return widget.onOpen();
    }
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
                if (_canUnlock) TextButton.icon(onPressed: _bio, icon: const Icon(Icons.fingerprint), label: Text(Platform.isWindows ? 'Unlock with Windows Hello' : 'Unlock with this phone')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
