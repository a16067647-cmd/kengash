import 'package:flutter/material.dart';

import '../api.dart';
import '../brand.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'channels.dart' show MessageBubble, timeLabel;
import 'admin_more.dart';
import 'books.dart' show AdminBooksScreen;
import 'directory.dart' show confirmSheet;
import 'media.dart' show PhotoViewer;
import 'pickers.dart';
import 'staff.dart' show StaffScreen;

/// Admin paneli: statistika, foydalanuvchilar, maktablar.
/// Панель админа: статистика, пользователи, школы.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  String _seg = 'stats';

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return TabPage(
      title: s.t('admin'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIconButton(Icons.campaign_rounded,
            key: const ValueKey('admin-broadcast'),
            tooltip: s.t('bc_title'),
            color: s.c.accentText,
            onPressed: () => Navigator.of(context).push(AppRoute(builder: (_) => const BroadcastScreen()))),
        const SizedBox(width: S.x2),
        AppIconButton(Icons.badge_rounded,
            key: const ValueKey('admin-staff'),
            tooltip: s.t('staff_title'),
            color: s.c.accentText,
            onPressed: () => Navigator.of(context).push(AppRoute(builder: (_) => const StaffScreen()))),
        const SizedBox(width: S.x2),
        AppIconButton(Icons.menu_book_rounded,
            key: const ValueKey('admin-books'),
            tooltip: s.t('books_title'),
            color: s.c.accentText,
            onPressed: () => Navigator.of(context).push(AppRoute(builder: (_) => const AdminBooksScreen()))),
      ]),
      children: [
        Segmented<String>(
          values: const ['stats', 'users', 'schools', 'reports'],
          labels: [s.t('stats'), s.t('users'), s.t('schools'), s.t('reports')],
          value: _seg,
          onChanged: (v) => setState(() => _seg = v),
        ),
        switch (_seg) {
          'users' => const _Users(),
          'schools' => const _Schools(),
          'reports' => const _Reports(),
          _ => const _Stats(),
        },
      ],
    );
  }
}

// ------------------------------------------------------------------ statistika / статистика
class _Stats extends StatefulWidget {
  const _Stats();

  @override
  State<_Stats> createState() => _StatsState();
}

class _StatsState extends State<_Stats> {
  Json? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final d = await s.api.get('/api/admin/stats');
      if (mounted) setState(() => _d = d);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    if (_error != null) return EmptyState(icon: Icons.wifi_off_rounded, title: _error!, error: true);
    final d = _d;
    if (d == null) return const SkeletonRows(count: 4);
    final total = (d['seats_total'] as num).toInt();
    final seated = (d['seated'] as num).toInt();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      gridOf([
        StatTile(icon: Icons.people_alt_rounded, value: '${d['users']}', label: s.t('st_users')),
        StatTile(icon: Icons.event_seat_rounded, value: '$seated', label: s.t('st_seated')),
        StatTile(icon: Icons.bolt_rounded, value: '${d['active_week']}', label: s.t('st_active')),
        StatTile(icon: Icons.school_rounded, value: '${d['schools']}', label: s.t('st_schools')),
      ], 2),
      const SizedBox(height: S.x5),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('st_fill'), style: AppType.headline.copyWith(color: c.text)),
          const SizedBox(height: S.x3),
          AppProgress(total == 0 ? 0 : seated / total, gradient: c.accentGradient),
          const SizedBox(height: S.x2),
          Text('$seated / $total', style: AppType.footnote.copyWith(color: c.text2)),
        ]),
      ),
      const SizedBox(height: S.x5),
      SectionHeader(s.t('districts')),
      const SizedBox(height: S.x3),
      GroupList([
        for (final x in (d['by_district'] as List).cast<Map>())
          GroupRow(
            icon: Icons.map_rounded,
            color: c.accent,
            title: s.pick(x.cast<String, dynamic>(), 'name'),
            value: '${x['users']} · ${x['schools']} ${s.t('schools_short')}',
          ),
      ]),
      const SizedBox(height: S.x5),
      const ActivityCard(),
      const SizedBox(height: S.x5),
      const ExportCard(),
    ]);
  }
}

// ------------------------------------------------------------------ foydalanuvchilar / пользователи
class _Users extends StatefulWidget {
  const _Users();

  @override
  State<_Users> createState() => _UsersState();
}

