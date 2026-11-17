import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../sound.dart';
import 'audience.dart';
import 'channels.dart' show PresetTile, channelPresets;
import 'directory.dart' show confirmSheet;
import 'manage.dart' show planActions;
import 'media.dart' show PhotoViewer, VoiceClip, VoicePlayer, VoiceRecorderBar;

// ============================================================ vaqt / время
String two(int x) => x.toString().padLeft(2, '0');

DateTime fromTs(num ts) => DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000);
int toTs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

/// "Bugun 18:00", "Ertaga 09:00", "21 noy, 14:00"
String whenLabel(AppState s, num ts) {
  final d = fromTs(ts);
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = day.difference(today).inDays;
  final hm = '${two(d.hour)}:${two(d.minute)}';
  if (diff == 0) return '${s.t('today_w')} $hm';
  if (diff == 1) return '${s.t('tomorrow')} $hm';
  if (diff == -1) return '${s.t('yesterday')} $hm';
  final months = s.lang == 'ru'
      ? ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек']
      : ['yan', 'fev', 'mar', 'apr', 'may', 'iyn', 'iyl', 'avg', 'sen', 'okt', 'noy', 'dek'];
  return '${d.day} ${months[d.month - 1]}, $hm';
}

/// Muddat tanlash: tezkor tugmalar + «Boshqa sana» / выбор срока: быстрые кнопки + «Другая дата».
class WhenPicker extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool future;
  const WhenPicker({super.key, required this.value, required this.onChanged, this.future = true});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final now = DateTime.now();
    DateTime at(int days, int hour) => DateTime(now.year, now.month, now.day + days, hour);
    final quick = <(String, DateTime)>[
      if (now.hour < 17) (s.t('q_today_18'), at(0, 18)),
      (s.t('q_tomorrow'), at(1, 18)),
      (s.t('q_3days'), at(3, 18)),
      (s.t('q_week'), at(7, 18)),
    ];
    Widget chip(String label, bool on, VoidCallback onTap, {Key? key}) => Pressable(
          key: key,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
            decoration: BoxDecoration(
              color: on ? c.accentSoft : c.surface,
              borderRadius: R.all(R.pill),
              border: Border.all(color: on ? c.accent : c.hairlineStrong, width: on ? 1.6 : 1),
            ),
            child: Text(label, style: AppType.subhead.copyWith(color: on ? c.accentText : c.text)),
          ),
        );
    final isQuick = quick.any((q) => q.$2 == value);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: S.x2, runSpacing: S.x2, children: [
        for (final (i, q) in quick.indexed) chip(q.$1, value == q.$2, () => onChanged(q.$2), key: ValueKey('when-$i')),
        chip(s.t('q_other'), value != null && !isQuick, () async {
          final d = await showDatePicker(
            context: context,
            initialDate: value ?? at(1, 18),
            firstDate: DateTime(now.year, now.month, now.day),
            lastDate: now.add(const Duration(days: 365)),
          );
          if (d == null || !context.mounted) return;
          final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(value ?? at(1, 18)));
          if (t == null) return;
          onChanged(DateTime(d.year, d.month, d.day, t.hour, t.minute));
        }, key: const ValueKey('when-other')),
      ]),
      if (value != null) ...[
        const SizedBox(height: S.x2),
        Row(children: [
          Icon(Icons.schedule_rounded, size: 18, color: c.accentText),
          const SizedBox(width: S.x2),
          Text(whenLabel(s, toTs(value!)), style: AppType.callout.copyWith(color: c.accentText)),
        ]),
      ],
    ]);
  }
}

