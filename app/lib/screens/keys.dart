import 'package:flutter/material.dart';

import '../api.dart';
import '../brand.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'pickers.dart';

/// Kalitlar: yaratilganlar ro‘yxati va yangi kalit / ключи: список и новый ключ.
class KeysScreen extends StatefulWidget {
  const KeysScreen({super.key});

  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  List<Json>? _keys;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/keys');
      if (mounted) setState(() => _keys = [for (final x in r['keys'] as List) (x as Map).cast<String, dynamic>()]);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return TabPage(
      title: s.t('keys'),
      subtitle: s.t('keys_sub'),
      onRefresh: _load,
      children: [
        AppButton(s.t('new_key'), key: const ValueKey('new-key'), icon: Icons.add_rounded, expand: true, onPressed: () async {
          await Navigator.of(context).push(AppRoute(builder: (_) => const KeyCreateScreen()));
          _load();
        }),
        AppCard(
          kind: CardKind.tinted,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_rounded, color: c.accentText, size: 20),
            const SizedBox(width: S.x3),
            Expanded(child: Text(s.t('keys_info'), style: AppType.subhead.copyWith(color: c.text))),
          ]),
        ),
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
        else if (_keys == null)
          const SkeletonRows(count: 4)
        else if (_keys!.isEmpty)
          EmptyState(icon: Icons.key_rounded, title: s.t('no_keys'), message: s.t('no_keys_text'))
        else ...[
          SectionHeader(s.t('recent_keys')),
          GroupList([for (final k in _keys!) _KeyRow(k: k, onChanged: _load)]),
        ],
      ],
    );
  }
}

class _KeyRow extends StatelessWidget {
  final Json k;
  final VoidCallback onChanged;
  const _KeyRow({required this.k, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final state = k['state'] as String;
    final (tone, label) = switch (state) {
      'active' => (Tone.accent, s.t('key_active')),
      'used' => (Tone.yellow, s.t('key_used')),
      'expired' => (Tone.neutral, s.t('key_expired')),
      _ => (Tone.danger, s.t('key_revoked')),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
      child: Row(children: [
        DirectionTile(k['direction'] as String),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.placeLine((k['place'] as Map?)?.cast<String, dynamic>()),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong.copyWith(color: c.text)),
            Text(
                state == 'used'
                    ? '${s.dirName(k['direction'] as String)} · ${k['used_name']}'
                    : '${s.dirName(k['direction'] as String)} · …${k['hint']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.footnote.copyWith(color: c.text2)),
          ]),
        ),
        const SizedBox(width: S.x2),
        AppPill(label, tone: tone, small: true),
        if (state == 'active')
          IconButton(
            tooltip: s.t('revoke'),
            icon: Icon(Icons.close_rounded, color: c.text3),
            onPressed: () async {
              try {
                await s.api.post('/api/keys/${k['id']}/revoke');
                onChanged();
              } on ApiError catch (e) {
                s.toast(s.errText(e));
              }
            },
          ),
      ]),
    );
  }
}

/// Yangi kalit(lar) yaratish / создание ключа(ей).
class KeyCreateScreen extends StatefulWidget {
  const KeyCreateScreen({super.key});

  @override
  State<KeyCreateScreen> createState() => _KeyCreateScreenState();
}

class _KeyCreateScreenState extends State<KeyCreateScreen> {
  late String _level;
  String? _district;
  List<Json>? _schools;
  final Set<String> _places = {};
  final Set<String> _dirs = {};
  bool _busy = false;

  List<String> get _levels {
    final s = AppScope.read(context);
    if (s.isAdmin) return ['school', 'district', 'region'];
    if (s.me?['level'] == 'region') return ['school', 'district'];
    return ['school'];
  }