class _UsersState extends State<_Users> {
  List<Json>? _users;
  int _total = 0;
  String _q = '';
  String _level = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/admin/users', query: {'q': _q, 'level': _level});
      if (mounted) {
        setState(() {
          _users = [for (final x in r['users'] as List) (x as Map).cast<String, dynamic>()];
          _total = (r['total'] as num).toInt();
        });
      }
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(
        key: const ValueKey('admin-search'),
        hint: s.t('search_users'),
        icon: Icons.search_rounded,
        onChanged: (v) {
          _q = v.trim();
          _load();
        },
      ),
      const SizedBox(height: S.x3),
      HScroll(
        child: Row(children: [
          for (final (v, k) in [
            ('', 'all'),
            ('region', 'lvl_region'),
            ('district', 'lvl_district'),
            ('school', 'lvl_school'),
            ('none', 'no_seat')
          ])
            Padding(
              padding: const EdgeInsets.only(right: S.x2),
              child: Pressable(
                onTap: () {
                  setState(() => _level = v);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
                  decoration: BoxDecoration(
                    color: _level == v ? c.accentSoft : c.surface,
                    borderRadius: R.all(R.pill),
                    border: Border.all(color: _level == v ? c.accent : c.hairlineStrong),
                  ),
                  child: Text(s.t(k), style: AppType.subhead.copyWith(color: _level == v ? c.accentText : c.text)),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: S.x3),
      Text('${s.t('found')}: $_total', style: AppType.footnote.copyWith(color: c.text2)),
      const SizedBox(height: S.x2),
      if (_users == null)
        const SkeletonRows(count: 5)
      else if (_users!.isEmpty)
        EmptyState(icon: Icons.person_search_rounded, title: s.t('nothing_found'))
      else
        GroupList([
          for (final u in _users!)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _open(u),
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
                    if (u['status'] == 'blocked') AppPill(s.t('blocked'), tone: Tone.danger, small: true),
                    if (u['role'] == 'admin') AppPill('Admin', tone: Tone.accent, small: true),
                  ]),
                ),
              ),
            ),
        ]),
    ]);
  }

  Future<void> _open(Json u) async {
    final s = AppScope.read(context);
    final uid = u['id'];
    Future<void> act(Future<void> Function() f) async {
      try {
        await f();
        if (mounted) Navigator.of(context).pop();
        s.toast(s.t('saved'), icon: Icons.check_circle_rounded);
        _load();
      } on ApiError catch (e) {
        s.toast(s.errText(e));
      }
    }

    await showAppSheet<void>(context, builder: (ctx) {
      final c = AppScope.of(ctx).c;
      final blocked = u['status'] == 'blocked';
      return SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: AppAvatar(url: s.photoUrl(u['photo']), name: (u['name'] ?? '').toString(), size: 80, ring: true)),
          const SizedBox(height: S.x3),
          Text((u['name'] ?? '').toString(), textAlign: TextAlign.center, style: AppType.title3.copyWith(color: c.text)),
          Text(s.seatLine(u), textAlign: TextAlign.center, style: AppType.subhead.copyWith(color: c.text2)),
          Text([if ((u['tg_username'] ?? '') != '') '@${u['tg_username']}', (u['phone'] ?? '').toString()].join(' · '),
              textAlign: TextAlign.center, style: AppType.footnote.copyWith(color: c.text3)),
          const SizedBox(height: S.x5),
          if (u['role'] != 'admin') ...[
            // ism, rol, maktab, sinf, yo‘nalish — hammasi bir joyda / имя, роль, школа, класс, направление
            AppButton(s.t('eu_title'), key: const ValueKey('user-edit'), kind: BtnKind.secondary, icon: Icons.edit_rounded,
                expand: true, onPressed: () async {
              Navigator.of(ctx).pop();
              final ok = await Navigator.of(context).push<bool>(AppRoute(builder: (_) => EditUserScreen(user: u)));
              if (ok == true) _load();
            }),
            if (u['level'] != null) ...[
              const SizedBox(height: S.x2),
              AppButton(s.t('free_seat'),
                  kind: BtnKind.secondary,
                  icon: Icons.person_remove_rounded,
                  expand: true,
                  onPressed: () => act(() => s.api.post('/api/admin/users/$uid/seat', {}))),
            ],
            const SizedBox(height: S.x2),
            AppButton(blocked ? s.t('unblock') : s.t('block'),
                kind: BtnKind.danger,
                icon: blocked ? Icons.lock_open_rounded : Icons.block_rounded,
                expand: true,
                onPressed: () => act(() => s.api.post('/api/admin/users/$uid/block', {'blocked': !blocked}))),
            const SizedBox(height: S.x2),
            AppButton(s.t('delete_user'), kind: BtnKind.danger, icon: Icons.delete_forever_rounded, expand: true,
                onPressed: () async {
              if (!await confirmSheet(ctx, s.t('delete_user_q'), s.t('delete_user'))) return;
              await act(() => s.api.post('/api/admin/users/$uid/delete'));
            }),
          ],
        ]),
      );
    });
  }

  /// Admin uchun o‘rin tanlash / выбор места для админа.
  Future<Json?> _pickSeat(BuildContext context) async {
    final s = AppScope.read(context);
    final level = await showAppSheet<String>(context, builder: (ctx) {
      final c = AppScope.of(ctx).c;
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('set_seat'), style: AppType.title3.copyWith(color: c.text)),
        const SizedBox(height: S.x4),
        GroupList([
          for (final l in ['school', 'district', 'region'])
            GroupRow(icon: Icons.layers_rounded, color: c.accent, title: s.levelName(l), onTap: () => Navigator.of(ctx).pop(l)),
        ]),
      ]);
    });
    if (level == null || !context.mounted) return null;
    String? placeId = 'andijon';
    if (level != 'region') {
      final d = await pickDistrict(context);
      if (d == null || !context.mounted) return null;
      placeId = d;
      if (level == 'school') {
        final sch = await pickSchool(context, d);
        if (sch == null) return null;
        placeId = sch['id'] as String;
      }
    }
    if (!context.mounted) return null;
    final dir = await pickDirection(context);
    if (dir == null) return null;
    return {'level': level, 'place_id': placeId, 'direction': dir};
  }
}

