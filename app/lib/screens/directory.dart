import 'package:flutter/material.dart';

import '../api.dart';
import '../brand.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'keys.dart' show showKeysResult;

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
      if (mounted) setState(() => _seats = [for (final x in r['seats'] as List) (x as Map).cast<String, dynamic>()]);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final filled = _seats?.where((x) => x['user'] != null).length ?? 0;
    return TabPage(
      title: widget.title,
      subtitle: '${s.levelName(widget.level)} · $filled/8',
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
          for (final x in _seats!) _SeatCard(seat: x, level: widget.level, placeId: widget.placeId, onChanged: _load),
      ],
    );
  }
}

class _SeatCard extends StatelessWidget {
  final Json seat;
  final String level;
  final String placeId;
  final VoidCallback onChanged;
  const _SeatCard({required this.seat, required this.level, required this.placeId, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final dir = seat['direction'] as String;
    final user = (seat['user'] as Map?)?.cast<String, dynamic>();
    final canManage = seat['can_manage'] == true;
    final contact = (seat['contact'] ?? '').toString();
    if (user != null) {
      return UserCard(user: user, canManage: canManage, onChanged: onChanged);
    }
    return AppCard(
      key: ValueKey('seat-$dir'),
      kind: CardKind.inset,
      child: Row(children: [
        DirectionTile(dir, size: 44),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.dirName(dir), style: AppType.headline.copyWith(color: c.text)),
            Text(contact.isNotEmpty ? '${s.t('seat_empty')} · @$contact' : s.t('seat_empty'),
                style: AppType.footnote.copyWith(color: c.text3)),
          ]),
        ),
        if (canManage)
          AppIconButton(Icons.key_rounded, tooltip: s.t('make_key'), color: c.accentText, onPressed: () async {
            try {
              final r = await s.api.post('/api/keys', {
                'seats': [
                  {'level': level, 'place_id': placeId, 'direction': dir}
                ]
              });
              if (context.mounted) await showKeysResult(context, r);
            } on ApiError catch (e) {
              s.toast(s.errText(e));
            }
          }),
        if (s.isAdmin) ...[
          const SizedBox(width: S.x2),
          AppIconButton(Icons.alternate_email_rounded, tooltip: s.t('seat_contact'), onPressed: () async {
            final v = await _askContact(context, contact);
            if (v == null) return;
            try {
              await s.api
                  .post('/api/admin/seat-contact', {'level': level, 'place_id': placeId, 'direction': dir, 'tg_username': v});
              onChanged();
            } on ApiError catch (e) {
              s.toast(s.errText(e));
            }
          }),
        ],
      ]),
    );
  }
}

Future<String?> _askContact(BuildContext context, String current) {
  final ctrl = TextEditingController(text: current);
  final s = AppScope.read(context);
  return showAppSheet<String>(context, builder: (ctx) {
    final c = AppScope.of(ctx).c;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(s.t('seat_contact'), style: AppType.title3.copyWith(color: c.text)),
      const SizedBox(height: S.x1),
      Text(s.t('seat_contact_text'), style: AppType.subhead.copyWith(color: c.text2)),
      const SizedBox(height: S.x4),
      AppTextField(controller: ctrl, hint: '@username', icon: Icons.alternate_email_rounded, autocorrect: false),
      const SizedBox(height: S.x4),
      AppButton(s.t('save'), expand: true, onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim())),
    ]);
  });
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