  List<String> get _allowedDirs {
    final s = AppScope.read(context);
    final mine = s.me?['direction'] as String?;
    if (s.isAdmin || mine == 'lider') return [for (final d in s.directions) d['id'] as String];
    return [if (mine != null) mine];
  }

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context);
    _level = 'school';
    if (s.me?['level'] == 'district') _district = s.me!['place_id'] as String;
    final a = _allowedDirs;
    if (a.length == 1) _dirs.add(a.first);
    if (_district != null) _loadSchools();
  }

  Future<void> _loadSchools() async {
    final s = AppScope.read(context);
    setState(() => _schools = null);
    try {
      final r = await s.api.get('/api/schools', query: {'district_id': _district!});
      if (mounted) {
        setState(() => _schools = [
              for (final x in r['schools'] as List)
                if ((x as Map)['hidden'] != 1) x.cast<String, dynamic>()
            ]);
      }
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  Future<void> _create() async {
    final s = AppScope.read(context);
    final places = _level == 'region' ? {'andijon'} : _places;
    final seats = [
      for (final p in places)
        for (final d in _dirs) {'level': _level, 'place_id': p, 'direction': d}
    ];
    if (seats.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await s.api.post('/api/keys', {'seats': seats}, const Duration(seconds: 40));
      if (mounted) {
        await showKeysResult(context, r);
        if (mounted) Navigator.of(context).pop();
      }
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
    final levels = _levels;
    final fixedDistrict = s.me?['level'] == 'district' && !s.isAdmin;
    final count = (_level == 'region' ? 1 : _places.length) * _dirs.length;

    Widget chip(String label, bool on, VoidCallback onTap, {Widget? leading, Key? key}) => Pressable(
          key: key,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
            decoration: BoxDecoration(
              color: on ? c.accentSoft : c.surface,
              borderRadius: R.all(R.pill),
              border: Border.all(color: on ? c.accent : c.hairlineStrong, width: on ? 1.6 : 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (leading != null) ...[leading, const SizedBox(width: S.x2)],
              Text(label, style: AppType.subhead.copyWith(color: on ? c.accentText : c.text)),
            ]),
          ),
        );

    return PageShell(
      child: TabPage(
        title: s.t('new_key'),
        subtitle: s.t('new_key_sub'),
        children: [
          if (levels.length > 1)
            Segmented<String>(
              values: levels,
              labels: [for (final l in levels) s.levelName(l)],
              value: _level,
              onChanged: (v) => setState(() {
                _level = v;
                _places.clear();
              }),
            ),
          if (_level == 'school') ...[
            SectionHeader(s.t('schools')),
            if (!fixedDistrict)
              GroupList([
                GroupRow(
                  key: const ValueKey('kc-district'),
                  icon: Icons.map_rounded,
                  color: c.accent,
                  title: s.t('district'),
                  value: _district == null ? s.t('choose') : s.districtName(_district),
                  onTap: () async {
                    final d = await pickDistrict(context);
                    if (d != null) {
                      setState(() {
                        _district = d;
                        _places.clear();
                      });
                      _loadSchools();
                    }
                  },
                ),
              ]),
            if (_district != null && _schools == null) const SkeletonRows(count: 3),
            if (_schools != null && _schools!.isEmpty)
              EmptyState(icon: Icons.school_rounded, title: s.t('no_schools'), message: s.t('no_schools_text')),
            if (_schools != null && _schools!.isNotEmpty)
              Wrap(spacing: S.x2, runSpacing: S.x2, children: [
                chip(s.t('all'), _places.length == _schools!.length, () {
                  setState(() {
                    if (_places.length == _schools!.length) {
                      _places.clear();
                    } else {
                      _places
                        ..clear()
                        ..addAll(_schools!.map((x) => x['id'] as String));
                    }
                  });
                }, key: const ValueKey('all-schools')),
                for (final x in _schools!)
                  chip(s.pick(x, 'name'), _places.contains(x['id']), () {
                    setState(() => _places.contains(x['id']) ? _places.remove(x['id']) : _places.add(x['id'] as String));
                  }, key: ValueKey('chip-${x['number'] ?? x['id']}')),
              ]),
          ],
          if (_level == 'district') ...[
            SectionHeader(s.t('districts')),
            Wrap(spacing: S.x2, runSpacing: S.x2, children: [
              chip(s.t('all'), _places.length == s.districts.length, () {
                setState(() {
                  if (_places.length == s.districts.length) {
                    _places.clear();
                  } else {
                    _places
                      ..clear()
                      ..addAll(s.districts.map((x) => x['id'] as String));
                  }
                });
              }),
              for (final d in s.districts)
                chip(s.pick(d, 'name'), _places.contains(d['id']), () {
                  setState(() => _places.contains(d['id']) ? _places.remove(d['id']) : _places.add(d['id'] as String));
                }),
            ]),
          ],
          SectionHeader(s.t('directions')),
          Wrap(spacing: S.x2, runSpacing: S.x2, children: [
            for (final d in _allowedDirs)
              chip(s.dirName(d), _dirs.contains(d), () {
                setState(() => _dirs.contains(d) ? _dirs.remove(d) : _dirs.add(d));
              }, leading: DirectionTile(d, size: 20), key: ValueKey('dirchip-$d')),
          ]),
          AppButton(count == 0 ? s.t('make_keys') : '${s.t('make_keys')} · $count',
              key: const ValueKey('make-keys'),
              icon: Icons.key_rounded,
              expand: true,
              loading: _busy,
              onPressed: count == 0 || _busy ? null : _create),
        ],
      ),
    );
  }
}

/// Yaratilgan kalitlarni ko‘rsatish: nusxa olish va Telegram’da ulashish.
/// Показ созданных ключей: копировать и поделиться в Telegram.
Future<void> showKeysResult(BuildContext context, Json r) {
  final s = AppScope.read(context);
  final keys = [for (final x in (r['keys'] as List? ?? [])) (x as Map).cast<String, dynamic>()];
  final skipped = (r['skipped'] as List? ?? []).length;
  String line(Json k) =>
      '${s.dirName(k['direction'] as String)} · ${s.placeLine((k['place'] as Map?)?.cast<String, dynamic>())}: ${k['code']}';
  final all = keys.map(line).join('\n');
  return showAppSheet<void>(context, builder: (ctx) {
    final c = AppScope.of(ctx).c;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(keys.isEmpty ? s.t('no_new_keys') : s.t('keys_ready'), style: AppType.title3.copyWith(color: c.text)),
      const SizedBox(height: S.x1),
      Text(skipped > 0 ? '${s.t('keys_ready_text')} ${s.t('keys_skipped')}: $skipped' : s.t('keys_ready_text'),
          style: AppType.subhead.copyWith(color: c.text2)),
      const SizedBox(height: S.x4),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          for (final k in keys)
            Container(
              margin: const EdgeInsets.only(bottom: S.x2),
              padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x2, S.x3),
              decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: R.all(R.md)),
              child: Row(children: [
                DirectionTile(k['direction'] as String),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SelectableText(k['code'] as String, style: AppType.monoStrong.copyWith(color: c.text)),
                    Text(s.placeLine((k['place'] as Map?)?.cast<String, dynamic>()),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2)),
                  ]),
                ),
                IconButton(
                    tooltip: s.t('copy'),
                    icon: Icon(Icons.copy_rounded, color: c.accentText),
                    onPressed: () => s.copy(k['code'] as String)),
                IconButton(
                    tooltip: s.t('share_tg'),
                    icon: Icon(Icons.send_rounded, color: c.accentText),
                    onPressed: () => s.openUrl(
                        'https://t.me/share/url?url=${Uri.encodeComponent(s.t('share_url'))}&text=${Uri.encodeComponent('${s.t('share_key_text')}\n${line(k)}')}')),
              ]),
            ),
        ]),
      ),
      if (keys.length > 1) ...[
        const SizedBox(height: S.x2),
        AppButton(s.t('copy_all'),
            kind: BtnKind.secondary, icon: Icons.copy_all_rounded, expand: true, onPressed: () => s.copy(all)),
      ],
      const SizedBox(height: S.x2),
      AppButton(s.t('done'), key: const ValueKey('keys-done'), expand: true, onPressed: () => Navigator.of(ctx).pop()),
    ]);
  });
}
