// «Adminga yozish» (hamma uchun) va admin vositalari: e’lon, faollik, Excel, foydalanuvchini tahrirlash.
// «Написать админу» (для всех) и инструменты админа: рассылка, активность, Excel, правка пользователя.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../sound.dart';
import 'pickers.dart';

// ============================================================ adminga yozish / написать админу
/// Hamma uchun bitta oddiy shakl: mavzu, matn, ixtiyoriy surat. Javob Telegram orqali keladi.
/// Одна простая форма для всех: тема, текст, фото по желанию. Ответ придёт в Telegram.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _text = TextEditingController();
  String _topic = 'shikoyat';
  Uint8List? _photo;
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    if (f == null) return;
    final b = await f.readAsBytes();
    setState(() => _photo = b);
  }

  Future<void> _send() async {
    final s = AppScope.read(context);
    if (_text.text.trim().length < 3) {
      s.toast(s.t('fb_empty'));
      return;
    }
    setState(() => _busy = true);
    try {
      await s.api.post('/api/feedback', {
        'topic': _topic,
        'text': _text.text.trim(),
        if (_photo != null) 'photo': base64Encode(_photo!),
      }, const Duration(seconds: 60));
      Sfx.success();
      setState(() => _sent = true);
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
    if (_sent) {
      return PageShell(
        child: TabPage(children: [
          const SizedBox(height: S.x8),
          EmptyState(
            icon: Icons.mark_email_read_rounded,
            title: s.t('fb_sent'),
            message: s.t('fb_sent_text'),
            actionLabel: s.t('done'),
            onAction: () => Navigator.of(context).pop(),
          ),
        ]),
      );
    }
    return PageShell(
      child: TabPage(
        title: s.t('fb_title'),
        subtitle: s.t('fb_sub'),
        children: [
          Segmented<String>(
            key: const ValueKey('fb-topic'),
            values: const ['shikoyat', 'taklif', 'savol'],
            labels: [s.t('fb_shikoyat'), s.t('fb_taklif'), s.t('fb_savol')],
            value: _topic,
            onChanged: (v) => setState(() => _topic = v),
          ),
          AppTextField(
            key: const ValueKey('fb-text'),
            controller: _text,
            hint: s.t('fb_hint_$_topic'),
            maxLength: 2000,
            minLines: 5,
            maxLines: 10,
          ),
          if (_photo != null)
            Stack(children: [
              ClipRRect(borderRadius: R.all(R.lg), child: Image.memory(_photo!, height: 160, width: double.infinity, fit: BoxFit.cover)),
              Positioned(
                top: 6,
                right: 6,
                child: AppIconButton(Icons.close_rounded, tooltip: s.t('delete'), onPressed: () => setState(() => _photo = null)),
              ),
            ])
          else
            GroupList([
              GroupRow(
                key: const ValueKey('fb-photo'),
                icon: Icons.add_photo_alternate_rounded,
                color: const Color(0xFF0A84D6),
                title: s.t('fb_photo'),
                onTap: _pick,
              ),
            ]),
          Text(s.t('fb_private'), style: AppType.footnote.copyWith(color: c.text3)),
          AppButton(s.t('fb_send'),
              key: const ValueKey('fb-send'), icon: Icons.send_rounded, expand: true, onPressed: _busy ? null : _send),
        ],
      ),
    );
  }
}