/// Holat belgisi / метка статуса.
Widget statusPill(AppState s, String status, {bool overdue = false}) {
  if (overdue && (status == 'new' || status == 'returned')) {
    return AppPill(s.t('st_overdue'), tone: Tone.danger, small: true, icon: Icons.error_rounded);
  }
  return switch (status) {
    'submitted' => AppPill(s.t('st_submitted'), tone: Tone.accent, small: true, icon: Icons.hourglass_top_rounded),
    'accepted' => AppPill(s.t('st_accepted'), tone: Tone.yellow, small: true, icon: Icons.check_circle_rounded),
    'returned' => AppPill(s.t('st_returned'), tone: Tone.danger, small: true, icon: Icons.undo_rounded),
    _ => AppPill(s.t('st_new'), small: true),
  };
}

// ============================================================ ro‘yxat / список
class TasksTab extends StatefulWidget {
  const TasksTab({super.key});

  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> {
  String _box = 'mine';
  List<Json>? _list;
  bool _canGive = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context);
    _canGive = s.canGive;
    if (s.tasksBox == 'given' && _canGive) _box = 'given';
    final cached = s.api.peek('/api/tasks', query: {'box': _box}); // darhol / сразу
    if (cached != null) _apply(cached);
    _load();
  }

  void _apply(Json r) {
    _list = [for (final x in r['tasks'] as List) (x as Map).cast<String, dynamic>()];
    if (r['can_give'] != null) _canGive = r['can_give'] == true;
    _error = null;
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/tasks', query: {'box': _box});
      if (!mounted) return;
      setState(() => _apply(r));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return TabPage(
      title: s.t('tab_tasks'),
      onRefresh: _load,
      trailing: _canGive
          ? AppIconButton(Icons.add_rounded, key: const ValueKey('new-task'), tooltip: s.t('task_new'), color: c.accentText,
              onPressed: () async {
              final ok = await Navigator.of(context).push<bool>(AppRoute(builder: (_) => const CreateTaskScreen()));
              if (ok == true) {
                setState(() => _box = 'given');
                _load();
              }
            })
          : null,
      children: [
        if (_canGive)
          Segmented<String>(
            values: const ['mine', 'given'],
            labels: [s.t('box_mine'), s.t('box_given')],
            value: _box,
            onChanged: (v) {
              setState(() {
                _box = v;
                _list = null;
              });
              s.tasksBox = v;
              _load();
            },
          ),
        if (_error != null)
          EmptyState(icon: Icons.wifi_off_rounded, title: _error!, error: true, actionLabel: s.t('retry'), onAction: _load)
        else if (_list == null)
          const SkeletonRows(count: 4)
        else if (_list!.isEmpty)
          EmptyState(
              icon: Icons.task_alt_rounded,
              title: s.t(_box == 'mine' ? 'tasks_none' : 'tasks_none_given'),
              message: s.t(_box == 'mine' ? 'tasks_none_text' : 'tasks_none_given_text'))
        else
          for (final t in _list!) TaskCard(task: t, given: _box == 'given', onChanged: _load),
        const SizedBox(height: S.navSpace - S.x6),
      ],
    );
  }
}

class TaskCard extends StatelessWidget {
  final Json task;
  final bool given;
  final VoidCallback? onChanged;
  const TaskCard({super.key, required this.task, this.given = false, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final my = (task['my'] as Map?)?.cast<String, dynamic>();
    final overdue = task['overdue'] == true;
    final total = (task['total'] as num?)?.toInt() ?? 0;
    final done = (task['done'] as num?)?.toInt() ?? 0;
    final toReview = ((task['counts'] as Map?)?['submitted'] as num?)?.toInt() ?? 0;
    return AppCard(
      key: ValueKey('task-${task['id']}'),
      onTap: () async {
        await Navigator.of(context).push(AppRoute(builder: (_) => TaskScreen(taskId: task['id'] as String)));
        onChanged?.call();
      },
      onLongPress: task['is_giver'] == true || s.isAdmin
          ? () => planActions(context, task, event: false, onChanged: onChanged)
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(task['title'] as String, style: AppType.headline.copyWith(color: c.text))),
          const SizedBox(width: S.x2),
          if (!given && my != null) statusPill(s, my['status'] as String, overdue: overdue),
          if (given && toReview > 0) AppPill('$toReview ${s.t('to_check')}', tone: Tone.accent, small: true),
        ]),
        const SizedBox(height: S.x2),
        Row(children: [
          Icon(Icons.schedule_rounded, size: 16, color: overdue ? c.danger : c.text3),
          const SizedBox(width: 4),
          Text(whenLabel(s, task['deadline'] as num), style: AppType.footnote.copyWith(color: overdue ? c.danger : c.text2)),
          const Spacer(),
          if (!given) Text(((task['by'] as Map?)?['name'] ?? '').toString(), style: AppType.footnote.copyWith(color: c.text3)),
          if (given) Text('$done / $total', style: AppType.footnote.copyWith(color: c.text2, fontWeight: w7)),
        ]),
        if (given) ...[
          const SizedBox(height: S.x2),
          AppProgress(total == 0 ? 0 : done / total, height: 6, gradient: c.accentGradient),
        ],
      ]),
    );
  }
}