// ------------------------------------------------------------------ maktablar / школы
class _Schools extends StatefulWidget {
  const _Schools();

  @override
  State<_Schools> createState() => _SchoolsState();
}

class _SchoolsState extends State<_Schools> {
  String? _district;
  List<Json>? _schools;
  final _spec = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _spec.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    if (_district == null) return;
    try {
      final r = await s.api.get('/api/schools', query: {'district_id': _district!});
      if (mounted) setState(() => _schools = [for (final x in r['schools'] as List) (x as Map).cast<String, dynamic>()]);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  Future<void> _add() async {
    final s = AppScope.read(context);
    if (_spec.text.trim().isEmpty && _name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await s.api.post('/api/admin/schools/bulk',
          {'district_id': _district, 'spec': _spec.text.trim(), if (_spec.text.trim().isEmpty) 'name': _name.text.trim()});
      s.toast('${s.t('added')}: ${r['added']}', icon: Icons.check_circle_rounded);
      _spec.clear();
      _name.clear();
      _load();
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GroupList([
        GroupRow(
          key: const ValueKey('admin-district'),
          icon: Icons.map_rounded,
          color: c.accent,
          title: s.t('district'),
          value: _district == null ? s.t('choose') : s.districtName(_district),
          onTap: () async {
            final d = await pickDistrict(context);
            if (d != null) {
              setState(() {
                _district = d;
                _schools = null;
              });
              _load();
            }
          },
        ),
      ]),
      if (_district != null) ...[
        const SizedBox(height: S.x5),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.t('add_schools'), style: AppType.headline.copyWith(color: c.text)),
            const SizedBox(height: S.x1),
            Text(s.t('add_schools_text'), style: AppType.footnote.copyWith(color: c.text2)),
            const SizedBox(height: S.x3),
            AppTextField(
                key: const ValueKey('school-spec'),
                controller: _spec,
                hint: '1-62, 70, 71',
                icon: Icons.format_list_numbered_rounded,
                onSubmitted: (_) => _add()),
            const SizedBox(height: S.x2),
            AppTextField(controller: _name, hint: s.t('school_name_hint'), icon: Icons.edit_rounded, onSubmitted: (_) => _add()),
            const SizedBox(height: S.x3),
            AppButton(s.t('add'),
                key: const ValueKey('school-add'), icon: Icons.add_rounded, expand: true, loading: _busy, onPressed: _add),
          ]),
        ),
        const SizedBox(height: S.x5),
        if (_schools == null)
          const SkeletonRows(count: 4)
        else if (_schools!.isEmpty)
          EmptyState(icon: Icons.school_rounded, title: s.t('no_schools'))
        else
          GroupList([
            for (final x in _schools!)
              GroupRow(
                icon: x['hidden'] == 1 ? Icons.visibility_off_rounded : Icons.school_rounded,
                color: x['hidden'] == 1 ? const Color(0xFF8E8E93) : c.accent,
                title: s.pick(x, 'name'),
                value: '${x['filled']}/8',
                onTap: () => _edit(x),
              ),
          ]),
      ],
    ]);
  }

  Future<void> _edit(Json x) async {
    final s = AppScope.read(context);
    final name = TextEditingController(text: (x['name'] ?? '').toString());
    final num = TextEditingController(text: (x['number'] ?? '').toString());
    Future<void> save(Json body) async {
      try {
        await s.api.post('/api/admin/schools/${x['id']}', body);
        if (mounted) Navigator.of(context).pop();
        _load();
      } on ApiError catch (e) {
        s.toast(s.errText(e));
      }
    }

    await showAppSheet<void>(context, builder: (ctx) {
      final c = AppScope.of(ctx).c;
      final hidden = x['hidden'] == 1;
      return SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const DirectionTile('talim', size: 36),
            const SizedBox(width: S.x3),
            Expanded(child: Text(s.pick(x, 'name'), style: AppType.title3.copyWith(color: c.text))),
          ]),
          const SizedBox(height: S.x4),
          AppTextField(controller: num, label: s.t('school_number'), icon: Icons.tag_rounded, keyboardType: TextInputType.number),
          const SizedBox(height: S.x3),
          AppTextField(controller: name, label: s.t('school_name'), hint: s.t('school_name_hint'), icon: Icons.edit_rounded),
          const SizedBox(height: S.x4),
          AppButton(s.t('save'), expand: true, onPressed: () => save({'name': name.text.trim(), 'number': num.text.trim()})),
          const SizedBox(height: S.x2),
          AppButton(hidden ? s.t('show') : s.t('hide'),
              kind: BtnKind.secondary, expand: true, onPressed: () => save({'hidden': !hidden})),
          const SizedBox(height: S.x2),
          AppButton(s.t('delete'), kind: BtnKind.danger, expand: true, onPressed: () => save({'delete': true})),
        ]),
      );
    });
  }
}

