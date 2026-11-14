import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../brand.dart';
import '../chat.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'audience.dart';
import 'directory.dart' show confirmSheet, showUserSheet;
import 'media.dart';

// ============================================================ yordamchilar / помощники
String channelTitle(AppState s, Json ch) => s.pick(ch, 'title');

/// Kanal belgisi / значок канала.
class ChannelIcon extends StatelessWidget {
  final Json ch;
  final double size;
  const ChannelIcon(this.ch, {super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final key = (ch['auto_key'] ?? '').toString();
    final parts = key.split(':');
    Widget tile(Color bg, IconData icon, {Color fg = kWhite}) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: bg, borderRadius: R.all(size * 0.3)),
          child: Icon(icon, color: fg, size: size * 0.52),
        );
    if (key == 'all') return tile(kViolet, Icons.campaign_rounded);
    if (key.startsWith('dd:') || key.startsWith('rd:')) return DirectionTile(parts.last, size: size);
    if (key.startsWith('school:')) return tile(const Color(0xFF0A84D6), Icons.school_rounded);
    if (key.startsWith('dt:')) return tile(const Color(0xFF00A89D), Icons.groups_rounded);
    if (key.startsWith('rt:')) return tile(kKengashBlue, Icons.account_balance_rounded);
    final icon = (ch['icon'] ?? '').toString();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: c.accentGradient, borderRadius: R.all(size * 0.3)),
      child: icon.isEmpty
          ? Icon(ch['mode'] == 'announce' ? Icons.campaign_rounded : Icons.forum_rounded, color: kWhite, size: size * 0.5)
          : Text(icon, style: TextStyle(fontSize: size * 0.48)),
    );
  }
}

String timeLabel(AppState s, num? ts, {bool full = false}) {
  if (ts == null || ts == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000);
  final now = DateTime.now();
  String two(int x) => x.toString().padLeft(2, '0');
  final hm = '${two(d.hour)}:${two(d.minute)}';
  if (!full && d.year == now.year && d.month == now.month && d.day == now.day) return hm;
  final months = s.lang == 'ru'
      ? ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек']
      : ['yan', 'fev', 'mar', 'apr', 'may', 'iyn', 'iyl', 'avg', 'sen', 'okt', 'noy', 'dek'];
  final date = '${d.day} ${months[d.month - 1]}';
  return full ? '$date, $hm' : date;
}

