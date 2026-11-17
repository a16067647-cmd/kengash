import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../brand.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'portfolio.dart' show PortfolioScreen;

/// Koordinatorlar: viloyat → tumanlar → maktablar, har birida 8 o‘rin.
/// Координаторы: область → районы → школы, в каждом 8 мест.
class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  String _q = '';
  List<Json>? _found;
  bool _searching = false;

  Future<void> _search(String q) async {
    final s = AppScope.read(context);
    _q = q.trim();
    if (_q.length < 2) {
      setState(() => _found = null);
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await s.api.get('/api/users/search', query: {'q': _q});
      if (mounted && _q == q.trim()) {
        setState(() => _found = [for (final x in r['users'] as List) (x as Map).cast<String, dynamic>()]);
      }
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final me = s.me;
    if (s.isStudent && me?['place_id'] != null) {
      final place = (me!['place'] as Map?)?.cast<String, dynamic>();
      return SeatsView(level: 'school', placeId: me['place_id'] as String, title: place == null ? s.t('my_school') : s.pick(place, 'name'));
    }
    final myDistrict = me?['level'] == 'district' ? me!['place_id'] : (me?['place'] as Map?)?['district_id'];
    return TabPage(
      title: s.t('directory'),
      subtitle: s.t('directory_sub'),
      children: [
        AppTextField(
          key: const ValueKey('dir-search'),
          hint: s.t('search_people'),
          icon: Icons.search_rounded,
          onChanged: _search,
        ),
        if (_found != null) ...[
          if (_searching) const SkeletonRows(count: 2),
          if (_found!.isEmpty && !_searching) EmptyState(icon: Icons.person_search_rounded, title: s.t('nothing_found')),
          for (final u in _found!) UserCard(user: u),
        ] else ...[
          _PlaceCard(
            key: const ValueKey('place-region'),
            icon: Icons.account_balance_rounded,
            title: s.regionName('andijon'),
            subtitle: s.t('region_team'),
            highlight: true,
            onTap: () => openPlace(context, 'region', 'andijon', s.regionName('andijon')),
          ),
          SectionHeader(s.t('districts')),
          GroupList([
            for (final d in s.districts)
              GroupRow(
                key: ValueKey('dist-${d['id']}'),
                icon: d['kind'] == 'shahar' ? Icons.location_city_rounded : Icons.map_rounded,
                color: d['id'] == myDistrict ? c.accent : const Color(0xFF0A84D6),
                title: s.pick(d, 'name'),
                onTap: () => Navigator.of(context).push(AppRoute(builder: (_) => DistrictScreen(district: d))),
              ),
          ]),
        ],
      ],
    );
  }
}

void openPlace(BuildContext context, String level, String placeId, String title) {
  Navigator.of(context).push(AppRoute(builder: (_) => PageShell(child: SeatsView(level: level, placeId: placeId, title: title))));
}

class _PlaceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlight;
  final VoidCallback onTap;
  const _PlaceCard(
      {super.key, required this.icon, required this.title, required this.subtitle, this.highlight = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final fg = highlight ? kWhite : c.text;
    return AppCard(
      onTap: onTap,
      gradient: highlight ? c.heroGradient : null,
      shadow: highlight ? Shadows.glow(kViolet, c, strength: 0.6) : null,
      child: Row(children: [
        Icon(icon, color: fg, size: 28),
        const SizedBox(width: S.x4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.headline.copyWith(color: fg)),
            Text(subtitle, style: AppType.footnote.copyWith(color: highlight ? Colors.white70 : c.text2)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: highlight ? Colors.white70 : c.text3),
      ]),
    );
  }
}

/// Tuman: tuman jamoasi + maktablar ro‘yxati / район: команда района + список школ.
class DistrictScreen extends StatefulWidget {
  final Json district;
  const DistrictScreen({super.key, required this.district});

  @override
  State<DistrictScreen> createState() => _DistrictScreenState();
}

