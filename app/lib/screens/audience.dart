import 'package:flutter/material.dart';

import '../api.dart';
import '../brand.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Kimlarga: guruhlar (daraja + tuman/maktab + yo‘nalish) va alohida odamlar.
/// Кому: группы (уровень + район/школа + направление) и отдельные люди.
/// Server faqat ruxsat etilganlarni qo‘shadi / сервер добавит только разрешённых.
class AudiencePick {
  final List<Json> groups;
  final List<Json> users;
  const AudiencePick(this.groups, this.users);

  bool get isEmpty => groups.isEmpty && users.isEmpty;

  Json toJson() => {
        'audience': groups,
        'user_ids': [for (final u in users) u['id']]
      };

  String groupLabel(AppState s, Json g) {
    final level = s.levelName(g['level'] as String?);
    final dids = (g['district_ids'] as List?)?.cast<String>() ?? const [];
    final sch = (g['school_names'] as List?)?.cast<String>() ?? const [];
    final dirs = (g['directions'] as List?)?.cast<String>() ?? const [];
    final where = sch.isNotEmpty
        ? sch.join(', ')
        : dids.isEmpty
            ? s.t('aud_all_places')
            : dids.map(s.districtName).join(', ');
    final what = dirs.isEmpty ? s.t('aud_all_dirs') : dirs.map(s.dirName).join(', ');
    return '$level · $where · $what';
  }

  String label(AppState s) => [
        ...groups.map((g) => groupLabel(s, g)),
        if (users.isNotEmpty) '${users.length} ${s.t('aud_people')}',
      ].join('\n');
}

class AudienceScreen extends StatefulWidget {
  final String title;
  final AudiencePick? initial;
  const AudienceScreen({super.key, required this.title, this.initial});

  @override
  State<AudienceScreen> createState() => _AudienceScreenState();
}

class _AudienceScreenState extends State<AudienceScreen> {
  late final List<Json> _groups = [...?widget.initial?.groups];
  late final List<Json> _users = [...?widget.initial?.users];
  late String _level;
  final Set<String> _districts = {};
  final Set<String> _schools = {};
  final Map<String, String> _schoolNames = {};
  final Set<String> _dirs = {};
  List<Json>? _schoolList;
  List<Json>? _found;

  List<String> get _levels {
    final s = AppScope.read(context);
    if (s.isAdmin) return ['school', 'district', 'region'];
    if (s.me?['level'] == 'region') return ['school', 'district', 'region'];
    return ['school', 'district'];
  }

  String? get _fixedDistrict {
    final s = AppScope.read(context);
    return s.me?['level'] == 'district' && !s.isAdmin ? s.me!['place_id'] as String : null;
  }

  @override
  void initState() {
    super.initState();
    _level = 'school';
    final fixed = _fixedDistrict;
    if (fixed != null) {
      _districts.add(fixed);
      _loadSchools(fixed);
    }
  }

  Future<void> _loadSchools(String did) async {
    final s = AppScope.read(context);
    setState(() => _schoolList = null);
    try {
      final r = await s.api.get('/api/schools', query: {'district_id': did});
      if (mounted) {
        setState(() => _schoolList = [
              for (final x in r['schools'] as List)
                if ((x as Map)['hidden'] != 1) x.cast<String, dynamic>()
            ]);
      }
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  void _addGroup() {
    final g = <String, dynamic>{
      'level': _level,
      if (_level != 'region' && _districts.isNotEmpty) 'district_ids': _districts.toList(),
      if (_level == 'school' && _schools.isNotEmpty) 'school_ids': _schools.toList(),
      if (_level == 'school' && _schools.isNotEmpty) 'school_names': [for (final id in _schools) _schoolNames[id] ?? id],
      if (_dirs.isNotEmpty) 'directions': _dirs.toList(),
    };
    setState(() {
      _groups.add(g);
      _schools.clear();
      _dirs.clear();
    });
  }

  Future<void> _search(String q) async {
    final s = AppScope.read(context);
    if (q.trim().length < 2) {
      setState(() => _found = null);
      return;
    }
    try {
      final r = await s.api.get('/api/users/search', query: {'q': q.trim()});
      if (mounted) setState(() => _found = [for (final x in r['users'] as List) (x as Map).cast<String, dynamic>()]);
    } on ApiError catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final fixed = _fixedDistrict;
    final pick = AudiencePick(_groups, _users);

    Widget chip(String label, bool on, VoidCallback onTap, {Widget? leading, Key? key}) => Pressable(
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
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (leading != null) ...[leading, const SizedBox(width: S.x2)],
              Text(label, style: AppType.subhead.copyWith(color: on ? c.accentText : c.text)),
            ]),
          ),
        );