// ============================================================ vazifa / задача
class TaskScreen extends StatefulWidget {
  final String taskId;
  const TaskScreen({super.key, required this.taskId});

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  Json? _t;
  String? _error;
  final _comment = TextEditingController();
  final List<(String, String)> _photos = []; // (yo‘l / путь, '')
  final List<Uint8List> _previews = [];
  (String, double)? _voice; // ovozli hisobot (yo‘l, soniya) / голосовой отчёт (путь, секунды)
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final t = await s.api.get('/api/tasks/${widget.taskId}');
      if (mounted) {
        setState(() {
          _t = t;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = s.errText(e));
    }
  }

  Future<void> _addPhoto() async {
    final s = AppScope.read(context);
    final f = await ImagePicker()
        .pickImage(source: kIsWeb ? ImageSource.gallery : ImageSource.camera, maxWidth: 2400, maxHeight: 2400, imageQuality: 88);
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await f.readAsBytes();
      final r = await s.api.post('/api/tasks/${widget.taskId}/photo', {'data': base64Encode(bytes)}, const Duration(seconds: 90));
      setState(() {
        _photos.add((r['path'] as String, ''));
        _previews.add(bytes);
      });
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ovoz yozildi → darhol yuklanadi / голос записан → сразу загружается.
  Future<void> _addVoice(VoiceClip v) async {
    final s = AppScope.read(context);
    setState(() => _busy = true);
    try {
      final r = await s.api.post('/api/tasks/${widget.taskId}/voice', {'size': v.bytes.length, 'mime': v.mime, 'duration': v.seconds});
      final res = await s.api.client
          .put(Uri.parse(r['upload_url'] as String), headers: {'Content-Type': v.mime, 'x-upsert': 'false'}, body: v.bytes)
          .timeout(const Duration(minutes: 3));
      if (res.statusCode >= 300) throw ApiError(res.statusCode, 'upload_failed');
      if (mounted) setState(() => _voice = (r['path'] as String, v.seconds));
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    } catch (_) {
      s.toast(s.t('err_conn'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final s = AppScope.read(context);
    final t = _t!;
    if (t['photo_required'] == true && _photos.isEmpty) {
      s.toast(s.t('err_photo_required'));
      return;
    }
    setState(() => _busy = true);
    try {
      await s.api.post('/api/tasks/${widget.taskId}/submit', {
        'comment': _comment.text.trim(),
        'photos': [for (final p in _photos) p.$1],
        if (_voice != null) 'voice': _voice!.$1,
        if (_voice != null) 'voice_sec': _voice!.$2,
      });
      Sfx.success();
      s.toast(s.t('task_sent'), icon: Icons.check_circle_rounded);
      _photos.clear();
      _previews.clear();
      _voice = null;
      await _load();
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final t = _t;
    if (t == null) {
      return PageShell(
        child: TabPage(children: [
          if (_error != null)
            EmptyState(icon: Icons.wifi_off_rounded, title: _error!, error: true)
          else
            const SkeletonRows(count: 5)
        ]),
      );
    }
    final my = (t['my'] as Map?)?.cast<String, dynamic>();
    final people = [for (final x in (t['people'] as List? ?? [])) (x as Map).cast<String, dynamic>()];
    final overdue = t['overdue'] == true;
    final canSubmit = my != null && my['status'] != 'accepted';
    final total = (t['total'] as num).toInt();
    final done = (t['done'] as num).toInt();
    return PageShell(
      child: TabPage(
        title: t['title'] as String,
        onRefresh: _load,
        children: [
          AppCard(
            kind: CardKind.inset,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.schedule_rounded, color: overdue ? c.danger : c.accentText),
                const SizedBox(width: S.x2),
                Expanded(
                  child: Text('${s.t('deadline')}: ${whenLabel(s, t['deadline'] as num)}',
                      style: AppType.callout.copyWith(color: overdue ? c.danger : c.text)),
                ),
                if (my != null) statusPill(s, my['status'] as String, overdue: overdue),
              ]),
              const SizedBox(height: S.x2),
              Text('${s.t('from')}: ${((t['by'] as Map?)?['name'] ?? '')}', style: AppType.footnote.copyWith(color: c.text2)),
              if ((t['description'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: S.x3),
                SelectableText(t['description'] as String, style: AppType.body.copyWith(color: c.text)),
              ],
              if (t['photo_required'] == true) ...[
                const SizedBox(height: S.x3),
                Row(children: [
                  Icon(Icons.photo_camera_rounded, size: 18, color: c.text3),
                  const SizedBox(width: S.x2),
                  Text(s.t('photo_needed'), style: AppType.footnote.copyWith(color: c.text2)),
                ]),
              ],
            ]),
          ),
          // ---- bajaruvchi / исполнитель
          if (my != null) ...[
            if (my['status'] == 'returned' && (my['review_note'] ?? '').toString().isNotEmpty)
              AppCard(
                kind: CardKind.tinted,
                tint: c.dangerSoft,
                borderColor: c.danger.withAlpha(0x44),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.undo_rounded, color: c.danger),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text('${s.t('returned_note')}: ${my['review_note']}', style: AppType.subhead.copyWith(color: c.text)),
                  ),
                ]),
              ),
            if (my['status'] == 'submitted' || my['status'] == 'accepted') ...[
              SectionHeader(s.t('my_report')),
              _ReportView(
                  comment: my['comment'] as String? ?? '',
                  urls: (my['photo_urls'] as List? ?? []).cast<String>(),
                  voiceUrl: (my['voice_url'] ?? '').toString(),
                  voiceSec: (my['voice_sec'] as num?)?.toInt() ?? 0),
            ],
            if (canSubmit) ...[
              SectionHeader(my['status'] == 'submitted' ? s.t('report_again') : s.t('report_send')),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: S.x2, runSpacing: S.x2, children: [
                    for (final (i, p) in _previews.indexed)
                      Stack(children: [
                        ClipRRect(borderRadius: R.all(R.sm), child: Image.memory(p, width: 76, height: 76, fit: BoxFit.cover)),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _photos.removeAt(i);
                              _previews.removeAt(i);
                            }),
                            child: Container(
                              decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded, color: kWhite, size: 18),
                            ),
                          ),
                        ),
                      ]),
                    if (_photos.length < 6)
                      Pressable(
                        key: const ValueKey('add-photo'),
                        onTap: _busy ? null : _addPhoto,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                              color: c.accentSoft,
                              borderRadius: R.all(R.sm),
                              border: Border.all(color: c.accent.withAlpha(0x55))),
                          child: _busy
                              ? Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: c.accent))
                              : Icon(Icons.add_a_photo_rounded, color: c.accentText),
                        ),
                      ),
                  ]),
                  const SizedBox(height: S.x3),
                  // Yozish o‘rniga gapirish: mikrofonni bosing → «15 o‘quvchi keldi» / вместо текста — голосом
                  if (_voice != null)
                    Row(children: [
                      Expanded(child: VoicePlayer(key: const ValueKey('report-voice'), url: '', seconds: _voice!.$2, mine: true)),
                      IconButton(
                          key: const ValueKey('report-voice-remove'),
                          tooltip: s.t('delete'),
                          icon: Icon(Icons.close_rounded, color: c.text3),
                          onPressed: () => setState(() => _voice = null)),
                    ])
                  else
                    VoiceRecorderBar(
                      onDone: _addVoice,
                      idle: (start) => AppButton(s.t('report_voice'),
                          key: const ValueKey('report-mic'),
                          kind: BtnKind.secondary,
                          icon: Icons.mic_rounded,
                          height: 44,
                          expand: true,
                          onPressed: _busy ? null : start),
                    ),
                  const SizedBox(height: S.x3),
                  AppTextField(
                      key: const ValueKey('report-comment'),
                      controller: _comment,
                      hint: s.t('report_comment'),
                      icon: Icons.notes_rounded,
                      maxLines: 4,
                      maxLength: 1000),
                  const SizedBox(height: S.x3),
                  AppButton(s.t('task_done_btn'),
                      key: const ValueKey('task-submit'),
                      icon: Icons.check_rounded,
                      expand: true,
                      loading: _busy,
                      onPressed: _busy ? null : _submit),
                ]),
              ),
            ],
          ],
          // ---- beruvchi / выдавший
          if (t['can_review'] == true) ...[
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text(s.t('progress'), style: AppType.headline.copyWith(color: c.text)),
                  const Spacer(),
                  Text('$done / $total', style: AppType.number.copyWith(color: c.accentText)),
                ]),
                const SizedBox(height: S.x3),
                AppProgress(total == 0 ? 0 : done / total, gradient: c.accentGradient),
              ]),
            ),
            SectionHeader(s.t('people')),
            GroupList([
              for (final p in people)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('person-${(p['user'] as Map)['id']}'),
                    onTap: p['status'] == 'new' && !(overdue && p['can_rate'] == true) ? null : () => _openReport(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
                      child: Row(children: [
                        AppAvatar(
                            url: s.photoUrl((p['user'] as Map)['photo']),
                            name: ((p['user'] as Map)['name'] ?? '').toString(),
                            size: 38),
                        const SizedBox(width: S.x3),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(((p['user'] as Map)['name'] ?? '').toString(),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong.copyWith(color: c.text)),
                            Text(s.placeLine(((p['user'] as Map)['place'] as Map?)?.cast<String, dynamic>()),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2)),
                          ]),
                        ),
                        if ((p['points'] ?? 0) != 0) ...[
                          PointsBadge(p['points'] as int),
                          const SizedBox(width: S.x2),
                        ],
                        statusPill(s, p['status'] as String, overdue: overdue),
                      ]),
                    ),
                  ),
                ),
            ]),
          ],
          if (t['is_giver'] == true || s.isAdmin)
            AppButton(s.t('task_delete'), kind: BtnKind.danger, icon: Icons.delete_rounded, expand: true, onPressed: () async {
              if (!await confirmSheet(context, s.t('task_delete_q'), s.t('delete'))) return;
              try {
                await s.api.post('/api/tasks/${widget.taskId}/delete');
                if (context.mounted) Navigator.of(context).pop();
              } on ApiError catch (e) {
                s.toast(s.errText(e));
              }
            }),
        ],
      ),
    );
  }

  Future<void> _openReport(Json p) async {
    final s = AppScope.read(context);
    final user = (p['user'] as Map).cast<String, dynamic>();
    final note = TextEditingController();
    var returning = false; // «Qaytarish» bosilgandagina izoh maydoni / поле заметки только после «Вернуть»
    await showAppSheet<void>(context, builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      final c = AppScope.of(ctx).c;
      Future<void> act(String action) async {
        if (action == 'return' && note.text.trim().isEmpty) {
          s.toast(s.t('err_note_required'));
          return;
        }
        try {
          await s.api
              .post('/api/tasks/${widget.taskId}/review', {'user_id': user['id'], 'action': action, 'note': note.text.trim()});
          // Qabul qilish = +1 ball (standart); keyin o‘zgartirish mumkin / Принять = +1 балл по умолчанию
          if (action == 'accept' && p['can_rate'] == true && ((p['points'] as int?) ?? 0) == 0) {
            await s.api.post('/api/tasks/${widget.taskId}/rate', {'user_id': user['id'], 'value': 1});
          }
          if (action == 'accept') Sfx.success();
          if (ctx.mounted) Navigator.of(ctx).pop();
          _load();
        } on ApiError catch (e) {
          s.toast(s.errText(e));
        }
      }

      final submitted = p['status'] == 'submitted';
      return SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            AppAvatar(url: s.photoUrl(user['photo']), name: (user['name'] ?? '').toString(), size: 44),
            const SizedBox(width: S.x3),
            Expanded(child: Text((user['name'] ?? '').toString(), style: AppType.title3.copyWith(color: c.text))),
            statusPill(s, p['status'] as String),
          ]),
          const SizedBox(height: S.x4),
          _ReportView(comment: p['comment'] as String? ?? '', urls: (p['photo_urls'] as List? ?? []).cast<String>(),
              voiceUrl: (p['voice_url'] ?? '').toString(), voiceSec: (p['voice_sec'] as num?)?.toInt() ?? 0),
          // Baho — faqat ko‘rib chiqilgandan keyin (qabul qilish o‘zi +1 beradi) / оценка — только после проверки
          if (p['can_rate'] == true && !submitted) ...[
            const SizedBox(height: S.x4),
            RateRow(
              value: (p['points'] as int?) ?? 0,
              onChanged: (v) async {
                await s.api.post('/api/tasks/${widget.taskId}/rate', {'user_id': user['id'], 'value': v});
                _load();
              },
            ),
          ],
          if (submitted && !returning) ...[
            const SizedBox(height: S.x4),
            AppButton(s.t('accept'),
                key: const ValueKey('review-accept'), icon: Icons.check_rounded, expand: true, onPressed: () => act('accept')),
            const SizedBox(height: S.x2),
            AppButton(s.t('return_btn'),
                key: const ValueKey('review-return-open'),
                kind: BtnKind.ghost,
                icon: Icons.undo_rounded,
                expand: true,
                onPressed: () => setSheet(() => returning = true)),
          ],
          if (submitted && returning) ...[
            const SizedBox(height: S.x4),
            AppTextField(
                key: const ValueKey('review-note'),
                controller: note,
                hint: s.t('return_hint'),
                icon: Icons.edit_note_rounded,
                maxLength: 500),
            const SizedBox(height: S.x2),
            AppButton(s.t('return_btn'),
                key: const ValueKey('review-return'), icon: Icons.undo_rounded, expand: true, onPressed: () => act('return')),
          ],
        ]),
      );
    }));
  }
}

