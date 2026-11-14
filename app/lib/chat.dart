import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'state.dart' show Json;

/// Kanallar holati va jonli ulanish / состояние каналов и живое соединение.
class ChatStore extends ChangeNotifier {
  final Api api;
  final bool testMode;
  ChatStore(this.api, {this.testMode = false});

  List<Json>? channels;
  bool canCreate = false;
  String? error;

  /// Ochiq kanal → xabarlar (yangisi birinchi) / открытый канал → сообщения (новые первыми).
  final Map<String, List<Json>> messages = {};
  final Map<String, bool> hasMore = {};
  String? openChannel;
  String? myId;

  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  Timer? _retry;
  Timer? _ping;
  Timer? _poll;
  int _backoff = 2;
  bool _wanted = false;
  bool connected = false;

  int get unreadTotal =>
      (channels ?? []).where((c) => c['muted'] != true).fold(0, (a, c) => a + ((c['unread'] as num?)?.toInt() ?? 0));

  Json? channel(String id) {
    for (final c in channels ?? const <Json>[]) {
      if (c['id'] == id) return c;
    }
    return null;
  }

  // ---------------------------------------------------------------- yuklash / загрузка
  Future<void> loadChannels() async {
    try {
      final r = await api.get('/api/channels');
      channels = [for (final c in r['channels'] as List) (c as Map).cast<String, dynamic>()];
      canCreate = r['can_create'] == true;
      error = null;
    } on ApiError catch (e) {
      error = e.code;
    }
    notifyListeners();
  }

  Future<void> loadMessages(String cid, {bool older = false}) async {
    final list = messages[cid];
    final before = older && list != null && list.isNotEmpty ? (list.last['seq'] as num).toInt() : 0;
    final r = await api.get('/api/channels/$cid/messages', query: {if (before > 0) 'before': '$before', 'limit': '50'});
    final got = [for (final m in r['messages'] as List) (m as Map).cast<String, dynamic>()];
    if (older && list != null) {
      list.addAll(got);
    } else {
      // vaqtincha (yuborilmoqda) xabarlar saqlanadi / временные (отправляются) сохраняются
      final pending = (list ?? []).where((m) => m['pending'] == true).toList();
      messages[cid] = [...pending, ...got];
    }
    hasMore[cid] = r['has_more'] == true;
    notifyListeners();
  }

  Future<void> markRead(String cid) async {
    final list = messages[cid];
    final c = channel(cid);
    if (c == null) return;
    final seq = list == null || list.isEmpty ? (c['seq'] as num?)?.toInt() ?? 0 : _maxSeq(list);
    if ((c['unread'] as num? ?? 0) > 0) {
      c['unread'] = 0;
      notifyListeners();
    }
    try {
      await api.post('/api/channels/$cid/read', {'seq': seq});
    } catch (_) {}
  }

  int _maxSeq(List<Json> list) {
    var m = 0;
    for (final x in list) {
      final s = (x['seq'] as num?)?.toInt() ?? 0;
      if (s > m) m = s;
    }
    return m;
  }

  // ---------------------------------------------------------------- yuborish / отправка
  /// Matn va/yoki fayllar bilan xabar. [upload] — fayllarni yuklaydi (vaqtincha pufakcha ko‘rinadi).
  /// Сообщение с текстом и/или файлами. [upload] загружает файлы (видна временная «пузырька»).
  Future<void> send(String cid, Json me,
      {String text = '', Json? reply, Future<List<Json>> Function()? upload, String pendingKind = ''}) async {
    final tmp = <String, dynamic>{
      'id': 'tmp-${DateTime.now().microsecondsSinceEpoch}',
      'pending': true,
      'text': text,
      'user': {'id': me['id'], 'name': me['name'], 'photo': me['photo'], 'direction': me['direction']},
      'attachments': pendingKind.isEmpty
          ? []
          : [
              {'kind': pendingKind, 'pending': true}
            ],
      'reply': reply == null ? null : {'id': reply['id'], 'text': reply['text'], 'user': reply['user']},
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'seq': 1 << 50,
    };
    messages.putIfAbsent(cid, () => []).insert(0, tmp);
    notifyListeners();
    try {
      final atts = upload == null ? <Json>[] : await upload();
      final m = await api.post('/api/channels/$cid/messages', {'text': text, 'reply_to': reply?['id'], 'attachments': atts},
          const Duration(seconds: 30));
      final list = messages[cid]!;
      list.remove(tmp);
      if (!list.any((x) => x['id'] == m['id'])) list.insert(0, m);
      _touchChannel(cid, m, mine: true);
    } catch (e) {
      tmp['failed'] = true;
      tmp['error'] = e is ApiError ? e.code : 'conn';
      tmp['retry'] = () {
        messages[cid]?.remove(tmp);
        send(cid, me, text: text, reply: reply, upload: upload, pendingKind: pendingKind);
      };
    }
    notifyListeners();
  }

  /// Surat: server orqali (EXIF o‘chiriladi) / фото: через сервер (EXIF удаляется).
  Future<Json> uploadPhoto(String cid, Uint8List bytes) async {
    return api.post('/api/channels/$cid/photo', {'data': base64Encode(bytes)}, const Duration(seconds: 90));
  }

