import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The system user's hourly PIN, exactly as the Suite works it out
/// (internal/support/pin.go): seed = HMAC(secret, label + install id), code =
/// HMAC(seed, hour number) → 6 digits.
const _label = 'karots-suite/support/seed/v1|';

String supportPin(String secret, String installId, DateTime t) => _code(_seed(secret, installId), t.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 3600);

/// This hour's PIN, then the previous hour's (the Suite accepts ±1 hour).
List<String> supportPinsNow(String secret, String installId, DateTime now) {
  final seed = _seed(secret, installId);
  final w = now.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 3600;
  return [_code(seed, w), _code(seed, w - 1)];
}

List<int> _seed(String secret, String installId) =>
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(_label + installId.trim().toUpperCase())).bytes;

String _code(List<int> seed, int window) {
  final buf = ByteData(8)..setUint64(0, window);
  final sum = Hmac(sha256, seed).convert(buf.buffer.asUint8List()).bytes;
  final n = ByteData.sublistView(Uint8List.fromList(sum.sublist(0, 4))).getUint32(0) % 1000000;
  return n.toString().padLeft(6, '0');
}