class _DistrictScreenState extends State<DistrictScreen> {
  List<Json>? _schools;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/schools', query: {'district_id': widget.district['id'] as String});
      if (mounted) setState(() => _schools = [for (final x in r['schools'] as List) (x as Map).cast<String, dynamic>()]);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final name = s.pick(widget.district, 'name');
    final list = (_schools ?? [])
        .where((x) => x['hidden'] != 1 && (_q.isEmpty || s.pick(x, 'name').toLowerCase().contains(_q.toLowerCase())))
        .toList();
    return PageShell(
      child: TabPage(
        title: name,
        onRefresh: _load,
        children: [
          _PlaceCard(
            key: const ValueKey('district-team'),
            icon: Icons.groups_rounded,
            title: s.t('district_team'),
            subtitle: name,
            highlight: true,
            onTap: () => openPlace(context, 'district', widget.district['id'] as String, name),
          ),
          SectionHeader(s.t('schools'), trailing: _schools == null ? null : AppPill('${list.length}')),
          AppTextField(hint: s.t('search_school'), icon: Icons.search_rounded, onChanged: (v) => setState(() => _q = v.trim())),
          if (_error != null)
            EmptyState(
                icon: Icons.wifi_off_rounded,
                title: _error!,
                error: true,
                actionLabel: s.t('retry'),
                onAction: () {
                  setState(() => _error = null);
                  _load();
                })
          else if (_schools == null)
            const SkeletonRows(count: 5)
          else if (list.isEmpty)
            EmptyState(icon: Icons.school_rounded, title: s.t('no_schools'), message: s.t('no_schools_text'))
          else
            GroupList([
              for (final x in list)
                GroupRow(
                  key: ValueKey('sch-${x['number'] ?? x['id']}'),
                  icon: Icons.school_rounded,
                  color: c.accent,
                  title: s.pick(x, 'name'),
                  value: '${x['filled']}/8',
                  onTap: () => openPlace(context, 'school', x['id'] as String, '${s.pick(x, 'name')} · $name'),
                ),
            ]),
        ],
      ),
    );
  }
}

/// Bir joyning 8 o‘rni / 8 мест одного места.
class SeatsView extends StatefulWidget {
  final String level;
  final String placeId;
  final String title;
  const SeatsView({super.key, required this.level, required this.placeId, required this.title});

  @override
  State<SeatsView> createState() => _SeatsViewState();
}

class _SeatsViewState extends State<SeatsView> {
  List<Json>? _seats;
  int _students = 0;
  bool _canSeeStudents = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/seats', query: {'level': widget.level, 'place_id': widget.placeId});
      if (mounted) {
        setState(() {
          _seats = [for (final x in r['seats'] as List) (x as Map).cast<String, dynamic>()];
          _students = (r['students'] as num?)?.toInt() ?? 0;
          _canSeeStudents = r['can_see_students'] == true;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final filled = _seats?.where((x) => x['user'] != null).length ?? 0;
    return TabPage(
      title: widget.title,
      subtitle: '${s.levelName(widget.level)} · $filled/${_seats?.length ?? 8}',
      onRefresh: _load,
      children: [
        if (_error != null)
          EmptyState(
              icon: Icons.wifi_off_rounded,
              title: _error!,
              error: true,
              actionLabel: s.t('retry'),
              onAction: () {
                setState(() => _error = null);
                _load();
              })
        else if (_seats == null)
          const SkeletonRows(count: 6)
        else
        ...[
          if (_canSeeStudents)
            AppCard(
              key: const ValueKey('students-card'),
              kind: CardKind.tinted,
              onTap: () => Navigator.of(context)
                  .push(AppRoute(builder: (_) => StudentsScreen(schoolId: widget.placeId, title: widget.title))),
              child: Row(children: [
                Icon(Icons.groups_2_rounded, color: c.accentText),
                const SizedBox(width: S.x3),
                Expanded(child: Text('${s.t('students')}: $_students', style: AppType.headline.copyWith(color: c.text))),
                Icon(Icons.chevron_right_rounded, color: c.text3),
              ]),
            ),
          for (final x in _seats!) _SeatCard(seat: x, onChanged: _load),
        ],
      ],
    );
  }
}

class _SeatCard extends StatelessWidget {
  final Json seat;
  final VoidCallback onChanged;
  const _SeatCard({required this.seat, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final dir = seat['direction'] as String;
    final user = (seat['user'] as Map?)?.cast<String, dynamic>();
    if (user != null) return UserCard(user: user, canManage: seat['can_manage'] == true, onChanged: onChanged);
    return AppCard(
      key: ValueKey('seat-$dir'),
      kind: CardKind.inset,
      child: Row(children: [
        DirectionTile(dir, size: 44),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.dirName(dir), style: AppType.headline.copyWith(color: c.text)),
            Text(s.t('seat_empty'), style: AppType.footnote.copyWith(color: c.text3)),
          ]),
        ),
      ]),
    );
  }
}