// ============================================================ e’lon tarqatish / рассылка
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _text = TextEditingController();
  String _kind = '';
  String? _district;
  String? _direction;
  int? _count;
  bool _busy = false;

  Json get _filter => {
        if (_kind.isNotEmpty) 'kind': _kind,
        if (_district != null) 'district_id': _district,
        if (_direction != null) 'direction': _direction,
      };

  @override
  void initState() {
    super.initState();
    _recount();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _recount() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.post('/api/admin/broadcast/count', {'filter': _filter});
      if (mounted) setState(() => _count = (r['count'] as num).toInt());
    } on ApiError catch (_) {}
  }

  Future<void> _send() async {
    final s = AppScope.read(context);
    if (_text.text.trim().length < 2) {
      s.toast(s.t('fb_empty'));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await s.api.post('/api/admin/broadcast', {'text': _text.text.trim(), 'filter': _filter});
      Sfx.success();
      s.toast('${s.t('bc_sent')}: ${r['count']}', icon: Icons.check_circle_rounded);
      if (mounted) Navigator.of(context).pop();
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
    final dname = _district == null
        ? s.t('all')
        : s.pick(s.districts.firstWhere((d) => d['id'] == _district, orElse: () => const {}), 'name');
    return PageShell(
      child: TabPage(
        title: '📣 ${s.t('bc_title')}',
        subtitle: s.t('bc_sub'),
        children: [
          Segmented<String>(
            key: const ValueKey('bc-kind'),
            values: const ['', 'coordinator', 'maslahatchi', 'student'],
            labels: [s.t('all'), s.t('bc_coords'), s.t('maslahatchi'), s.t('students')],
            value: _kind,
            onChanged: (v) {
              setState(() => _kind = v);
              _recount();
            },
          ),
          GroupList([
            GroupRow(
              key: const ValueKey('bc-district'),
              icon: Icons.map_rounded,
              color: const Color(0xFF0A84D6),
              title: s.t('district'),
              value: dname,
              onTap: () async {
                final d = await pickDistrict(context);
                setState(() => _district = d == _district ? null : d);
                _recount();
              },
            ),
            if (_kind != 'student' && _kind != 'maslahatchi')
              GroupRow(
                key: const ValueKey('bc-direction'),
                icon: Icons.tune_rounded,
                color: _direction == null ? c.accent : directionColor(_direction),
                title: s.t('direction'),
                value: _direction == null ? s.t('all') : s.dirName(_direction),
                onTap: () async {
                  final d = await pickDirection(context);
                  setState(() => _direction = d == _direction ? null : d);
                  _recount();
                },
              ),
          ]),
          AppTextField(
              key: const ValueKey('bc-text'), controller: _text, hint: s.t('bc_hint'), maxLength: 3000, minLines: 5, maxLines: 12),
          Text(s.t('bc_note'), style: AppType.footnote.copyWith(color: c.text3)),
          AppButton(
            _count == null ? s.t('bc_send') : '${s.t('bc_send')} · ${_count!} ${s.t('aud_people')}',
            key: const ValueKey('bc-send'),
            icon: Icons.send_rounded,
            expand: true,
            onPressed: _busy || _count == 0 ? null : _send,
          ),
        ],
      ),
    );
  }
}

// ============================================================ faollik va Excel / активность и Excel
/// Oylik hisobot: tanlangan oy bo‘yicha xulosa + «Telegram’ga yuborish».
/// Ежемесячный отчёт: сводка за выбранный месяц + «Отправить в Telegram».
class ReportCard extends StatefulWidget {
  const ReportCard({super.key});

