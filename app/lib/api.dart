import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

/// Server xatosi / ошибка сервера. [code] — server kodi (masalan 'bad_key') yoki 'conn'.
class ApiError implements Exception {
  final int status;
  final String code;
  const ApiError(this.status, this.code);
  @override
  String toString() => 'ApiError($status, $code)';
}

class Api {
  String base;
  String? token;
  http.Client client;
  Api({this.base = kServerUrl, this.token, http.Client? client}) : client = client ?? http.Client();

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  String url(String path) => path.startsWith('http') ? path : '$base$path';

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() f, Duration timeout) async {
    http.Response r;
    try {
      r = await f().timeout(timeout);
    } on TimeoutException {
      throw const ApiError(0, 'conn');
    } catch (_) {
      throw const ApiError(0, 'conn');
    }
    Map<String, dynamic> body = {};
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map<String, dynamic>) body = d;
    } catch (_) {}
    if (r.statusCode >= 400) throw ApiError(r.statusCode, (body['error'] ?? 'http_${r.statusCode}').toString());
    return body;
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query, Duration timeout = const Duration(seconds: 15)}) {
    final u = Uri.parse(url(path)).replace(queryParameters: query == null || query.isEmpty ? null : query);
    return _send(() => client.get(u, headers: headers), timeout);
  }

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)]) {
    return _send(() => client.post(Uri.parse(url(path)), headers: headers, body: jsonEncode(body ?? {})), timeout);
  }
}