// ------------------------------------------------------------------ shikoyatlar / жалобы
class _Reports extends StatefulWidget {
  const _Reports();

  @override
  State<_Reports> createState() => _ReportsState();
}

class _ReportsState extends State<_Reports> {
  List<Json>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/admin/reports');
      if (mounted) setState(() => _list = [for (final x in r['reports'] as List) (x as Map).cast<String, dynamic>()]);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  Future<void> _act(Json r, String action) async {
    final s = AppScope.read(context);
    if (action == 'block' && !await confirmSheet(context, s.t('rep_block_q'), s.t('block'))) return;
    try {
      await s.api.post('/api/admin/reports/${r['id']}', {'action': action});
      s.toast(s.t('saved'), icon: Icons.check_circle_rounded);
      _load();
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final list = _list;
    if (list == null) return const SkeletonRows(count: 3);
    if (list.isEmpty) return EmptyState(icon: Icons.verified_user_rounded, title: s.t('rep_none'), message: s.t('rep_none_text'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final r in list) ...[
        if (r['kind'] == 'feedback')
          _FeedbackCard(r: r, onDone: _load)
        else
        AppCard(
          key: ValueKey('report-${r['id']}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              AppPill(s.t('reason_${r['reason']}'), icon: Icons.flag_rounded, tone: Tone.danger, small: true),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(s.pick((r['channel'] as Map?)?.cast<String, dynamic>(), 'title'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2)),
              ),
              Text(timeLabel(s, r['created_at'] as num?), style: AppType.caption.copyWith(color: c.text3)),
            ]),
            const SizedBox(height: S.x3),
            if (r['message'] != null)
              IgnorePointer(child: MessageBubble(m: (r['message'] as Map).cast<String, dynamic>()))
            else
              Text(s.t('msg_deleted'), style: AppType.subhead.copyWith(color: c.text3)),
            const SizedBox(height: S.x2),
            Text('${s.t('rep_by')}: ${((r['reporter'] as Map?)?['name'] ?? '')}',
                style: AppType.footnote.copyWith(color: c.text2)),
            const SizedBox(height: S.x3),
            Row(children: [
              Expanded(
                  child: AppButton(s.t('delete'),
                      key: ValueKey('rep-del-${r['id']}'), kind: BtnKind.danger, height: 44, onPressed: () => _act(r, 'delete'))),
              const SizedBox(width: S.x2),
              Expanded(child: AppButton(s.t('block'), kind: BtnKind.danger, height: 44, onPressed: () => _act(r, 'block'))),
              const SizedBox(width: S.x2),
              Expanded(
                  child: AppButton(s.t('rep_dismiss'), kind: BtnKind.secondary, height: 44, onPressed: () => _act(r, 'dismiss'))),
            ]),
          ]),
        ),
        const SizedBox(height: S.x3),
      ],
    ]);
  }
}