    return PageShell(
      child: TabPage(
        title: widget.title,
        subtitle: s.t('aud_sub'),
        children: [
          if (_groups.isNotEmpty || _users.isNotEmpty)
            AppCard(
              kind: CardKind.tinted,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(s.t('aud_selected'), style: AppType.headline.copyWith(color: c.text)),
                const SizedBox(height: S.x2),
                for (final (i, g) in _groups.indexed)
                  Row(children: [
                    Icon(Icons.groups_rounded, size: 18, color: c.accentText),
                    const SizedBox(width: S.x2),
                    Expanded(child: Text(pick.groupLabel(s, g), style: AppType.subhead.copyWith(color: c.text))),
                    IconButton(
                        icon: Icon(Icons.close_rounded, color: c.text3, size: 20),
                        onPressed: () => setState(() => _groups.removeAt(i))),
                  ]),
                for (final u in [..._users])
                  Row(children: [
                    Icon(Icons.person_rounded, size: 18, color: c.accentText),
                    const SizedBox(width: S.x2),
                    Expanded(child: Text((u['name'] ?? '').toString(), style: AppType.subhead.copyWith(color: c.text))),
                    IconButton(
                        icon: Icon(Icons.close_rounded, color: c.text3, size: 20),
                        onPressed: () => setState(() => _users.remove(u))),
                  ]),
              ]),
            ),
          SectionHeader(s.t('aud_group')),
          Segmented<String>(
            values: _levels,
            labels: [for (final l in _levels) s.levelName(l)],
            value: _level,
            onChanged: (v) => setState(() {
              _level = v;
              _schools.clear();
              if (fixed == null) _districts.clear();
            }),
          ),
          if (_level != 'region') ...[
            Text(s.t('districts'), style: AppType.footnote.copyWith(color: c.text2)),
            Wrap(spacing: S.x2, runSpacing: S.x2, children: [
              if (fixed != null && _level == 'school')
                chip(s.districtName(fixed), true, () {})
              else ...[
                chip(s.t('all'), _districts.isEmpty, () => setState(() => _districts.clear()), key: const ValueKey('aud-all-d')),
                for (final d in s.districts)
                  chip(s.pick(d, 'name'), _districts.contains(d['id']), () {
                    setState(() {
                      _districts.contains(d['id']) ? _districts.remove(d['id']) : _districts.add(d['id'] as String);
                      _schools.clear();
                    });
                    if (_level == 'school' && _districts.length == 1) _loadSchools(_districts.first);
                  }, key: ValueKey('aud-d-${d['id']}')),
              ],
            ]),
          ],
          if (_level == 'school' && _districts.length == 1) ...[
            Text(s.t('schools'), style: AppType.footnote.copyWith(color: c.text2)),
            if (_schoolList == null)
              const SkeletonRows(count: 2)
            else
              Wrap(spacing: S.x2, runSpacing: S.x2, children: [
                chip(s.t('all'), _schools.isEmpty, () => setState(() => _schools.clear())),
                for (final x in _schoolList!)
                  chip(s.pick(x, 'name'), _schools.contains(x['id']), () {
                    setState(() {
                      final id = x['id'] as String;
                      _schoolNames[id] = s.pick(x, 'name');
                      _schools.contains(id) ? _schools.remove(id) : _schools.add(id);
                    });
                  }),
              ]),
          ],
          Text(s.t('directions'), style: AppType.footnote.copyWith(color: c.text2)),
          Wrap(spacing: S.x2, runSpacing: S.x2, children: [
            chip(s.t('all'), _dirs.isEmpty, () => setState(() => _dirs.clear())),
            for (final d in s.directions)
              chip(s.dirName(d['id'] as String), _dirs.contains(d['id']), () {
                setState(() => _dirs.contains(d['id']) ? _dirs.remove(d['id']) : _dirs.add(d['id'] as String));
              }, leading: DirectionTile(d['id'] as String, size: 20), key: ValueKey('aud-dir-${d['id']}')),
          ]),
          AppButton(s.t('aud_add_group'),
              key: const ValueKey('aud-add'),
              kind: BtnKind.secondary,
              icon: Icons.add_rounded,
              expand: true,
              onPressed: _addGroup),
          SectionHeader(s.t('aud_person')),
          AppTextField(hint: s.t('search_people'), icon: Icons.search_rounded, onChanged: _search),
          if (_found != null)
            GroupList([
              for (final u in _found!)
                GroupRow(
                  icon: _users.any((x) => x['id'] == u['id']) ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
                  color: _users.any((x) => x['id'] == u['id']) ? c.accent : const Color(0xFF8E8E93),
                  title: (u['name'] ?? '').toString(),
                  value: s.dirName(u['direction'] as String?),
                  onTap: () => setState(() {
                    final i = _users.indexWhere((x) => x['id'] == u['id']);
                    i >= 0 ? _users.removeAt(i) : _users.add(u);
                  }),
                ),
            ]),
          Text(s.t('aud_note'), style: AppType.footnote.copyWith(color: c.text3)),
          AppButton(s.t('done'), key: const ValueKey('aud-done'), expand: true, onPressed: () {
            // Tanlangan, lekin qo‘shilmagan guruhni ham olamiz / берём и выбранную, но не добавленную группу
            if (_groups.isEmpty && _users.isEmpty) _addGroup();
            Navigator.of(context).pop(AudiencePick(_groups, _users));
          }),
        ],
      ),
    );
  }
}
