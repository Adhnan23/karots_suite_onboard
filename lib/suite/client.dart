import 'dart:convert';

import 'package:http/http.dart' as http;

import 'support_pin.dart';

class SuiteError implements Exception {
  SuiteError(this.status, this.code, this.message);
  final int status;
  final String code, message;
  @override
  String toString() => message;
}

class LoginInfo {
  LoginInfo(this.installId, this.shopName);
  final String installId, shopName;
}

class Me {
  Me(this.shopName, this.plugins, this.stockTakeEnabled);
  final String shopName;
  final List<String> plugins;
  final bool stockTakeEnabled;
}

/// One shop's /api/v1, signed in as its system user. JSON in and out as maps;
/// money stays a decimal string.
class SuiteClient {
  SuiteClient(String base, {http.Client? client})
    : base = base.endsWith('/') ? base.substring(0, base.length - 1) : base,
      _http = client ?? http.Client();
  final String base;
  final http.Client _http;
  String _cookie = '';
  static const systemPhone = '0000000001';
  static const devSystemPin = '2273';
  static const timeout = Duration(seconds: 60);

  Map<String, String> get _headers => {
    'X-Ks-Device': 'karots-suite-onboard',
    'Accept': 'application/json',
    if (_cookie.isNotEmpty) 'Cookie': _cookie,
  };