  @override
  State<ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<ReportCard> {
  Json? _d;
  late DateTime _month = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month);
  }();

  String get _key => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final d = await s.api.get('/api/report', query: {'month': _key});
      if (mounted) setState(() => _d = d);
    } on ApiError catch (_) {}
  }

  void _shift(int by) {
    final n = DateTime(_month.year, _month.month + by);
    final now = DateTime.now();
    if (n.isAfter(DateTime(now.year, now.month))) return;
    setState(() {
      _month = n;
      _d = null;
    });
    _load();
  }

  Future<void> _send() async {
    final s = AppScope.read(context);
    try {
      await s.api.post('/api/report/send', {'month': _key});
      s.toast(s.t('rep_sent'), icon: Icons.send_rounded);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final d = _d;
    String pct(Object? v) => v == null ? '—' : '$v%';
    final months = s.lang == 'ru'
        ? const ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь']
        : const ['Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun', 'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr'];
    final top = [for (final x in (d?['top'] as List? ?? [])) (x as Map).cast<String, dynamic>()];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('🗓 ${s.t('rep_title')}'),
      const SizedBox(height: S.x3),
      AppCard(
        key: const ValueKey('report-card'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            AppIconButton(Icons.chevron_left_rounded, key: const ValueKey('rep-prev'), tooltip: '', onPressed: () => _shift(-1)),
            Expanded(
              child: Text('${months[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center, style: AppType.headline.copyWith(color: c.text)),
            ),
            AppIconButton(Icons.chevron_right_rounded, key: const ValueKey('rep-next'), tooltip: '', onPressed: () => _shift(1)),
          ]),
          const SizedBox(height: S.x3),
          if (d == null)
            const SkeletonRows(count: 2)
          else ...[
            Row(children: [
              Expanded(child: _RepNum(value: '${d['people']}', label: s.t('rep_people'))),
              Expanded(child: _RepNum(value: pct(d['tasks_pct']), label: '${s.t('rep_tasks')} · ${d['tasks']}')),
              Expanded(child: _RepNum(value: pct(d['came_pct']), label: '${s.t('rep_events')} · ${d['events']}')),
            ]),
            if ((d['tasks_late'] as num? ?? 0) > 0 || (d['quiet_count'] as num? ?? 0) > 0) ...[
              const SizedBox(height: S.x3),
              Text(
                  [
                    if ((d['tasks_late'] as num? ?? 0) > 0) '⏰ ${s.t('rep_late')}: ${d['tasks_late']}',
                    if ((d['quiet_count'] as num? ?? 0) > 0) '😴 ${s.t('rep_quiet')}: ${d['quiet_count']}',
                  ].join('  ·  '),
                  style: AppType.footnote.copyWith(color: c.text2)),
            ],
            if (top.isNotEmpty) ...[
              const SizedBox(height: S.x3),
              Text('🏆 ${s.t('rep_top')}', style: AppType.subhead.copyWith(color: c.text)),
              const SizedBox(height: S.x1),
              for (final p in top.take(3))
                Text('${p['name']} — +${p['score']}', style: AppType.footnote.copyWith(color: c.text2)),
            ],
          ],
          const SizedBox(height: S.x4),
          AppButton(s.t('rep_send'),
              key: const ValueKey('rep-send'), kind: BtnKind.secondary, icon: Icons.send_rounded, expand: true, height: 46,
              onPressed: _send),
        ]),
      ),
    ]);
  }
}

class _RepNum extends StatelessWidget {
  final String value;
  final String label;
  const _RepNum({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Column(children: [
      Text(value, style: AppType.number.copyWith(color: c.accentText)),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center, maxLines: 2, style: AppType.caption.copyWith(color: c.text2)),
    ]);
  }
}

/// Chorak sertifikatlari: guruhlar (tumanlar) va g‘oliblar, PDF yuklab olish.
/// Квартальные сертификаты: группы (районы) и победители, скачать PDF.
class CertificatesCard extends StatefulWidget {
  const CertificatesCard({super.key});

  @override
  State<CertificatesCard> createState() => _CertificatesCardState();
}