/// Faqat soat:daqiqa (sana ajratgichda) / только часы:минуты (дата — в разделителе).
String hourMinute(num? ts) {
  if (ts == null || ts == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String previewText(AppState s, Json? last) {
  if (last == null) return s.t('ch_empty');
  if (last['deleted'] == true) return s.t('msg_deleted');
  final kind = (last['kind'] ?? '').toString();
  final k = switch (kind) {
    'photo' => '📷 ${s.t('att_photo')}',
    'video' => '🎬 ${s.t('att_video')}',
    'voice' => '🎤 ${s.t('att_voice')}',
    'file' => '📎 ${s.t('att_file')}',
    _ => '',
  };
  final text = (last['text'] ?? '').toString().replaceAll('\n', ' ');
  final body = [if (k.isNotEmpty) k, if (text.isNotEmpty) text].join(' · ');
  final who = (last['user_name'] ?? '').toString();
  final name = last['user_id'] == s.me?['id'] ? s.t('you') : who.split(' ').first;
  return name.isEmpty ? body : '$name: $body';
}

// ============================================================ ro‘yxat / список
class ChannelsTab extends StatefulWidget {
  const ChannelsTab({super.key});

  @override
  State<ChannelsTab> createState() => _ChannelsTabState();
}

class _ChannelsTabState extends State<ChannelsTab> {
  String _q = '';

  @override
  void initState() {
    super.initState();
    final chat = AppScope.read(context).chat;
    if (chat.channels == null) chat.loadChannels();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return ListenableBuilder(
      listenable: s.chat,
      builder: (context, _) {
        final chat = s.chat;
        final all = chat.channels;
        final list =
            (all ?? []).where((ch) => _q.isEmpty || channelTitle(s, ch).toLowerCase().contains(_q.toLowerCase())).toList();
        return TabPage(
          title: s.t('tab_channels'),
          onRefresh: chat.loadChannels,
          trailing: chat.canCreate
              ? AppIconButton(Icons.add_rounded,
                  key: const ValueKey('new-channel'),
                  tooltip: s.t('ch_new'),
                  color: c.accentText,
                  onPressed: () => Navigator.of(context).push(AppRoute(builder: (_) => const CreateChannelScreen())))
              : null,
          children: [
            if ((all?.length ?? 0) > 6)
              AppTextField(hint: s.t('ch_search'), icon: Icons.search_rounded, onChanged: (v) => setState(() => _q = v.trim())),
            if (all == null && chat.error != null)
              EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: s.errText(ApiError(0, chat.error!)),
                  error: true,
                  actionLabel: s.t('retry'),
                  onAction: chat.loadChannels)
            else if (all == null)
              const SkeletonRows(count: 6)
            else if (list.isEmpty)
              EmptyState(icon: Icons.forum_rounded, title: s.t('ch_none'), message: s.t('ch_none_text'))
            else
              GroupList([for (final ch in list) _ChannelRow(ch)]),
            const SizedBox(height: S.navSpace - S.x6),
          ],
        );
      },
    );
  }
}

class _ChannelRow extends StatelessWidget {
  final Json ch;
  const _ChannelRow(this.ch);

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final unread = (ch['unread'] as num?)?.toInt() ?? 0;
    final muted = ch['muted'] == true;
    final last = (ch['last'] as Map?)?.cast<String, dynamic>();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('ch-${ch['auto_key'] ?? ch['title_uz']}'),
        onTap: () => openChannel(context, ch['id'] as String),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
          child: Row(children: [
            ChannelIcon(ch, size: 48),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (ch['mode'] == 'announce') ...[
                    Icon(Icons.campaign_rounded, size: 15, color: c.text3),
                    const SizedBox(width: 3),
                  ],
                  Expanded(
                    child: Text(channelTitle(s, ch),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.headline.copyWith(color: c.text)),
                  ),
                  const SizedBox(width: S.x2),
                  Text(timeLabel(s, last?['created_at'] as num?), style: AppType.caption.copyWith(color: c.text3)),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(
                    child: Text(previewText(s, last),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.subhead.copyWith(color: c.text2)),
                  ),
                  if (muted) Icon(Icons.notifications_off_rounded, size: 15, color: c.text3),
                  if (unread > 0) ...[
                    const SizedBox(width: S.x2),
                    Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: muted ? c.text3 : c.accent, borderRadius: R.all(R.pill)),
                      child: Text(unread > 99 ? '99+' : '$unread',
                          textAlign: TextAlign.center, style: AppType.caption.copyWith(color: kWhite)),
                    ),
                  ],
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

void openChannel(BuildContext context, String id) {
  Navigator.of(context).push(AppRoute(builder: (_) => ChannelScreen(channelId: id)));
}

// ============================================================ suhbat / чат
class ChannelScreen extends StatefulWidget {
  final String channelId;
  const ChannelScreen({super.key, required this.channelId});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Json? _info;
  Json? _reply;
  Json? _editing;
  String? _error;
  bool _loadingOlder = false;
  late final ChatStore _chat;

  String get cid => widget.channelId;

  @override
  void initState() {
    super.initState();
    _chat = AppScope.read(context).chat;
    _chat.openChannel = cid;
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    if (_chat.openChannel == cid) _chat.openChannel = null;
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final info = await s.api.get('/api/channels/$cid');
      await _chat.loadMessages(cid);
      if (!mounted) return;
      setState(() {
        _info = info;
        _error = null;
      });
      _chat.markRead(cid);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = s.errText(e));
    }
  }

  void _onScroll() {
    if (_loadingOlder || _chat.hasMore[cid] != true) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _loadingOlder = true;
      _chat.loadMessages(cid, older: true).whenComplete(() => _loadingOlder = false);
    }
  }

  Json get _ch => _chat.channel(cid) ?? _info ?? const {};

  Future<void> _send() async {
    final s = AppScope.read(context);
    final text = _text.text.trim();
    if (text.isEmpty) return;
    if (_editing != null) {
      final m = _editing!;
      setState(() => _editing = null);
      _text.clear();
      try {
        await _chat.edit(m['id'] as String, text);
        m['text'] = text;
        m['edited'] = true;
        setState(() {});
      } on ApiError catch (e) {
        s.toast(s.errText(e));
      }
      return;
    }
    final reply = _reply;
    _text.clear();
    setState(() => _reply = null);
    await _chat.send(cid, s.me!, text: text, reply: reply);
  }

  Future<void> _attach() async {
    final s = AppScope.read(context);
    final c = s.c;
    final choice = await showAppSheet<String>(context, builder: (ctx) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('att_send'), style: AppType.title3.copyWith(color: c.text)),
        const SizedBox(height: S.x4),
        GroupList([
          GroupRow(
              key: const ValueKey('att-photo'),
              icon: Icons.photo_rounded,
              color: const Color(0xFF0A84D6),
              title: s.t('att_photo'),
              onTap: () => Navigator.of(ctx).pop('photo')),
          if (!kIsWeb)
            GroupRow(
                icon: Icons.photo_camera_rounded,
                color: const Color(0xFF34C759),
                title: s.t('att_camera'),
                onTap: () => Navigator.of(ctx).pop('camera')),
          GroupRow(
              icon: Icons.videocam_rounded,
              color: const Color(0xFFFF9F0A),
              title: '${s.t('att_video')} · ${s.t('max')} 50 MB',
              onTap: () => Navigator.of(ctx).pop('video')),
          GroupRow(
              icon: Icons.attach_file_rounded,
              color: const Color(0xFF8E8E93),
              title: '${s.t('att_file')} · ${s.t('max')} 20 MB',
              onTap: () => Navigator.of(ctx).pop('file')),
        ]),
      ]);
    });
    if (choice == null || !mounted) return;
    final caption = _text.text.trim();
    try {
      switch (choice) {
        case 'photo' || 'camera':
          final f = await ImagePicker().pickImage(
              source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
              maxWidth: 2400,
              maxHeight: 2400,
              imageQuality: 90);
          if (f == null) return;
          final bytes = await f.readAsBytes();
          _text.clear();
          await _chat.send(cid, s.me!,
              text: caption, pendingKind: 'photo', upload: () async => [await _chat.uploadPhoto(cid, bytes)]);
        case 'video':
          final f = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 10));
          if (f == null) return;
          final size = await f.length();
          if (size > 50 * 1024 * 1024) {
            s.toast(s.t('err_too_large'));
            return;
          }
          final bytes = await f.readAsBytes();
          final name = f.name.isEmpty ? 'video.mp4' : f.name;
          _text.clear();
          await _chat.send(cid, s.me!,
              text: caption,
              pendingKind: 'video',
              upload: () async => [await _chat.uploadFile(cid, 'video', name, f.mimeType ?? mimeOf(name), bytes)]);
        case 'file':
          final r = await FilePicker.platform.pickFiles(withData: true);
          final f = r?.files.single;
          if (f == null || f.bytes == null) return;
          if (f.size > 20 * 1024 * 1024) {
            s.toast(s.t('err_too_large'));
            return;
          }
          final bytes = f.bytes!;
          _text.clear();
          await _chat.send(cid, s.me!,
              text: caption,
              pendingKind: 'file',
              upload: () async => [await _chat.uploadFile(cid, 'file', f.name, mimeOf(f.name), bytes)]);
      }
    } catch (_) {
      s.toast(s.t('err_photo'));
    }
  }

  Future<void> _voice(VoiceClip v) async {
    final s = AppScope.read(context);
    await _chat.send(cid, s.me!,
        pendingKind: 'voice',
        upload: () async => [await _chat.uploadFile(cid, 'voice', v.name, v.mime, v.bytes, duration: v.seconds)]);
  }

  Future<void> _actions(Json m) async {
    final s = AppScope.read(context);
    final c = s.c;
    final mine = (m['user'] as Map?)?['id'] == s.me?['id'];
    final ch = _ch;
    final mod = ch['is_mod'] == true;
    final canEdit = mine &&
        (m['text'] ?? '').toString().isNotEmpty &&
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - ((m['created_at'] as num?) ?? 0) < 15 * 60;
    HapticFeedback.mediumImpact();
    final a = await showAppSheet<String>(context, builder: (ctx) {
      Widget row(String id, IconData icon, Color color, String title) =>
          GroupRow(key: ValueKey('act-$id'), icon: icon, color: color, title: title, onTap: () => Navigator.of(ctx).pop(id));
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GroupList([
          if (ch['can_post'] == true) row('reply', Icons.reply_rounded, c.accent, s.t('reply')),
          if ((m['text'] ?? '').toString().isNotEmpty) row('copy', Icons.copy_rounded, const Color(0xFF0A84D6), s.t('copy')),
          if (canEdit) row('edit', Icons.edit_rounded, const Color(0xFFFF9F0A), s.t('edit')),
          if (mod) row('pin', Icons.push_pin_rounded, const Color(0xFF00A89D), s.t(ch['pinned'] == m['id'] ? 'unpin' : 'pin')),
          if (!mine) row('report', Icons.flag_rounded, const Color(0xFFFF9F0A), s.t('report')),
          if (mine || mod) row('delete', Icons.delete_rounded, const Color(0xFFFF3B30), s.t('delete')),
        ]),
      ]);
    });
    if (a == null || !mounted) return;
    try {
      switch (a) {
        case 'reply':
          setState(() {
            _reply = m;
            _editing = null;
          });
          _focus.requestFocus();
        case 'copy':
          s.copy((m['text'] ?? '').toString());
        case 'edit':
          setState(() {
            _editing = m;
            _reply = null;
            _text.text = (m['text'] ?? '').toString();
          });
          _focus.requestFocus();
        case 'pin':
          await _chat.pin(m['id'] as String, ch['pinned'] != m['id']);
          _load();
        case 'report':
          final reason = await _askReason();
          if (reason == null) return;
          await _chat.report(m['id'] as String, reason);
          s.toast(s.t('reported'), icon: Icons.flag_rounded);
        case 'delete':
          if (!mounted || !await confirmSheet(context, s.t('delete_msg_q'), s.t('delete'))) return;
          await _chat.delete(m['id'] as String);
          m['deleted'] = true;
          m['text'] = '';
          m['attachments'] = [];
          setState(() {});
      }
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  Future<String?> _askReason() {
    final s = AppScope.read(context);
    return showAppSheet<String>(context, builder: (ctx) {
      final c = AppScope.of(ctx).c;
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('report_title'), style: AppType.title3.copyWith(color: c.text)),
        const SizedBox(height: S.x1),
        Text(s.t('report_text'), style: AppType.subhead.copyWith(color: c.text2)),
        const SizedBox(height: S.x4),
        GroupList([
          for (final r in ['insult', 'inappropriate', 'spam', 'other'])
            GroupRow(
                key: ValueKey('reason-$r'),
                icon: Icons.flag_rounded,
                color: const Color(0xFFFF9F0A),
                title: s.t('reason_$r'),
                onTap: () => Navigator.of(ctx).pop(r)),
        ]),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return ListenableBuilder(
      listenable: _chat,
      builder: (context, _) {
        final ch = _ch;
        final list = _chat.messages[cid];
        final canPost = ch['can_post'] == true;
        final pinned = (_info?['pinned_message'] as Map?)?.cast<String, dynamic>();
        final members = (ch['members'] as num?)?.toInt() ?? 0;
        return GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Scaffold(
            backgroundColor: c.bg,
            body: SafeArea(
              bottom: false,
              child: Column(children: [
                // sarlavha / шапка
                Container(
                  padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x3, S.x2),
                  decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.hairline))),
                  child: Row(children: [
                    IconButton(
                        key: const ValueKey('back'),
                        tooltip: s.t('back'),
                        icon: Icon(Icons.chevron_left_rounded, size: 30, color: c.accentText),
                        onPressed: () => Navigator.of(context).maybePop()),
                    if (ch.isNotEmpty) ChannelIcon(ch, size: 38),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Pressable(
                        key: const ValueKey('ch-info'),
                        onTap: ch.isEmpty
                            ? null
                            : () => Navigator.of(context)
                                .push(AppRoute(builder: (_) => ChannelInfoScreen(channelId: cid)))
                                .then((_) => _load()),
                        scale: 0.99,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(ch.isEmpty ? '' : channelTitle(s, ch),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.headline.copyWith(color: c.text)),
                          Text(
                              '$members ${s.t('members_short')}${ch['mode'] == 'announce' ? ' · ${s.t('mode_announce_short')}' : ''}',
                              style: AppType.caption.copyWith(color: c.text2)),
                        ]),
                      ),
                    ),
                    if (ch['muted'] == true) Icon(Icons.notifications_off_rounded, color: c.text3, size: 20),
                  ]),
                ),
                if (pinned != null)
                  Material(
                    color: c.surfaceAlt,
                    child: InkWell(
                      onTap: () {},
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
                        child: Row(children: [
                          Icon(Icons.push_pin_rounded, size: 18, color: c.accentText),
                          const SizedBox(width: S.x2),
                          Expanded(
                            child: Text((pinned['text'] ?? '').toString().isEmpty ? s.t('att_file') : pinned['text'] as String,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.subhead.copyWith(color: c.text)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                Expanded(
                  child: _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(S.page),
                            child: EmptyState(
                                icon: Icons.wifi_off_rounded,
                                title: _error!,
                                error: true,
                                actionLabel: s.t('retry'),
                                onAction: _load),
                          ),
                        )
                      : list == null
                          ? const Padding(padding: EdgeInsets.all(S.page), child: SkeletonRows(count: 6))
                          : list.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(S.page),
                                    child: EmptyState(
                                        icon: Icons.waving_hand_rounded, title: s.t('ch_empty'), message: s.t('ch_first')),
                                  ),
                                )
                              : Align(
                                  alignment: Alignment.topCenter,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 820),
                                    child: ListView.builder(
                                      controller: _scroll,
                                      reverse: true,
                                      padding: const EdgeInsets.fromLTRB(S.x3, S.x3, S.x3, S.x3),
                                      itemCount: list.length,
                                      itemBuilder: (context, i) {
                                        final m = list[i];
                                        final older = i + 1 < list.length ? list[i + 1] : null;
                                        final newer = i > 0 ? list[i - 1] : null;
                                        return MessageBubble(
                                          key: ValueKey(m['id']),
                                          m: m,
                                          showDate: older == null || !_sameDay(older, m),
                                          first: older == null || !_grouped(older, m),
                                          last: newer == null || !_grouped(m, newer),
                                          announce: ch['mode'] == 'announce',
                                          onLong: m['pending'] == true || m['deleted'] == true ? null : () => _actions(m),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                ),
                if (canPost)
                  Composer(
                    controller: _text,
                    focus: _focus,
                    reply: _reply,
                    editing: _editing,
                    onCancel: () => setState(() {
                      _reply = null;
                      if (_editing != null) _text.clear();
                      _editing = null;
                    }),
                    onSend: _send,
                    onAttach: _attach,
                    onVoice: _voice,
                  )
                else if (ch.isNotEmpty)
                  _ReadOnlyBar(ch: ch),
              ]),
            ),
          ),
        );
      },
    );
  }

  bool _sameDay(Json a, Json b) {
    final x = DateTime.fromMillisecondsSinceEpoch(((a['created_at'] as num?) ?? 0).toInt() * 1000);
    final y = DateTime.fromMillisecondsSinceEpoch(((b['created_at'] as num?) ?? 0).toInt() * 1000);
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  bool _grouped(Json older, Json newer) =>
      (older['user'] as Map?)?['id'] == (newer['user'] as Map?)?['id'] &&
      ((newer['created_at'] as num? ?? 0) - (older['created_at'] as num? ?? 0)) < 300 &&
      _sameDay(older, newer);
}

