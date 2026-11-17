import 'package:flutter/material.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'directory.dart' show showUserSheet;
import 'pickers.dart' show pickDirection, pickDistrict;

/// Ochiq reyting: chorak boshida noldan / открытый рейтинг: с нуля каждый квартал.
/// Bitta asosiy amal — ro‘yxatni ko‘rish; daraja, tuman, yo‘nalish — ixtiyoriy filtr.
class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  Json? _data;
  String? _error;
  String? _level;
  String? _district;
  String? _direction;
  Json? _cert; // o‘tgan chorak g‘olibi bo‘lsam / если я победитель прошлого квартала

  @override
  void initState() {
    super.initState();
    _load();
    _loadCert();
  }

  Future<void> _loadCert() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/certificates/mine');
      if (mounted) setState(() => _cert = (r['certificate'] as Map?)?.cast<String, dynamic>());
    } on ApiError catch (_) {}
  }

  Future<void> _myPdf() async {
    final s = AppScope.read(context);
    s.toast(s.t('ex_preparing'), icon: Icons.hourglass_top_rounded);
    try {
      final r = await s.api.post('/api/certificates/mine/pdf', null, const Duration(seconds: 60));
      await s.openUrl(r['url'] as String);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    final q = <String, String>{
      if (_level != null) 'level': _level!,
      if (_level == 'school' && _district != null) 'place_id': _district!,
      if (_level != null && _level != 'school') 'place_id': 'andijon',
      if (_direction != null) 'direction': _direction!,
    };
    try {
      final r = await s.api.get('/api/rating', query: q);
      if (!mounted) return;
      setState(() {
        _data = r;
        _error = null;
        _level ??= r['level'] as String?;
        if (_level == 'school') _district ??= r['place_id'] as String?;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = s.errText(e));
    }
  }

  Future<void> _setLevel(String v) async {
    final s = AppScope.read(context);
    if (v == 'school' && _district == null) {
      final d = await pickDistrict(context);
      if (d == null) return;
      _district = d;
    }
    setState(() {
      _level = v;
      _data = null;
    });
    if (v == 'school' && _district == null && s.districts.isNotEmpty) _district = s.districts.first['id'] as String;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final d = _data;
    final people = [for (final x in (d?['people'] as List? ?? [])) (x as Map).cast<String, dynamic>()];
    final me = (d?['me'] as Map?)?.cast<String, dynamic>();
    final districtName = () {
      if (_district == null) return '';
      final m = s.districts.where((x) => x['id'] == _district).toList();
      return m.isEmpty ? '' : s.pick(m.first, 'name');
    }();
    return TabPage(
      title: s.t('rating'),
      subtitle: d == null ? s.t('rating_sub') : '${d['quarter']} ${s.t('rating_sub')}',
      onRefresh: _load,
      children: [
        if (_cert != null)
          AppCard(
            key: const ValueKey('my-cert'),
            kind: CardKind.tinted,
            tint: const Color(0x26E8B628),
            borderColor: const Color(0x66E8B628),
            onTap: _myPdf,
            child: Row(children: [
              const Icon(Icons.workspace_premium_rounded, color: Color(0xFFE8B628), size: 40),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_cert!['quarter']} · ${_cert!['rank']}-${s.t('rating_place')}',
                      style: AppType.headline.copyWith(color: c.text)),
                  Text(s.t('cert_mine'), style: AppType.footnote.copyWith(color: c.text2)),
                ]),
              ),
              Icon(Icons.download_rounded, color: c.accentText),
            ]),
          ),
        if (me != null && me['rated'] == true)
          AppCard(
            key: const ValueKey('my-rating'),
            kind: CardKind.tinted,
            child: Row(children: [
              Text('${me['score']}', style: AppType.largeTitle.copyWith(color: c.accentText)),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.t('rating_mine'), style: AppType.headline.copyWith(color: c.text)),
                  Text(
                      me['rank'] == null
                          ? s.t('rating_how')
                          : '${me['rank']}-${s.t('rating_place')} · ${d?['total']} ${s.t('aud_people')}',
                      style: AppType.footnote.copyWith(color: c.text2)),
                ]),
              ),
            ]),
          ),
        Segmented<String>(
          key: const ValueKey('rating-level'),
          values: const ['school', 'district', 'region'],
          labels: [s.t('lvl_school'), s.t('lvl_district'), s.t('lvl_region')],
          value: _level ?? 'school',
          onChanged: _setLevel,
        ),
        GroupList([
          if (_level == 'school')
            GroupRow(
              key: const ValueKey('rating-district'),
              icon: Icons.map_rounded,
              color: const Color(0xFF0A84D6),
              title: s.t('district'),
              value: districtName,
              onTap: () async {
                final v = await pickDistrict(context);
                if (v == null) return;
                setState(() => _district = v);
                _load();
              },
            ),
          GroupRow(
            key: const ValueKey('rating-direction'),
            icon: Icons.tune_rounded,
            color: _direction == null ? c.accent : directionColor(_direction),
            title: s.t('direction'),
            value: _direction == null ? s.t('all') : s.dirName(_direction),
            onTap: () async {
              final v = await pickDirection(context);
              if (v == null) return;
              setState(() => _direction = v == _direction ? null : v);
              _load();
            },
          ),
        ]),
        if (_error != null)
          EmptyState(icon: Icons.wifi_off_rounded, title: _error!, error: true, actionLabel: s.t('retry'), onAction: _load)
        else if (d == null)
          const SkeletonRows(count: 6)
        else if (people.isEmpty)
          EmptyState(icon: Icons.emoji_events_rounded, title: s.t('rating_none'))
        else
          GroupList([
            for (final p in people) _Row(p: p, me: (p['user'] as Map)['id'] == s.me?['id']),
          ]),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final Json p;
  final bool me;
  const _Row({required this.p, required this.me});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final u = (p['user'] as Map).cast<String, dynamic>();
    final rank = p['rank'] as int;
    final score = p['score'] as int;
    const medals = {1: Color(0xFFFFBB02), 2: Color(0xFFA7B1BE), 3: Color(0xFFCD7F32)};
    return Material(
      color: me ? c.accentSoft : Colors.transparent,
      child: InkWell(
        key: ValueKey('rank-${u['id']}'),
        onTap: () => showUserSheet(context, u),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
          child: Row(children: [
            SizedBox(
              width: 30,
              child: medals[rank] != null
                  ? Icon(Icons.emoji_events_rounded, color: medals[rank], size: 24)
                  : Text('$rank', textAlign: TextAlign.center, style: AppType.bodyStrong.copyWith(color: c.text3)),
            ),
            const SizedBox(width: S.x2),
            AppAvatar(url: s.photoUrl(u['photo']), name: (u['name'] ?? '').toString(), size: 38),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((u['name'] ?? '').toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong.copyWith(color: c.text)),
                Text(s.seatLine(u), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2)),
              ]),
            ),
            const SizedBox(width: S.x2),
            Text(score > 0 ? '+$score' : (score < 0 ? '−${-score}' : '0'),
                style: AppType.number.copyWith(
                    color: score > 0 ? const Color(0xFF1F9D55) : (score < 0 ? const Color(0xFFE5484D) : c.text3))),
          ]),
        ),
      ),
    );
  }
}