  Future<http.Response> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$base/api/v1$path').replace(queryParameters: query);
    final req = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    final set = res.headers['set-cookie'];
    if (set != null) {
      final m = RegExp(r'pos_token=([^;]*)').firstMatch(set);
      if (m != null) _cookie = 'pos_token=${m.group(1)}';
    }
    if (res.statusCode >= 300) {
      var code = 'HTTP_${res.statusCode}', msg = 'The shop answered ${res.statusCode}';
      try {
        final e = (jsonDecode(res.body) as Map)['error'] as Map;
        code = '${e['code']}';
        msg = '${e['message']}';
      } catch (_) {}
      throw SuiteError(res.statusCode, code, msg);
    }
    return res;
  }

  Future<dynamic> _json(String method, String path, {Object? body, Map<String, String>? query}) async {
    final res = await _send(method, path, body: body, query: query);
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) => _json('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _json('POST', path, body: body ?? {});
  Future<dynamic> put(String path, [Object? body]) => _json('PUT', path, body: body ?? {});

  // ---- who and sign-in ----

  Future<LoginInfo> loginInfo() async {
    final m = await get('/auth/login-info') as Map;
    return LoginInfo('${m['installId'] ?? ''}', '${m['shopName'] ?? ''}');
  }

  /// Tries this hour's PIN, then the last hour's (a clock at the hour's edge),
  /// then the Suite's public dev fallback 2273 (a dev or test build with no seed;
  /// a shop build never takes it).
  Future<void> signIn(String secret, String installId, {DateTime? now}) async {
    SuiteError? last;
    for (final pin in [...supportPinsNow(secret, installId, now ?? DateTime.now()), devSystemPin]) {
      try {
        await post('/auth/login', {'phone': systemPhone, 'pin': pin, 'deviceLabel': 'Karots Suite Onboard'});
        return;
      } on SuiteError catch (e) {
        if (e.status != 401 && e.status != 422) rethrow;
        last = e;
      }
    }
    throw last ?? SuiteError(401, 'UNAUTHORIZED', 'Sign-in refused');
  }

  Future<Me> me() async {
    final m = await get('/me') as Map;
    return Me('${m['shopName'] ?? ''}', [for (final p in (m['plugins'] as List? ?? [])) '$p'], m['stockTakeEnabled'] == true);
  }

  // ---- whole-shop reads ----

  Future<String> productsCsv({required bool customFields}) async => utf8.decode(
    (await _send('GET', '/admin/products/export', query: {'format': 'csv', 'ids': '1', if (customFields) 'extras': 'productplus'})).bodyBytes,
  );
  Future<String> suppliersCsv() async => utf8.decode((await _send('GET', '/admin/suppliers/export', query: {'format': 'csv'})).bodyBytes);
  Future<Map<int, List<Map>>> allPacks() async {
    final m = await get('/admin/products/packs') as Map;
    return {
      for (final e in m.entries) int.parse('${e.key}'): [for (final k in e.value as List) k as Map],
    };
  }

  Future<List> categories() async => await get('/admin/categories') as List;
  Future<List> units() async => await get('/admin/units') as List;

  /// The shop's suppliers as {id, name} for pickers.
  Future<List> supplierOptions() async => await get('/admin/supplier-options') as List;
  Future<List> fields() async => await get('/x/productplus/fields') as List;
  Future<List> alternatives() async => await get('/x/alternatives') as List;
  Future<Map> aiSettings() async => await get('/x/aicatalog/settings') as Map;
  Future<Map> identify(Map ask) async => await post('/x/aicatalog/identify', ask) as Map;

  // ---- writes ----

  /// Settings → Stock-take on: intake (old stock) works only with it.
  Future<void> enableStockTake() async {
    final s = (await get('/admin/settings') as Map)['settings'] as Map; // the page wraps them
    if (s['stockTakeEnabled'] == true) return;
    await put('/admin/settings', {...s, 'stockTakeEnabled': true});
  }

  /// A new product and its first batch of old stock (no money).
  Future<Map> intakeCreate(Map product, {String quantity = '', String expiry = ''}) async =>
      await post('/admin/inventory/intake/create', {'product': product, 'quantity': quantity, 'expiry': expiry}) as Map;

  /// Another batch of old stock with its own expiry and prices.
  Future<Map> intakeRestock(
    int productId, {
    required String quantity,
    String expiry = '',
    String cost = '',
    String selling = '',
    String wholesale = '',
    int supplierId = 0,
  }) async => await post('/admin/inventory/intake/restock', {
    'productId': productId,
    'quantity': quantity,
    'expiry': expiry,
    'costPrice': cost,
    'sellingPrice': selling,
    'wholesalePrice': wholesale,
    'batchId': 0,
    'supplierId': supplierId,
    'scanned': '',
  }) as Map;

  Future<Map> product(int id) async => await get('/admin/products/$id') as Map;
  Future<Map> updateProduct(int id, Map body) async => await put('/admin/products/$id', body) as Map;
  Future<Map> createSupplier(Map body) async => await post('/admin/suppliers', body) as Map;

  /// Finds or makes a category path ("Medicine > Pain") level by level; its id.
  Future<int> categoryPath(String path) async {
    int parent = 0;
    for (final name in path.split('>').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      final r = await post('/admin/categories/quick', {'name': name, 'parentId': parent}) as Map;
      parent = (r['id'] as num).toInt();
    }
    return parent;
  }

  Future<Map> mergePreview(int from, int into) async => await get('/admin/products/$from/merge/$into') as Map;
  Future<void> merge(int from, int into, {String lotPrice = ''}) => post('/admin/products/$from/merge/$into', {'lotPrice': lotPrice});

  /// An Alternatives group with one tier of these products.
  Future<int> createAlternative(String name, String tier, List<int> productIds) async {
    final g = await post('/x/alternatives', {'name': name}) as Map;
    final gid = (g['id'] as num).toInt();
    final tiers = g['tiers'] as List? ?? [];
    num tid;
    if (tiers.isNotEmpty) {
      // A new group comes with its first tier, unnamed: name it.
      tid = (tiers.first as Map)['id'] as num;
      await put('/x/alternatives/tiers/${tid.toInt()}', {'name': tier, 'reorderLevel': 0});
    } else {
      final grp = await post('/x/alternatives/$gid/tiers', {'name': tier, 'reorderLevel': 0}) as Map; // answers with the group
      tid = ((grp['tiers'] as List).last as Map)['id'] as num;
    }
    for (final id in productIds) {
      await post('/x/alternatives/tiers/${tid.toInt()}/members', {'productId': id, 'move': true});
    }
    return gid;
  }
}