  /// Fayl/ovoz/video: imzolangan havolaga to‘g‘ridan-to‘g‘ri / файл/голос/видео: напрямую по подписанной ссылке.
  Future<Json> uploadFile(String cid, String kind, String name, String mime, Uint8List bytes, {double? duration}) async {
    final r = await api.post('/api/channels/$cid/upload',
        {'kind': kind, 'name': name, 'size': bytes.length, 'mime': mime, if (duration != null) 'duration': duration});
    final res = await api.client
        .put(Uri.parse(r['upload_url'] as String), headers: {'Content-Type': mime, 'x-upsert': 'false'}, body: bytes)
        .timeout(const Duration(minutes: 5));
    if (res.statusCode >= 300) throw ApiError(res.statusCode, 'upload_failed');
    return {
      'kind': kind,
      'path': r['path'],
      'name': name,
      'mime': mime,
      'size': bytes.length,
      if (duration != null) 'duration': duration,
    };
  }

  Future<void> edit(String mid, String text) => api.post('/api/messages/$mid/edit', {'text': text});
  Future<void> delete(String mid) => api.post('/api/messages/$mid/delete');
  Future<void> pin(String mid, bool pin) => api.post('/api/messages/$mid/pin', {'pin': pin});
  Future<void> report(String mid, String reason) => api.post('/api/messages/$mid/report', {'reason': reason});

  Future<void> setMuted(String cid, bool muted) async {
    final c = channel(cid);
    if (c != null) c['muted'] = muted;
    notifyListeners();
    await api.post('/api/channels/$cid/mute', {'muted': muted});
  }

  void _touchChannel(String cid, Json m, {bool mine = false}) {
    final c = channel(cid);
    if (c == null) {
      loadChannels();
      return;
    }
    final atts = (m['attachments'] as List?) ?? [];
    c['last'] = {
      'text': m['text'],
      'deleted': m['deleted'] == true,
      'kind': atts.isEmpty ? '' : (atts.first as Map)['kind'],
      'user_name': (m['user'] as Map?)?['name'] ?? '',
      'user_id': (m['user'] as Map?)?['id'],
      'created_at': m['created_at'],
    };
    c['last_msg_at'] = m['created_at'];
    c['seq'] = m['seq'];
    if (!mine && openChannel != cid) c['unread'] = ((c['unread'] as num?)?.toInt() ?? 0) + 1;
    channels!.sort((a, b) => ((b['last_msg_at'] as num?) ?? 0).compareTo((a['last_msg_at'] as num?) ?? 0));
  }

  // ---------------------------------------------------------------- jonli / живое соединение
  void start() {
    _wanted = true;
    if (testMode) return;
    _connect();
    // Zaxira: ulanish bo‘lmasa har 20 soniyada yangilash / запасной вариант: обновление каждые 20 с без соединения
    _poll ??= Timer.periodic(const Duration(seconds: 20), (_) {
      if (!connected && _wanted) {
        loadChannels();
        final open = openChannel;
        if (open != null) loadMessages(open).catchError((_) {});
      }
    });
  }

  void stop() {
    _wanted = false;
    _retry?.cancel();
    _ping?.cancel();
    _poll?.cancel();
    _poll = null;
    _sub?.cancel();
    _ws?.sink.close();
    _ws = null;
    connected = false;
    channels = null;
    messages.clear();
  }

  void _connect() {
    final token = api.token;
    if (!_wanted || token == null) return;
    final base = api.base.replaceFirst(RegExp(r'^http'), 'ws');
    try {
      final ws = WebSocketChannel.connect(Uri.parse('$base/api/ws?token=$token'));
      _ws = ws;
      _sub = ws.stream.listen(_onEvent, onDone: _lost, onError: (_) => _lost(), cancelOnError: true);
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _ws?.sink.add('ping');
        } catch (_) {}
      });
    } catch (_) {
      _lost();
    }
  }

  void _lost() {
    connected = false;
    _ping?.cancel();
    if (!_wanted) return;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _backoff), _connect);
    _backoff = (_backoff * 2).clamp(2, 60);
  }

  void _onEvent(dynamic raw) {
    Json ev;
    try {
      ev = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (ev['type']) {
      case 'hello':
        connected = true;
        _backoff = 2;
        loadChannels();
        final open = openChannel;
        if (open != null) loadMessages(open).catchError((_) {});
      case 'message.new':
        final cid = ev['channel_id'] as String;
        final m = (ev['message'] as Map).cast<String, dynamic>();
        final list = messages[cid];
        if (list != null && !list.any((x) => x['id'] == m['id'])) {
          // imzolangan havolalar uchun qayta yuklash / перезагрузка ради подписанных ссылок
          if ((m['attachments'] as List?)?.isNotEmpty == true) {
            loadMessages(cid).catchError((_) {});
          } else {
            list.insert(0, m);
          }
        }
        _touchChannel(cid, m, mine: (m['user'] as Map?)?['id'] == myId);
        if (openChannel == cid) markRead(cid);
        notifyListeners();
      case 'message.update':
        final cid = ev['channel_id'] as String;
        final m = (ev['message'] as Map).cast<String, dynamic>();
        final list = messages[cid];
        if (list != null) {
          final i = list.indexWhere((x) => x['id'] == m['id']);
          if (i >= 0) {
            final old = list[i];
            // fayl havolalari saqlanadi / ссылки на файлы сохраняются
            if (m['deleted'] != true) m['attachments'] = old['attachments'];
            list[i] = m;
          }
        }
        notifyListeners();
      case 'channel.update':
      case 'channels.changed':
        loadChannels();
    }
  }
}

/// Fayl turini nomidan aniqlash / тип файла по имени.
String mimeOf(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt' => 'text/plain',
    'zip' => 'application/zip',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    _ => 'application/octet-stream',
  };
}

String fileSize(num bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Fayl baytlari (yozib olingan ovoz va h.k.) / байты файла.
Future<Uint8List> fetchBytes(String url) async => (await http.get(Uri.parse(url))).bodyBytes;