class _CertificatesCardState extends State<CertificatesCard> {
  Json? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final d = await s.api.get('/api/certificates');
      if (mounted) setState(() => _d = d);
    } on ApiError catch (_) {}
  }

  Future<void> _pdf(String group) async {
    final s = AppScope.read(context);
    s.toast(s.t('ex_preparing'), icon: Icons.hourglass_top_rounded);
    try {
      final r = await s.api.post('/api/certificates/pdf', {'group': group}, const Duration(seconds: 90));
      await s.openUrl(r['url'] as String);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final d = _d;
    final groups = [
      for (final g in (d?['groups'] as List? ?? [])) (g as Map).cast<String, dynamic>()
    ].where((g) => (g['winners'] as List).isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('🏅 ${s.t('cert_title')}${d == null ? '' : ' · ${d['quarter']}'}'),
      const SizedBox(height: S.x3),
      if (d == null)
        const SkeletonRows(count: 2)
      else if (groups.isEmpty)
        AppCard(child: Text(s.t('cert_none'), style: AppType.subhead.copyWith(color: c.text2)))
      else
        GroupList([
          for (final g in groups)
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('cert-${g['id']}'),
                onTap: () => _pdf(g['id'] as String),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
                  child: Row(children: [
                    const Icon(Icons.workspace_premium_rounded, color: Color(0xFFE8B628), size: 28),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text((g['name'] ?? '').toString(), style: AppType.bodyStrong.copyWith(color: c.text)),
                        Text(
                            [
                              for (final w in (g['winners'] as List).cast<Map>())
                                '${w['rank']}. ${((w['user'] as Map)['name'] ?? '').toString().split(' ').take(2).join(' ')}'
                            ].join('  ·  '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.footnote.copyWith(color: c.text2)),
                      ]),
                    ),
                    Icon(Icons.picture_as_pdf_rounded, color: c.accentText),
                  ]),
                ),
              ),
            ),
        ]),
    ]);
  }
}

class ActivityCard extends StatefulWidget {
  const ActivityCard({super.key});

  @override
  State<ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<ActivityCard> {
  Json? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final d = await s.api.get('/api/admin/activity');
      if (mounted) setState(() => _d = d);
    } on ApiError catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final d = _d;
    if (d == null) return const SkeletonRows(count: 3);
    final districts = [for (final x in d['districts'] as List) (x as Map).cast<String, dynamic>()];
    final inactive = [for (final x in d['inactive'] as List) (x as Map).cast<String, dynamic>()];
    final top = [for (final x in d['top_schools'] as List) (x as Map).cast<String, dynamic>()];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('📈 ${s.t('act_title')}'),
      const SizedBox(height: S.x3),
      AppCard(
        key: const ValueKey('act-districts'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('act_tasks'), style: AppType.headline.copyWith(color: c.text)),
          const SizedBox(height: S.x3),
          for (final x in districts) ...[
            Row(children: [
              Expanded(
                child: Text(s.pick(x, 'name'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.subhead.copyWith(color: c.text)),
              ),
              Text(x['done_pct'] == null ? '—' : '${x['done_pct']}%',
                  style: AppType.subhead.copyWith(color: c.text2, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            AppProgress(((x['done_pct'] as num?) ?? 0) / 100, height: 6, gradient: c.accentGradient),
            const SizedBox(height: 2),
            Text('${s.t('act_empty_schools')}: ${x['schools_empty']} / ${x['schools']}',
                style: AppType.caption.copyWith(color: (x['schools_empty'] as num) > 0 ? c.danger : c.text3)),
            const SizedBox(height: S.x3),
          ],
        ]),
      ),
      const SizedBox(height: S.x3),
      if (top.isNotEmpty)
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('🏆 ${s.t('act_top')}', style: AppType.headline.copyWith(color: c.text)),
            const SizedBox(height: S.x2),
            for (final (i, t) in top.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 24, child: Text('${i + 1}', style: AppType.bodyStrong.copyWith(color: c.text3))),
                  Expanded(child: Text(s.placeLine((t['place'] as Map).cast<String, dynamic>()), style: AppType.body.copyWith(color: c.text))),
                  Text('${t['messages']} 💬', style: AppType.footnote.copyWith(color: c.text2)),
                ]),
              ),
          ]),
        ),
      const SizedBox(height: S.x3),
      AppCard(
        key: const ValueKey('act-inactive'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('😴 ${s.t('act_inactive')}: ${d['inactive_count']}', style: AppType.headline.copyWith(color: c.text)),
          const SizedBox(height: S.x2),
          if (inactive.isEmpty)
            Text(s.t('act_all_active'), style: AppType.subhead.copyWith(color: c.text2))
          else
            for (final u in inactive.take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  AppAvatar(url: s.photoUrl(u['photo']), name: (u['name'] ?? '').toString(), size: 30),
                  const SizedBox(width: S.x2),
                  Expanded(
                    child: Text('${u['name']} · ${s.seatLine(u)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text)),
                  ),
                  if ((u['tg_username'] ?? '').toString().isNotEmpty)
                    IconButton(
                      tooltip: 'Telegram',
                      icon: Icon(Icons.send_rounded, size: 18, color: c.accent),
                      onPressed: () => s.openUrl('https://t.me/${u['tg_username']}'),
                    ),
                ]),
              ),
        ]),
      ),
    ]);
  }
}

