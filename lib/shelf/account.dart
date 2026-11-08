import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../settings/secure.dart';

/// A person signed in to Karots Shelf on this phone: which shop, who they are,
/// and their PIN as a salted hash (for unlocking offline). The PIN itself is
/// never kept.
class ShelfAccount {
  ShelfAccount({
    required this.address,
    required this.phone,
    required this.name,
    required this.role,
    required this.pinSalt,
    required this.pinHash,
    this.wrongTries = 0,
  });
  final String address, phone, name, role, pinSalt, pinHash;

  /// Wrong PINs in a row on the offline lock; 5 means only an online sign-in opens it.
  int wrongTries;
  static const maxWrong = 5;

  static Future<ShelfAccount> make({
    required String address,
    required String phone,
    required String name,
    required String role,
    required String pin,
  }) async {
    final salt = base64Encode(SecretKeyData.random(length: 16).bytes);
    return ShelfAccount(address: address, phone: phone, name: name, role: role, pinSalt: salt, pinHash: await hashPin(pin, salt));
  }

  Future<bool> checkPin(String pin) async => await hashPin(pin, pinSalt) == pinHash;

  bool get lockedOut => wrongTries >= maxWrong;

  Map<String, Object> toJson() => {
    'address': address,
    'phone': phone,
    'name': name,
    'role': role,
    'pinSalt': pinSalt,
    'pinHash': pinHash,
    'wrongTries': wrongTries,
  };

  factory ShelfAccount.fromJson(Map m) => ShelfAccount(
    address: '${m['address']}',
    phone: '${m['phone']}',
    name: '${m['name']}',
    role: '${m['role']}',
    pinSalt: '${m['pinSalt']}',
    pinHash: '${m['pinHash']}',
    wrongTries: (m['wrongTries'] as num?)?.toInt() ?? 0,
  );
}

final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 50000, bits: 256);

/// The PIN's salted hash (PBKDF2-SHA256), base64.
Future<String> hashPin(String pin, String salt) async {
  final k = await _kdf.deriveKeyFromPassword(password: pin, nonce: base64Decode(salt));
  return base64Encode(await k.extractBytes());
}

/// The people signed in to Shelf on this phone, kept in secure storage.
class ShelfAccounts {
  ShelfAccounts(this.store);
  final KeyStore store;

  Future<ShelfAccount?> find(String phone) async {
    final raw = await store.read('shelf_account_$phone');
    return raw == null || raw.isEmpty ? null : ShelfAccount.fromJson(jsonDecode(raw) as Map);
  }

  Future<void> save(ShelfAccount a) async {
    await store.write('shelf_account_${a.phone}', jsonEncode(a.toJson()));
    final all = await phones();
    if (!all.contains(a.phone)) await store.write('shelf_people', jsonEncode([...all, a.phone]));
  }

  Future<List<String>> phones() async {
    final raw = await store.read('shelf_people');
    return raw == null || raw.isEmpty ? [] : [for (final x in jsonDecode(raw) as List) '$x'];
  }

  Future<List<ShelfAccount>> all() async => [for (final p in await phones()) ?await find(p)];

  /// The person the phone opens for (the last one signed in).
  Future<ShelfAccount?> current() async {
    final p = await store.read('shelf_current');
    return p == null || p.isEmpty ? null : find(p);
  }

  Future<void> setCurrent(String phone) => store.write('shelf_current', phone);
}