class _ReadOnlyBar extends StatelessWidget {
  final Json ch;
  const _ReadOnlyBar({required this.ch});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final muted = ch['muted'] == true;
    return Container(
      padding: EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x3 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.hairline))),
      child: Row(children: [
        Icon(Icons.campaign_rounded, color: c.text3, size: 20),
        const SizedBox(width: S.x2),
        Expanded(child: Text(s.t('read_only'), style: AppType.subhead.copyWith(color: c.text2))),
        TextButton.icon(
          key: const ValueKey('mute-toggle'),
          onPressed: () => s.chat.setMuted(ch['id'] as String, !muted),
          icon: Icon(muted ? Icons.notifications_active_rounded : Icons.notifications_off_rounded, size: 18),
          label: Text(s.t(muted ? 'unmute' : 'mute')),
        ),
      ]),
    );
  }
}

// ============================================================ xabar pufakchasi / пузырь сообщения
class MessageBubble extends StatelessWidget {
  final Json m;
  final bool showDate, first, last, announce;
  final VoidCallback? onLong;
  const MessageBubble(
      {super.key,
      required this.m,
      this.showDate = false,
      this.first = true,
      this.last = true,
      this.announce = false,
      this.onLong});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final user = (m['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mine = user['id'] == s.me?['id'];
    final deleted = m['deleted'] == true;
    final text = (m['text'] ?? '').toString();
    final atts = [for (final a in (m['attachments'] as List? ?? [])) (a as Map).cast<String, dynamic>()];
    final reply = (m['reply'] as Map?)?.cast<String, dynamic>();
    final dir = user['direction'] as String?;
    final nameColor = dir == null ? c.accentText : (dir == 'lider' ? const Color(0xFFD99A00) : directionColor(dir));
    final fg = mine ? kWhite : c.text;
    final sub = mine ? Colors.white.withAlpha(0xBB) : c.text3;
    final r = Radius.circular(R.lg);
    final small = const Radius.circular(6);
    final onlyMedia = text.isEmpty && atts.length == 1 && (atts.first['kind'] == 'photo' || atts.first['kind'] == 'video');

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: (MediaQuery.sizeOf(context).width * 0.78).clamp(220, 520)),
      padding: onlyMedia ? const EdgeInsets.all(3) : const EdgeInsets.fromLTRB(S.x3, S.x2, S.x3, S.x2),
      decoration: BoxDecoration(
        gradient: mine && !deleted ? c.accentGradient : null,
        color: mine && !deleted ? null : (deleted ? c.surfaceAlt : c.surface),
        borderRadius: BorderRadius.only(
          topLeft: !mine && !first ? small : r,
          topRight: mine && !first ? small : r,
          bottomLeft: !mine && !last ? small : (mine ? r : small),
          bottomRight: mine && !last ? small : (mine ? small : r),
        ),
        border: mine || deleted ? null : Border.all(color: c.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (!mine && first && !onlyMedia)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text((user['name'] ?? '').toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: nameColor, fontWeight: w7)),
          ),
        if (reply != null && !deleted)
          Container(
            margin: const EdgeInsets.only(bottom: S.x1, top: 2),
            padding: const EdgeInsets.fromLTRB(S.x2, 4, S.x2, 4),
            decoration: BoxDecoration(
              color: mine ? Colors.white.withAlpha(0x26) : c.accentSoft,
              borderRadius: R.all(R.xs),
              border: Border(left: BorderSide(color: mine ? kWhite : c.accent, width: 3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(((reply['user'] as Map?)?['name'] ?? '').toString(),
                  maxLines: 1, style: AppType.caption.copyWith(color: mine ? kWhite : c.accentText)),
              Text(
                  reply['deleted'] == true
                      ? s.t('msg_deleted')
                      : (reply['text'] ?? '').toString().isEmpty
                          ? previewText(s, {'kind': reply['kind'], 'text': ''})
                          : reply['text'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.footnote.copyWith(color: mine ? Colors.white.withAlpha(0xDD) : c.text2)),
            ]),
          ),
        if (deleted)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.block_rounded, size: 15, color: c.text3),
            const SizedBox(width: 4),
            Text(s.t('msg_deleted'), style: AppType.subhead.copyWith(color: c.text3, fontStyle: FontStyle.italic)),
          ]),
        for (final a in atts)
          Padding(
            padding: EdgeInsets.only(bottom: text.isEmpty ? 0 : S.x1),
            child: AttachmentView(a: a, mine: mine, pending: m['pending'] == true),
          ),
        if (text.isNotEmpty)
          Text.rich(linkify(text, AppType.body.copyWith(color: fg, height: 1.4), mine ? kWhite : c.accentText, s)),
        Padding(
          padding: onlyMedia ? const EdgeInsets.fromLTRB(S.x2, 2, S.x2, 2) : const EdgeInsets.only(top: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (m['edited'] == true) Text('${s.t('edited')} · ', style: AppType.caption.copyWith(color: sub, fontWeight: w6)),
            if (announce && m['seen'] != null) ...[
              Icon(Icons.visibility_rounded, size: 12, color: sub),
              Text(' ${m['seen']} · ', style: AppType.caption.copyWith(color: sub, fontWeight: w6)),
            ],
            Text(hourMinute(m['created_at'] as num?), style: AppType.caption.copyWith(color: sub, fontWeight: w6)),
            if (m['pending'] == true && m['failed'] != true) ...[
              const SizedBox(width: 4),
              Icon(Icons.schedule_rounded, size: 12, color: sub),
            ],
          ]),
        ),
      ]),
    );

    final row = Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!mine)
          SizedBox(
            width: 38,
            child: last
                ? GestureDetector(
                    onTap: user['id'] == null ? null : () => _openUser(context, user['id'] as String),
                    child: AppAvatar(url: s.photoUrl(user['photo']), name: (user['name'] ?? '').toString(), size: 32),
                  )
                : null,
          ),
        Flexible(
          child: GestureDetector(
            onLongPress: onLong,
            onSecondaryTap: onLong,
            child: Opacity(opacity: m['pending'] == true && m['failed'] != true ? 0.7 : 1, child: bubble),
          ),
        ),
      ],
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (showDate)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x3),
          child: Center(
            child: AppPill(timeLabel(s, m['created_at'] as num?, full: true).split(',').first, small: true),
          ),
        ),
      Padding(padding: EdgeInsets.only(top: first ? S.x2 : 2), child: row),
      if (m['failed'] == true)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: m['retry'] as VoidCallback?,
            icon: Icon(Icons.error_rounded, size: 16, color: c.danger),
            label: Text('${s.errText(ApiError(0, (m['error'] ?? 'conn').toString()))} · ${s.t('retry')}',
                style: AppType.caption.copyWith(color: c.danger)),
          ),
        ),
    ]);
  }

  Future<void> _openUser(BuildContext context, String id) async {
    final s = AppScope.read(context);
    try {
      final u = await s.api.get('/api/users/$id');
      if (context.mounted) showUserSheet(context, u);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }
}