class _ReportView extends StatelessWidget {
  final String comment;
  final List<String> urls;
  final String voiceUrl;
  final int voiceSec;
  const _ReportView({required this.comment, required this.urls, this.voiceUrl = '', this.voiceSec = 0});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return AppCard(
      kind: CardKind.inset,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (urls.isNotEmpty)
          Wrap(spacing: S.x2, runSpacing: S.x2, children: [
            for (final u in urls)
              GestureDetector(
                onTap:
                    u.isEmpty ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewer(url: u))),
                child: ClipRRect(
                  borderRadius: R.all(R.sm),
                  child: u.isEmpty
                      ? Container(width: 90, height: 90, color: c.surfaceAlt)
                      : Image.network(u,
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                          cacheWidth: (90 * MediaQuery.devicePixelRatioOf(context)).round(),
                          errorBuilder: (_, __, ___) => Container(width: 90, height: 90, color: c.surfaceAlt)),
                ),
              ),
          ]),
        if (voiceUrl.isNotEmpty) ...[
          if (urls.isNotEmpty) const SizedBox(height: S.x3),
          VoicePlayer(key: const ValueKey('report-voice-play'), url: voiceUrl, seconds: voiceSec.toDouble()),
        ],
        if (comment.isNotEmpty) ...[
          if (urls.isNotEmpty || voiceUrl.isNotEmpty) const SizedBox(height: S.x3),
          Text(comment, style: AppType.body.copyWith(color: c.text)),
        ],
        if (comment.isEmpty && urls.isEmpty && voiceUrl.isEmpty) Text(s.t('report_empty'), style: AppType.subhead.copyWith(color: c.text3)),
      ]),
    );
  }
}

