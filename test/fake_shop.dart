import 'dart:convert';
import 'dart:io';

/// A tiny fake shop: records requests, answers by path.
class FakeShop {
  late HttpServer server;
  final calls = <(String, String, Map<String, String>, String)>[];
  Map<String, Object? Function(HttpRequest, String)> routes = {};
  String get url => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((r) async {
      final body = await utf8.decodeStream(r);
      final h = <String, String>{};
      r.headers.forEach((k, v) => h[k] = v.join(','));
      calls.add((r.method, r.uri.path, h, body));
      final fn = routes['${r.method} ${r.uri.path}'];
      if (fn == null) {
        r.response.statusCode = 404;
        r.response.write(
          jsonEncode({
            'error': {'code': 'NOT_FOUND', 'message': 'no route'},
          }),
        );
      } else {
        final out = fn(r, body);
        if (out is String) {
          r.response.write(out);
        } else {
          r.response.headers.contentType = ContentType.json;
          r.response.write(jsonEncode(out));
        }
      }
      await r.response.close();
    });
  }
}