/// Havolalarni bosiladigan qilish / кликабельные ссылки.
TextSpan linkify(String text, TextStyle style, Color link, AppState s) {
  final re = RegExp(r'(https?://[^\s]+|@[A-Za-z0-9_]{4,32})');
  final spans = <InlineSpan>[];
  var i = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
    final v = m.group(0)!;
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        onTap: () => v.startsWith('@') ? s.openTelegram(v) : s.openUrl(v),
        child: Text(v, style: style.copyWith(color: link, decoration: TextDecoration.underline, decorationColor: link)),
      ),
    ));
    i = m.end;
  }
  if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
  return TextSpan(style: style, children: spans);
}

// ============================================================ yozish maydoni / поле ввода
class Composer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final Json? reply;
  final Json? editing;
  final VoidCallback onCancel;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final Future<void> Function(VoiceClip) onVoice;
  const Composer(
      {super.key,
      required this.controller,
      required this.focus,
      this.reply,
      this.editing,
      required this.onCancel,
      required this.onSend,
      required this.onAttach,
      required this.onVoice});

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final hasText = widget.controller.text.trim().isNotEmpty;
    final ctx = widget.editing ?? widget.reply;
    return Container(
      padding: EdgeInsets.fromLTRB(S.x2, S.x2, S.x2, S.x2 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.hairline))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (ctx != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x2, 0, 0, S.x2),
            child: Row(children: [
              Icon(widget.editing != null ? Icons.edit_rounded : Icons.reply_rounded, color: c.accentText, size: 20),
              const SizedBox(width: S.x2),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.editing != null ? s.t('editing') : ((ctx['user'] as Map?)?['name'] ?? '').toString(),
                      style: AppType.caption.copyWith(color: c.accentText)),
                  Text((ctx['text'] ?? '').toString().isEmpty ? s.t('att_file') : ctx['text'] as String,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2)),
                ]),
              ),
              IconButton(
                  key: const ValueKey('cancel-ctx'),
                  icon: Icon(Icons.close_rounded, color: c.text3),
                  tooltip: s.t('cancel'),
                  onPressed: widget.onCancel),
            ]),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: VoiceRecorderBar(
            onDone: widget.onVoice,
            idle: (startRecording) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (widget.editing == null)
                IconButton(
                  key: const ValueKey('attach'),
                  tooltip: s.t('att_send'),
                  icon: Icon(Icons.add_circle_rounded, color: c.accent, size: 30),
                  onPressed: widget.onAttach,
                ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): () {
                      if (hasText) widget.onSend();
                    },
                    const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: R.all(22),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: S.x4),
                    child: TextField(
                      key: const ValueKey('composer'),
                      controller: widget.controller,
                      focusNode: widget.focus,
                      minLines: 1,
                      maxLines: 6,
                      maxLength: 4000,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppType.body.copyWith(color: c.text),
                      decoration: InputDecoration(
                        hintText: s.t('msg_hint'),
                        hintStyle: AppType.body.copyWith(color: c.text3),
                        border: InputBorder.none,
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: S.x1),
              if (hasText || widget.editing != null)
                _RoundBtn(
                    key: const ValueKey('send'),
                    icon: widget.editing != null ? Icons.check_rounded : Icons.arrow_upward_rounded,
                    tip: s.t('send'),
                    onTap: widget.onSend)
              else
                _RoundBtn(key: const ValueKey('mic'), icon: Icons.mic_rounded, tip: s.t('att_voice'), onTap: startRecording),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final Color? color;
  const _RoundBtn({super.key, required this.icon, required this.tip, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Tooltip(
      message: tip,
      child: Pressable(
        onTap: onTap,
        semanticLabel: tip,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(gradient: color == null ? c.accentGradient : null, color: color, shape: BoxShape.circle),
          child: Icon(icon, color: kWhite, size: 24),
        ),
      ),
    );
  }
}