// ============================================================ yangi vazifa / новая задача
class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  DateTime? _deadline;
  bool _photo = true;
  String? _preset;
  AudiencePick? _audience;
  bool _busy = false;
  String? _error;
  late final presets = channelPresets(AppScope.read(context), below: true);

  @override
  void initState() {
    super.initState();
    // Aqlli standartlar: oxirgi tanlangan guruh, 3 kundan keyin 18:00, rasm sozlamasi — oxirgidek.
    // Умные значения: последняя группа, срок — через 3 дня в 18:00, фото — как в прошлый раз.
    final s = AppScope.read(context);
    final last = s.lastUsed('task_preset');
    final p = presets.where((x) => x.$1 == last).firstOrNull ?? presets.firstOrNull;
    if (p != null) {
      _preset = p.$1;
      _audience = p.$3;
    }
    final now = DateTime.now();
    _deadline = DateTime(now.year, now.month, now.day + 3, 18);
    _photo = s.lastUsed('task_photo') != 'false';
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final s = AppScope.read(context);
    if (_title.text.trim().length < 2) return setState(() => _error = s.t('err_task_title'));
    if (_deadline == null) return setState(() => _error = s.t('err_pick_deadline'));
    if (_audience == null || _audience!.isEmpty) return setState(() => _error = s.t('aud_pick'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await s.api.post('/api/tasks', {
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'deadline': toTs(_deadline!),
        'photo_required': _photo,
        ..._audience!.toJson(),
      });
      if (_preset != null && _preset != 'custom') s.rememberUsed('task_preset', _preset!);
      s.rememberUsed('task_photo', '$_photo');
      s.toast('${s.t('task_created')} · ${r['total']} ${s.t('aud_people')}', icon: Icons.check_circle_rounded);
      if (mounted) Navigator.of(context).pop(true);
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
        title: s.t('task_new'),
        children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppTextField(
                  key: const ValueKey('task-title'),
                  controller: _title,
                  label: s.t('task_what'),
                  hint: s.t('task_what_hint'),
                  icon: Icons.task_alt_rounded,
                  maxLength: 120),
              const SizedBox(height: S.x3),
              AppTextField(
                  controller: _desc, label: s.t('task_details'), icon: Icons.notes_rounded, maxLines: 4, maxLength: 2000),
              const SizedBox(height: S.x2),
              Row(children: [
                Icon(Icons.photo_camera_rounded, color: c.text2),
                const SizedBox(width: S.x3),
                Expanded(child: Text(s.t('photo_needed'), style: AppType.body.copyWith(color: c.text))),
                Switch.adaptive(
                    key: const ValueKey('photo-switch'),
                    value: _photo,
                    activeTrackColor: c.accent,
                    onChanged: (v) => setState(() => _photo = v)),
              ]),
            ]),
          ),
          SectionHeader(s.t('deadline')),
          WhenPicker(value: _deadline, onChanged: (d) => setState(() => _deadline = d)),
          SectionHeader(s.t('ch_who')),
          for (final p in presets)
            PresetTile(
              key: ValueKey('preset-${p.$1}'),
              title: p.$2,
              selected: _preset == p.$1,
              onTap: () => setState(() {
                _preset = p.$1;
                _audience = p.$3;
              }),
            ),
          PresetTile(
            key: const ValueKey('preset-custom'),
            title: _preset == 'custom' && _audience != null ? _audience!.label(s) : s.t('preset_custom'),
            icon: Icons.tune_rounded,
            selected: _preset == 'custom',
            onTap: () async {
              final pick =
                  await Navigator.of(context).push<AudiencePick>(AppRoute(builder: (_) => AudienceScreen(title: s.t('ch_who'))));
              if (pick != null) {
                setState(() {
                  _preset = 'custom';
                  _audience = pick;
                });
              }
            },
          ),
          if (_error != null) Text(_error!, style: AppType.footnote.copyWith(color: c.danger)),
          AppButton(s.t('task_give'),
              key: const ValueKey('task-create'),
              icon: Icons.send_rounded,
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : _create),
        ],
      ),
    );
  }
}


