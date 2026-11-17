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

  // ---- tez ochilish: oxirgi javoblar telefonda saqlanadi / мгновенный старт: последние ответы хранятся на телефоне
  /// Faqat asosiy ro‘yxatlar (kichik) / только главные списки (небольшие).
  static const cacheable = {'/api/today', '/api/channels', '/api/tasks', '/api/events'};
  String? Function(String key)? cacheRead;
  void Function(String key, String value)? cacheWrite;

  static String cacheKey(String path, Map<String, String>? query) {
    if (query == null || query.isEmpty) return path;
    final keys = query.keys.toList()..sort();
    return '$path?${keys.map((k) => '$k=${query[k]}').join('&')}';
  }

  /// Oxirgi saqlangan javob (internet kutmasdan ko‘rsatish uchun) yoki null.
  /// Последний сохранённый ответ (чтобы показать, не дожидаясь сети) или null.
  Map<String, dynamic>? peek(String path, {Map<String, String>? query}) {
    final raw = cacheRead?.call(cacheKey(path, query));
    if (raw == null) return null;
    try {
      final d = jsonDecode(raw);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

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

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query, Duration timeout = const Duration(seconds: 15)}) async {
    final u = Uri.parse(url(path)).replace(queryParameters: query == null || query.isEmpty ? null : query);
    final body = await _send(() => client.get(u, headers: headers), timeout);
    if (cacheWrite != null && cacheable.contains(path)) {
      try {
        cacheWrite!(cacheKey(path, query), jsonEncode(body));
      } catch (_) {}
    }
    return body;
  }

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)]) {
    return _send(() => client.post(Uri.parse(url(path)), headers: headers, body: jsonEncode(body ?? {})), timeout);
  }
}