class ExportCard extends StatelessWidget {
  final bool books;
  const ExportCard({super.key, this.books = true});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    Future<void> run(String what) async {
      s.toast(s.t('ex_preparing'), icon: Icons.hourglass_top_rounded);
      try {
        final r = await s.api.post('/api/admin/export', {'what': what}, const Duration(seconds: 90));
        await s.openUrl(r['url'] as String);
      } on ApiError catch (e) {
        s.toast(s.errText(e));
      }
    }

    Widget row(String what, IconData icon, Color color) => GroupRow(
          key: ValueKey('export-$what'),
          icon: icon,
          color: color,
          title: s.t('ex_$what'),
          trailing: const Icon(Icons.download_rounded, size: 20),
          onTap: () => run(what),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('📊 ${s.t('ex_title')}'),
      const SizedBox(height: S.x3),
      GroupList([
        row('users', Icons.people_alt_rounded, const Color(0xFF1F9D55)),
        row('tasks', Icons.task_alt_rounded, const Color(0xFF0A84D6)),
        row('rating', Icons.emoji_events_rounded, const Color(0xFFFFBB02)),
        if (books) row('books', Icons.menu_book_rounded, const Color(0xFFD6409F)),
      ]),
    ]);
  }
}

// ============================================================ foydalanuvchini tahrirlash / правка пользователя
class EditUserScreen extends StatefulWidget {
  final Json user;
  const EditUserScreen({super.key, required this.user});

  @override
  State<EditUserScreen> createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  late final _name = TextEditingController(text: (widget.user['name'] ?? '').toString());
  late String _kind = _initialKind();
  late String _level = (widget.user['level'] ?? 'school').toString();
  late String? _district = _initialDistrict();
  late String? _school = widget.user['level'] == 'school' ? widget.user['place_id'] as String? : null;
  String? _schoolName;
  late String? _direction =
      kDirectionColors.containsKey(widget.user['direction']) && widget.user['direction'] != 'maslahatchi'
          ? widget.user['direction'] as String?
          : null;
  late int _grade = int.tryParse((widget.user['class_name'] ?? '').toString().split('-').first) ?? 7;
  late String _letter =
      (widget.user['class_name'] ?? '').toString().contains('-') ? (widget.user['class_name'] as String).split('-').last : 'A';
  bool _busy = false;

  String _initialKind() {
    final k = (widget.user['kind'] ?? '').toString();
    return ['coordinator', 'maslahatchi', 'student'].contains(k) ? k : 'coordinator';
  }

  String? _initialDistrict() {
    final p = (widget.user['place'] as Map?)?.cast<String, dynamic>();
    if (p == null) return null;
    if (p['level'] == 'school') return p['district_id'] as String?;
    if (p['level'] == 'district') return p['id'] as String?;
    return null;
  }