// ============================================================ kanal haqida / о канале
class ChannelInfoScreen extends StatefulWidget {
  final String channelId;
  const ChannelInfoScreen({super.key, required this.channelId});

  @override
  State<ChannelInfoScreen> createState() => _ChannelInfoScreenState();
}

class _ChannelInfoScreenState extends State<ChannelInfoScreen> {
  Json? _ch;
  List<Json>? _members;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final ch = await s.api.get('/api/channels/${widget.channelId}');
      final m = await s.api.get('/api/channels/${widget.channelId}/members');
      if (mounted) {
        setState(() {
          _ch = ch;
          _members = [for (final x in m['members'] as List) (x as Map).cast<String, dynamic>()];
        });
      }
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  Future<void> _edit() async {
    final s = AppScope.read(context);
    final ch = _ch!;
    final title = TextEditingController(text: s.pick(ch, 'title'));
    final desc = TextEditingController(text: (ch['description'] ?? '').toString());
    var mode = ch['mode'] as String;
    await showAppSheet<void>(context, builder: (ctx) {
      final c = AppScope.of(ctx).c;
      return StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.t('ch_edit'), style: AppType.title3.copyWith(color: c.text)),
            const SizedBox(height: S.x4),
            AppTextField(controller: title, label: s.t('ch_name'), icon: Icons.title_rounded, maxLength: 60),
            const SizedBox(height: S.x3),
            AppTextField(controller: desc, label: s.t('ch_desc'), icon: Icons.notes_rounded, maxLength: 300, maxLines: 3),
            const SizedBox(height: S.x4),
            ModePicker(value: mode, onChanged: (v) => set(() => mode = v)),
            const SizedBox(height: S.x4),
            AppButton(s.t('save'), expand: true, onPressed: () async {
              try {
                await s.api.post('/api/channels/${widget.channelId}',
                    {'title': title.text.trim(), 'description': desc.text.trim(), 'mode': mode});
                if (ctx.mounted) Navigator.of(ctx).pop();
                s.chat.loadChannels();
                _load();
              } on ApiError catch (e) {
                s.toast(s.errText(e));
              }
            }),
          ]),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final ch = _ch;
    if (ch == null) return const PageShell(child: TabPage(children: [SkeletonRows(count: 6)]));
    final custom = ch['kind'] == 'custom';
    final mod = ch['is_mod'] == true;
    final owner = ch['role'] == 'owner';
    return PageShell(
      child: TabPage(
        onRefresh: _load,
        children: [
          Column(children: [
            ChannelIcon(ch, size: 84),
            const SizedBox(height: S.x3),
            Text(channelTitle(s, ch), textAlign: TextAlign.center, style: AppType.title2.copyWith(color: c.text)),
            const SizedBox(height: S.x1),
            Text('${ch['members']} ${s.t('members_short')} · ${s.t(ch['mode'] == 'announce' ? 'mode_announce' : 'mode_group')}',
                style: AppType.subhead.copyWith(color: c.text2)),
            if ((ch['description'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: S.x3),
              Text(ch['description'] as String, textAlign: TextAlign.center, style: AppType.body.copyWith(color: c.text)),
            ],
            if (!custom) ...[
              const SizedBox(height: S.x3),
              AppPill(s.t('ch_auto'), icon: Icons.autorenew_rounded, tone: Tone.accent, small: true),
            ],
          ]),
          GroupList([
            if (ch['member'] == true)
              GroupRow(
                icon: Icons.notifications_off_rounded,
                color: const Color(0xFF8E8E93),
                title: s.t('mute'),
                trailing: Switch.adaptive(
                    value: ch['muted'] == true,
                    activeTrackColor: c.accent,
                    onChanged: (v) async {
                      await s.chat.setMuted(widget.channelId, v);
                      _load();
                    }),
              ),
            if (custom && mod)
              GroupRow(
                  key: const ValueKey('ch-edit'),
                  icon: Icons.edit_rounded,
                  color: const Color(0xFFFF9F0A),
                  title: s.t('ch_edit'),
                  onTap: _edit),
            if (custom && mod)
              GroupRow(
                  key: const ValueKey('ch-add'),
                  icon: Icons.person_add_alt_1_rounded,
                  color: c.accent,
                  title: s.t('ch_add_members'),
                  onTap: () async {
                    final pick = await Navigator.of(context)
                        .push<AudiencePick>(AppRoute(builder: (_) => AudienceScreen(title: s.t('ch_add_members'))));
                    if (pick == null) return;
                    try {
                      final r = await s.api.post('/api/channels/${widget.channelId}/members/add', pick.toJson());
                      s.toast('${s.t('added')}: ${r['added']}', icon: Icons.check_circle_rounded);
                      _load();
                    } on ApiError catch (e) {
                      s.toast(s.errText(e));
                    }
                  }),
          ]),
          SectionHeader('${s.t('members')} · ${_members?.length ?? 0}'),
          if (_members == null)
            const SkeletonRows(count: 4)
          else
            GroupList([
              for (final u in _members!)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => showUserSheet(context, u),
                    onLongPress: !custom || !mod || u['channel_role'] == 'owner'
                        ? null
                        : () async {
                            if (!await confirmSheet(context, '${u['name']} — ${s.t('ch_remove_q')}', s.t('ch_remove'))) return;
                            try {
                              await s.api.post('/api/channels/${widget.channelId}/members/remove', {'user_id': u['id']});
                              _load();
                            } on ApiError catch (e) {
                              s.toast(s.errText(e));
                            }
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
                      child: Row(children: [
                        AppAvatar(url: s.photoUrl(u['photo']), name: (u['name'] ?? '').toString(), size: 40),
                        const SizedBox(width: S.x3),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((u['name'] ?? '').toString(),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong.copyWith(color: c.text)),
                            Text(s.seatLine(u),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2)),
                          ]),
                        ),
                        if (u['channel_role'] == 'owner' || u['channel_role'] == 'admin')
                          AppPill(s.t(u['channel_role'] == 'owner' ? 'role_owner' : 'role_ch_admin'),
                              tone: Tone.accent, small: true),
                      ]),
                    ),
                  ),
                ),
            ]),
          if (custom && mod) Text(s.t('ch_remove_hint'), style: AppType.footnote.copyWith(color: c.text3)),
          if (custom && ch['member'] == true && !owner)
            AppButton(s.t('ch_leave'), kind: BtnKind.danger, icon: Icons.logout_rounded, expand: true, onPressed: () async {
              if (!await confirmSheet(context, s.t('ch_leave_q'), s.t('ch_leave'))) return;
              try {
                await s.api.post('/api/channels/${widget.channelId}/leave');
                await s.chat.loadChannels();
                if (context.mounted)
                  Navigator.of(context)
                    ..pop()
                    ..pop();
              } on ApiError catch (e) {
                s.toast(s.errText(e));
              }
            }),
          if (custom && (owner || s.isAdmin))
            AppButton(s.t('ch_delete'),
                key: const ValueKey('ch-delete'),
                kind: BtnKind.danger,
                icon: Icons.delete_forever_rounded,
                expand: true, onPressed: () async {
              if (!await confirmSheet(context, s.t('ch_delete_q'), s.t('ch_delete'))) return;
              try {
                await s.api.post('/api/channels/${widget.channelId}/delete');
                await s.chat.loadChannels();
                if (context.mounted)
                  Navigator.of(context)
                    ..pop()
                    ..pop();
              } on ApiError catch (e) {
                s.toast(s.errText(e));
              }
            }),
        ],
      ),
    );
  }
}