/// Reyting belgisi: +1 yashil, −1 qizil / значок рейтинга.
class PointsBadge extends StatelessWidget {
  final int value;
  const PointsBadge(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final good = value > 0;
    final color = good ? const Color(0xFF1F9D55) : const Color(0xFFE5484D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: R.all(R.pill)),
      child: Text(good ? '+$value' : '−${-value}', style: AppType.caption.copyWith(color: color, fontWeight: FontWeight.w800)),
    );
  }
}

/// Baho: +1 yoki −1; tanlanganini qayta bosish — olib tashlash. Baho qo‘ymaslik ham mumkin.
/// Оценка: +1 или −1; повторное нажатие снимает. Можно не оценивать.
class RateRow extends StatefulWidget {
  final int value;
  final Future<void> Function(int value) onChanged;
  final String? plusLabel;
  final String? minusLabel;
  final String keyPrefix;
  const RateRow({super.key, required this.value, required this.onChanged, this.plusLabel, this.minusLabel, this.keyPrefix = 'rate'});

  @override
  State<RateRow> createState() => _RateRowState();
}

class _RateRowState extends State<RateRow> {
  late int _v = widget.value;
  bool _busy = false;

  Future<void> _set(int v) async {
    if (_busy) return;
    final s = AppScope.read(context);
    final next = _v == v ? 0 : v;
    setState(() => _busy = true);
    try {
      await widget.onChanged(next);
      if (next > 0) Sfx.success();
      if (mounted) setState(() => _v = next);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    Widget btn(int v, String label, IconData icon, Color color) {
      final on = _v == v;
      return Expanded(
        child: Pressable(
          key: ValueKey('${widget.keyPrefix}-${v > 0 ? 'plus' : 'minus'}'),
          onTap: () => _set(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 46,
            decoration: BoxDecoration(
              color: on ? color.withValues(alpha: 0.16) : c.surface,
              borderRadius: R.all(R.lg),
              border: Border.all(color: on ? color : c.hairlineStrong, width: on ? 1.8 : 1),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: on ? color : c.text2),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong.copyWith(color: on ? color : c.text)),
              ),
            ]),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s.t('rate_title'), style: AppType.footnote.copyWith(color: c.text2)),
      const SizedBox(height: S.x2),
      Row(children: [
        btn(1, widget.plusLabel ?? '+1', Icons.thumb_up_alt_rounded, const Color(0xFF1F9D55)),
        const SizedBox(width: S.x2),
        btn(-1, widget.minusLabel ?? '−1', Icons.thumb_down_alt_rounded, const Color(0xFFE5484D)),
      ]),
    ]);
  }
}
