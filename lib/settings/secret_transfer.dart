import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'secrets.dart';

/// Support secrets carried to another device as text (share, paste), sealed with
/// a passphrase the person types on both: AES-256-GCM, key from PBKDF2-SHA256.
/// Never through team or device sync (plain HTTP on the Wi-Fi).
const _prefix = 'KSEC1:';
const _rounds = 150000;
final _gcm = AesGcm.with256bits();
final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _rounds, bits: 256);

Future<String> sealSecrets(List<Secret> list, String passphrase) async {
  final salt = SecretKeyData.random(length: 16).bytes;
  final key = await _kdf.deriveKeyFromPassword(password: passphrase, nonce: salt);
  final plain = utf8.encode(jsonEncode([
    for (final x in list) {'name': x.name, 'secret': x.secret},
  ]));
  final box = await _gcm.encrypt(plain, secretKey: key);
  return _prefix + base64Url.encode([...salt, ...box.concatenation()]);
}

class WrongPassphrase implements Exception {}

/// The secrets in [text]; [WrongPassphrase] when it won't open, [FormatException] when it isn't one.
Future<List<Secret>> openSecrets(String text, String passphrase) async {
  final t = text.trim();
  if (!t.startsWith(_prefix)) throw const FormatException('Not a Karots secrets copy');
  final raw = base64Url.decode(t.substring(_prefix.length));
  if (raw.length < 16 + 12 + 16) throw const FormatException('Not a Karots secrets copy');
  final key = await _kdf.deriveKeyFromPassword(password: passphrase, nonce: raw.sublist(0, 16));
  final box = SecretBox.fromConcatenation(raw.sublist(16), nonceLength: 12, macLength: 16);
  try {
    final plain = await _gcm.decrypt(box, secretKey: key);
    return [for (final x in jsonDecode(utf8.decode(plain)) as List) (name: '${x['name']}', secret: '${x['secret']}')];
  } on SecretBoxAuthenticationError {
    throw WrongPassphrase();
  }
}

/// [incoming] added to [mine]: a name already here takes the incoming secret.
List<Secret> mergeSecrets(List<Secret> mine, List<Secret> incoming) {
  final next = [...mine];
  for (final x in incoming) {
    final i = next.indexWhere((m) => m.name == x.name);
    i < 0 ? next.add(x) : next[i] = x;
  }
  return next;
}
