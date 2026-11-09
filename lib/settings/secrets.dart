import 'dart:convert';

import '../data/models.dart';
import 'secure.dart';

typedef Secret = ({String name, String secret});

/// The support secrets, each named ("Main", "Reseller A"); a shop picks one. Kept
/// in secure storage. A device set up with a single secret reads it as "Main".
class Secrets {
  Secrets(this.store);
  final KeyStore store;
  static const key = 'support_secrets';

  Future<List<Secret>> all() async {
    final raw = await store.read(key);
    if (raw != null) {
      return [for (final x in jsonDecode(raw) as List) (name: '${x['name']}', secret: '${x['secret']}')];
    }
    final single = await store.read(supportSecretKey);
    return single == null || single.isEmpty ? [] : [(name: 'Main', secret: single)];
  }

  Future<void> save(List<Secret> list) => store.write(
    key,
    jsonEncode([
      for (final x in list) {'name': x.name, 'secret': x.secret},
    ]),
  );

  /// The shop's secret: the one it names, else the first.
  Future<String> forShop(Shop s) async {
    final list = await all();
    if (list.isEmpty) return '';
    return (list.where((x) => x.name == s.secretName).firstOrNull ?? list.first).secret;
  }

  /// Forgets every support secret on this device (they're never in a backup).
  Future<void> clear() async {
    await save([]);
    await store.write(supportSecretKey, '');
  }
}