  @override
  void initState() {
    super.initState();
    final p = (widget.user['place'] as Map?)?.cast<String, dynamic>();
    if (p != null && p['level'] == 'school') _schoolName = AppScope.read(context).pick(p, 'name');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppScope.read(context);
    final level = _kind == 'coordinator' ? _level : 'school';
    final place = level == 'region' ? 'andijon' : (level == 'district' ? _district : _school);
    if (place == null || (_kind == 'coordinator' && _direction == null)) {
      s.toast(s.t('eu_fill'));
      return;
    }
    setState(() => _busy = true);
    try {
      await s.api.post('/api/admin/users/${widget.user['id']}/edit', {
        'name': _name.text.trim(),
        'kind': _kind,
        'level': level,
        'place_id': place,
        if (_kind == 'coordinator') 'direction': _direction,
        if (_kind == 'student') 'class_name': '$_grade-$_letter',
        if (widget.user['status'] == 'pending') 'status': 'active',
      });
      s.toast(s.t('saved'), icon: Icons.check_circle_rounded);
      if (mounted) Navigator.of(context).pop(true);
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
    final level = _kind == 'coordinator' ? _level : 'school';
    final dname = _district == null
        ? '—'
        : s.pick(s.districts.firstWhere((d) => d['id'] == _district, orElse: () => const {}), 'name');
    const letters = ['A', 'B', 'V', 'G', 'D', 'E'];
    return PageShell(
      child: TabPage(
        title: s.t('eu_title'),
        subtitle: (widget.user['name'] ?? '').toString(),
        children: [
          AppTextField(key: const ValueKey('eu-name'), controller: _name, label: s.t('full_name'), maxLength: 60),
          Segmented<String>(
            key: const ValueKey('eu-kind'),
            values: const ['coordinator', 'maslahatchi', 'student'],
            labels: [s.t('bc_coords'), s.t('maslahatchi'), s.t('student')],
            value: _kind,
            onChanged: (v) => setState(() => _kind = v),
          ),
          if (_kind == 'coordinator')
            Segmented<String>(
              values: const ['school', 'district', 'region'],
              labels: [s.t('lvl_school'), s.t('lvl_district'), s.t('lvl_region')],
              value: _level,
              onChanged: (v) => setState(() => _level = v),
            ),
          GroupList([
            if (level != 'region')
              GroupRow(
                icon: Icons.map_rounded,
                color: const Color(0xFF0A84D6),
                title: s.t('district'),
                value: dname,
                onTap: () async {
                  final d = await pickDistrict(context);
                  if (d == null) return;
                  setState(() {
                    _district = d;
                    _school = null;
                    _schoolName = null;
                  });
                },
              ),
            if (level == 'school')
              GroupRow(
                key: const ValueKey('eu-school'),
                icon: Icons.school_rounded,
                color: c.accent,
                title: s.t('school'),
                value: _schoolName ?? '—',
                onTap: _district == null
                    ? null
                    : () async {
                        final sc = await pickSchool(context, _district!);
                        if (sc == null) return;
                        setState(() {
                          _school = sc['id'] as String;
                          _schoolName = s.pick(sc, 'name');
                        });
                      },
              ),
            if (_kind == 'coordinator')
              GroupRow(
                icon: Icons.tune_rounded,
                color: directionColor(_direction),
                title: s.t('direction'),
                value: _direction == null ? '—' : s.dirName(_direction),
                onTap: () async {
                  final d = await pickDirection(context);
                  if (d != null) setState(() => _direction = d);
                },
              ),
          ]),
          if (_kind == 'student') ...[
            Text(s.t('eu_class'), style: AppType.footnote.copyWith(color: c.text2)),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var g = 1; g <= 11; g++)
                ChoiceChip(label: Text('$g'), selected: _grade == g, onSelected: (_) => setState(() => _grade = g)),
            ]),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final l in letters)
                ChoiceChip(label: Text(l), selected: _letter == l, onSelected: (_) => setState(() => _letter = l)),
            ]),
          ],
          AppButton(s.t('save'),
              key: const ValueKey('eu-save'), icon: Icons.check_rounded, expand: true, onPressed: _busy ? null : _save),
        ],
      ),
    );
  }
}