/// «Hamma yozadi» yoki «Faqat men yozaman» / «Пишут все» или «Пишу только я».
class ModePicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String> onChanged;
  const ModePicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    Widget card(String v, IconData icon, String title, String text) {
      final on = value == v;
      return Expanded(
        child: Pressable(
          key: ValueKey('mode-$v'),
          onTap: () => onChanged(v),
          scale: 0.98,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(S.x4),
            decoration: BoxDecoration(
              color: on ? c.accentSoft : c.surface,
              borderRadius: R.all(R.lg),
              border: Border.all(color: on ? c.accent : c.hairlineStrong, width: on ? 1.8 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: on ? c.accentText : c.text2),
                const Spacer(),
                Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: on ? c.accent : c.text3, size: 20),
              ]),
              const SizedBox(height: S.x2),
              Text(title, style: AppType.headline.copyWith(color: c.text)),
              const SizedBox(height: 2),
              Text(text, style: AppType.footnote.copyWith(color: c.text2)),
            ]),
          ),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        card('group', Icons.forum_rounded, s.t('mode_group'), s.t('mode_group_text')),
        const SizedBox(width: S.x3),
        card('announce', Icons.campaign_rounded, s.t('mode_announce'), s.t('mode_announce_text')),
      ]),
    );
  }
}