/// Maktab o‘quvchilari (sinflar bo‘yicha) / ученики школы (по классам).
/// O‘quvchilarni taklif qilish: Telegram’da guruhni tanlash oynasi ochiladi, havola nusxalanadi.
/// Пригласить учеников: открывается выбор чата в Telegram, ссылка копируется.
Future<void> inviteStudents(BuildContext context, String schoolId) async {
  final s = AppScope.read(context);
  try {
    final r = await s.api.get('/api/schools/$schoolId/invite');
    await Clipboard.setData(ClipboardData(text: r['url'] as String));
    s.toast(s.t('invite_copied'), icon: Icons.link_rounded);
    await s.openUrl(r['share_url'] as String);
  } on ApiError catch (e) {
    s.toast(s.errText(e));
  }
}

class StudentsScreen extends StatefulWidget {
  final String schoolId;
  final String title;
  const StudentsScreen({super.key, required this.schoolId, required this.title});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  List<Json>? _list;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/schools/${widget.schoolId}/students');
      if (mounted) setState(() => _list = [for (final x in r['students'] as List) (x as Map).cast<String, dynamic>()]);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final list = (_list ?? []).where((u) => _q.isEmpty || (u['name'] ?? '').toString().toLowerCase().contains(_q)).toList();
    final byClass = <String, List<Json>>{};
    for (final u in list) {
      byClass.putIfAbsent((u['class_name'] ?? '').toString(), () => []).add(u);
    }
    return PageShell(
      child: TabPage(
        title: s.t('students'),
        subtitle: '${widget.title} · ${_list?.length ?? 0}',
        onRefresh: _load,
        children: [
          AppButton(s.t('invite_students'),
              key: const ValueKey('invite-students'),
              icon: Icons.person_add_alt_1_rounded,
              expand: true,
              onPressed: () => inviteStudents(context, widget.schoolId)),
          AppTextField(hint: s.t('search_people'), icon: Icons.search_rounded, onChanged: (v) => setState(() => _q = v.trim().toLowerCase())),
          if (_list == null)
            const SkeletonRows(count: 5)
          else if (_list!.isEmpty)
            EmptyState(icon: Icons.school_rounded, title: s.t('students_none'), message: s.t('students_none_text'))
          else
            for (final e in byClass.entries) ...[
              SectionHeader(e.key.isEmpty ? '—' : '${e.key} · ${e.value.length}'),
              GroupList([
                for (final u in e.value)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => showUserSheet(context, u),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
                        child: Row(children: [
                          AppAvatar(url: s.photoUrl(u['photo']), name: (u['name'] ?? '').toString(), size: 36),
                          const SizedBox(width: S.x3),
                          Expanded(child: Text((u['name'] ?? '').toString(), style: AppType.body.copyWith(color: c.text))),
                          if ((u['phone'] ?? '').toString().isNotEmpty)
                            Text(u['phone'] as String, style: AppType.footnote.copyWith(color: c.text3)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ],
        ],
      ),
    );
  }
}

/// Koordinator kartasi: surat, ism, o‘rin, Telegram / карточка координатора.
class UserCard extends StatelessWidget {
  final Json user;
  final bool canManage;
  final VoidCallback? onChanged;
  const UserCard({super.key, required this.user, this.canManage = false, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final tg = (user['tg_username'] ?? '').toString();
    final dir = user['direction'] as String?;
    return AppCard(
      key: ValueKey('user-${user['id']}'),
      onTap: () => showUserSheet(context, user, canManage: canManage, onChanged: onChanged),
      child: Row(children: [
        Stack(clipBehavior: Clip.none, children: [
          AppAvatar(url: s.photoUrl(user['photo']), name: (user['name'] ?? '').toString(), size: 48),
          if (dir != null) Positioned(right: -4, bottom: -4, child: DirectionTile(dir, size: 22)),
        ]),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((user['name'] ?? '').toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.headline.copyWith(color: c.text)),
            Text(s.seatLine(user),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2)),
          ]),
        ),
        if (tg.isNotEmpty) ...[
          const SizedBox(width: S.x2),
          AppIconButton(Icons.send_rounded, tooltip: s.t('write_tg'), color: c.accentText, onPressed: () => s.openTelegram(tg)),
        ],
      ]),
    );
  }
}

Future<void> showUserSheet(BuildContext context, Json user, {bool canManage = false, VoidCallback? onChanged}) {
  final s = AppScope.read(context);
  return showAppSheet<void>(context, builder: (ctx) {
    final c = AppScope.of(ctx).c;
    final tg = (user['tg_username'] ?? '').toString();
    final phone = (user['phone'] ?? '').toString();
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: AppAvatar(url: s.photoUrl(user['photo']), name: (user['name'] ?? '').toString(), size: 96, ring: true)),
        const SizedBox(height: S.x3),
        Text((user['name'] ?? '').toString(), textAlign: TextAlign.center, style: AppType.title2.copyWith(color: c.text)),
        const SizedBox(height: S.x1),
        Text(s.seatLine(user), textAlign: TextAlign.center, style: AppType.subhead.copyWith(color: c.text2)),
        const SizedBox(height: S.x5),
        if (user['role'] != 'admin' && user['kind'] != 'staff' && user['id'] != s.me?['id']) ...[
          AppButton(s.t('pf_title'),
              key: const ValueKey('user-portfolio'),
              kind: BtnKind.secondary,
              icon: Icons.route_rounded,
              expand: true,
              onPressed: () => Navigator.of(ctx).push(AppRoute(builder: (_) => PortfolioScreen(userId: user['id'] as String)))),
          const SizedBox(height: S.x3),
        ],
        if (tg.isNotEmpty)
          AppButton(s.t('write_tg'),
              key: const ValueKey('sheet-tg'), icon: Icons.send_rounded, expand: true, onPressed: () => s.openTelegram(tg))
        else
          AppCard(kind: CardKind.inset, child: Text(s.t('no_tg'), style: AppType.subhead.copyWith(color: c.text2))),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          AppButton('${s.t('call')} $phone',
              kind: BtnKind.secondary, icon: Icons.call_rounded, expand: true, onPressed: () => s.openUrl('tel:$phone')),
        ],
        if (canManage && user['level'] != null) ...[
          const SizedBox(height: S.x3),
          AppButton(s.t('free_seat'), kind: BtnKind.danger, icon: Icons.person_remove_rounded, expand: true, onPressed: () async {
            final ok = await confirmSheet(ctx, s.t('free_seat_q'), s.t('free_seat'));
            if (!ok) return;
            try {
              await s.api.post(
                  '/api/seats/free', {'level': user['level'], 'place_id': user['place_id'], 'direction': user['direction']});
              if (ctx.mounted) Navigator.of(ctx).pop();
              s.toast(s.t('seat_freed'), icon: Icons.check_circle_rounded);
              onChanged?.call();
            } on ApiError catch (e) {
              s.toast(s.errText(e));
            }
          }),
        ],
      ]),
    );
  });
}

/// Tasdiqlash oynasi / окно подтверждения.
Future<bool> confirmSheet(BuildContext context, String text, String action, {bool danger = true}) async {
  final s = AppScope.read(context);
  final r = await showAppSheet<bool>(context, builder: (ctx) {
    final c = AppScope.of(ctx).c;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(text, textAlign: TextAlign.center, style: AppType.headline.copyWith(color: c.text)),
      const SizedBox(height: S.x5),
      AppButton(action,
          key: const ValueKey('confirm-yes'),
          kind: danger ? BtnKind.danger : BtnKind.primary,
          expand: true,
          onPressed: () => Navigator.of(ctx).pop(true)),
      const SizedBox(height: S.x2),
      AppButton(s.t('cancel'), kind: BtnKind.ghost, expand: true, onPressed: () => Navigator.of(ctx).pop(false)),
    ]);
  });
  return r == true;
}