/// Foydalanuvchidan kelgan xabar: mavzu, matn, surat; admin javobi Telegram orqali ketadi.
/// Сообщение пользователя: тема, текст, фото; ответ админа уходит в Telegram.
class _FeedbackCard extends StatefulWidget {
  final Json r;
  final VoidCallback onDone;
  const _FeedbackCard({required this.r, required this.onDone});

  @override
  State<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends State<_FeedbackCard> {
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final s = AppScope.read(context);
    if (_reply.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await s.api.post('/api/admin/feedback/${widget.r['id']}/reply', {'text': _reply.text.trim()});
      s.toast(s.t('fb_replied'), icon: Icons.check_circle_rounded);
      widget.onDone();
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
    final r = widget.r;
    final who = (r['reporter'] as Map?)?.cast<String, dynamic>();
    final topic = (r['reason'] ?? 'shikoyat').toString();
    final photo = (r['photo_url'] ?? '').toString();
    return AppCard(
      key: ValueKey('feedback-${r['id']}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AppPill(s.t('fb_$topic'),
              icon: topic == 'shikoyat' ? Icons.report_rounded : (topic == 'taklif' ? Icons.lightbulb_rounded : Icons.help_rounded),
              tone: topic == 'shikoyat' ? Tone.danger : Tone.accent,
              small: true),
          const Spacer(),
          Text(timeLabel(s, r['created_at'] as num?), style: AppType.caption.copyWith(color: c.text3)),
        ]),
        const SizedBox(height: S.x3),
        if (who != null)
          Row(children: [
            AppAvatar(url: s.photoUrl(who['photo']), name: (who['name'] ?? '').toString(), size: 34),
            const SizedBox(width: S.x2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((who['name'] ?? '').toString(), style: AppType.bodyStrong.copyWith(color: c.text)),
                Text(s.seatLine(who), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.caption.copyWith(color: c.text2)),
              ]),
            ),
            if ((who['tg_username'] ?? '').toString().isNotEmpty)
              IconButton(
                tooltip: 'Telegram',
                icon: Icon(Icons.send_rounded, color: c.accent, size: 20),
                onPressed: () => s.openUrl('https://t.me/${who['tg_username']}'),
              ),
          ]),
        const SizedBox(height: S.x3),
        SelectableText((r['note'] ?? '').toString(), style: AppType.body.copyWith(color: c.text, height: 1.4)),
        if (photo.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewer(url: photo))),
            child: ClipRRect(borderRadius: R.all(R.md), child: Image.network(photo, height: 160, fit: BoxFit.cover)),
          ),
        ],
        const SizedBox(height: S.x3),
        AppTextField(key: ValueKey('fb-reply-${r['id']}'), controller: _reply, hint: s.t('fb_reply_hint'), maxLines: 3),
        const SizedBox(height: S.x2),
        Row(children: [
          Expanded(
            child: AppButton(s.t('fb_reply'),
                key: ValueKey('fb-reply-send-${r['id']}'),
                icon: Icons.reply_rounded,
                height: 44,
                onPressed: _busy ? null : _send),
          ),
          const SizedBox(width: S.x2),
          Expanded(
            child: AppButton(s.t('rep_dismiss'), kind: BtnKind.secondary, height: 44, onPressed: () async {
              try {
                await s.api.post('/api/admin/reports/${r['id']}', {'action': 'dismiss'});
                widget.onDone();
              } on ApiError catch (e) {
                s.toast(s.errText(e));
              }
            }),
          ),
        ]),
      ]),
    );
  }
}