// ============================================================ yangi kanal / новый канал
class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({super.key});

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  String _icon = '';
  String? _mode;
  AudiencePick? _audience;
  bool _busy = false;
  String? _error;

  static const icons = ['📢', '🏆', '📚', '💡', '⚽', '🎭', '🌱', '📷', '🤝', '⭐', '🎉', '📝'];

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final s = AppScope.read(context);
    if (_title.text.trim().length < 2) {
      setState(() => _error = s.t('err_bad_title'));
      return;
    }
    if (_mode == null) {
      setState(() => _error = s.t('err_pick_mode'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await s.api.post('/api/channels', {
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'icon': _icon,
        'mode': _mode,
        ...?_audience?.toJson(),
      });
      await s.chat.loadChannels();
      if (!mounted) return;
      Navigator.of(context).pop();
      s.toast('${s.t('ch_created')} · ${r['members']} ${s.t('members_short')}', icon: Icons.check_circle_rounded);
      openChannel(context, r['id'] as String);
    } on ApiError catch (e) {
      setState(() => _error = s.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return PageShell(
      child: TabPage(
        title: s.t('ch_new'),
        subtitle: s.t('ch_new_sub'),
        children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppTextField(
                  key: const ValueKey('ch-title'),
                  controller: _title,
                  label: s.t('ch_name'),
                  hint: s.t('ch_name_hint'),
                  icon: Icons.title_rounded,
                  maxLength: 60),
              const SizedBox(height: S.x3),
              AppTextField(controller: _desc, label: s.t('ch_desc'), icon: Icons.notes_rounded, maxLength: 300, maxLines: 3),
              const SizedBox(height: S.x3),
              Text(s.t('ch_icon'), style: AppType.footnote.copyWith(color: c.text2)),
              const SizedBox(height: S.x2),
              Wrap(spacing: S.x2, runSpacing: S.x2, children: [
                for (final e in icons)
                  Pressable(
                    onTap: () => setState(() => _icon = _icon == e ? '' : e),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _icon == e ? c.accentSoft : c.surfaceAlt,
                        borderRadius: R.all(R.sm),
                        border: Border.all(color: _icon == e ? c.accent : Colors.transparent, width: 1.6),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ]),
            ]),
          ),
          SectionHeader(s.t('ch_mode_q')),
          ModePicker(value: _mode, onChanged: (v) => setState(() => _mode = v)),
          SectionHeader(s.t('members')),
          AppCard(
            key: const ValueKey('ch-audience'),
            onTap: () async {
              final pick = await Navigator.of(context)
                  .push<AudiencePick>(AppRoute(builder: (_) => AudienceScreen(title: s.t('members'), initial: _audience)));
              if (pick != null) setState(() => _audience = pick);
            },
            child: Row(children: [
              IconTile(Icons.groups_rounded, size: 44, bg: c.accentSoft, color: c.accentText),
              const SizedBox(width: S.x3),
              Expanded(
                child: Text(_audience == null || _audience!.isEmpty ? s.t('aud_pick') : _audience!.label(s),
                    style: AppType.bodyStrong.copyWith(color: _audience == null ? c.text2 : c.text)),
              ),
              Icon(Icons.chevron_right_rounded, color: c.text3),
            ]),
          ),
          if (_error != null) Text(_error!, style: AppType.footnote.copyWith(color: c.danger)),
          AppButton(s.t('ch_create'),
              key: const ValueKey('ch-create'),
              icon: Icons.check_rounded,
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : _create),
        ],
      ),
    );
  }
}
