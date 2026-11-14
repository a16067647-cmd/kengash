import 'package:flutter/material.dart';

import '../api.dart';
import '../brand.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Tanlash oynalari: tuman, maktab, yo‘nalish / окна выбора: район, школа, направление.

Future<String?> pickDistrict(BuildContext context) {
  final s = AppScope.read(context);
  return showAppSheet<String>(context, builder: (ctx) {
    final c = AppScope.of(ctx).c;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(s.t('pick_district'), style: AppType.title3.copyWith(color: c.text)),
      const SizedBox(height: S.x3),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          for (final d in s.districts)
            _PickRow(
              key: ValueKey('district-${d['id']}'),
              title: s.pick(d, 'name'),
              icon: d['kind'] == 'shahar' ? Icons.location_city_rounded : Icons.map_rounded,
              onTap: () => Navigator.of(ctx).pop(d['id'] as String),
            ),
        ]),
      ),
    ]);
  });
}

Future<Json?> pickSchool(BuildContext context, String districtId) {
  return showAppSheet<Json>(context, builder: (ctx) => _SchoolPicker(districtId: districtId));
}

class _SchoolPicker extends StatefulWidget {
  final String districtId;
  const _SchoolPicker({required this.districtId});

  @override
  State<_SchoolPicker> createState() => _SchoolPickerState();
}

class _SchoolPickerState extends State<_SchoolPicker> {
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
      final r = await s.api.get('/api/schools', query: {'district_id': widget.districtId});
      setState(() => _schools = [for (final x in r['schools'] as List) (x as Map).cast<String, dynamic>()]);
    } on ApiError catch (e) {
      setState(() => _error = s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final list = (_schools ?? []).where((x) => _q.isEmpty || s.pick(x, 'name').toLowerCase().contains(_q.toLowerCase())).toList();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(s.t('pick_school'), style: AppType.title3.copyWith(color: c.text)),
      Text(s.districtName(widget.districtId), style: AppType.subhead.copyWith(color: c.text2)),
      const SizedBox(height: S.x3),
      AppTextField(
          hint: s.t('search_school'),
          icon: Icons.search_rounded,
          keyboardType: TextInputType.text,
          onChanged: (v) => setState(() => _q = v.trim())),
      const SizedBox(height: S.x3),
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
        const SkeletonRows(count: 4)
      else if (_schools!.isEmpty)
        EmptyState(icon: Icons.school_rounded, title: s.t('no_schools'), message: s.t('no_schools_text'))
      else
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (final x in list)
              _PickRow(
                key: ValueKey('school-${x['number'] ?? x['id']}'),
                title: s.pick(x, 'name'),
                icon: Icons.school_rounded,
                onTap: () => Navigator.of(context).pop(x),
              ),
          ]),
        ),
    ]);
  }
}

Future<String?> pickDirection(BuildContext context, {List<String>? only}) {
  final s = AppScope.read(context);
  return showAppSheet<String>(context, builder: (ctx) {
    final c = AppScope.of(ctx).c;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(s.t('pick_direction'), style: AppType.title3.copyWith(color: c.text)),
      const SizedBox(height: S.x3),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          for (final d in s.directions)
            if (only == null || only.contains(d['id']))
              _PickRow(
                key: ValueKey('dir-${d['id']}'),
                title: s.dirName(d['id'] as String),
                leading: DirectionTile(d['id'] as String),
                onTap: () => Navigator.of(ctx).pop(d['id'] as String),
              ),
        ]),
      ),
    ]);
  });
}

class _PickRow extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback onTap;
  const _PickRow({super.key, required this.title, this.icon, this.leading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        margin: const EdgeInsets.only(bottom: S.x2),
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
        decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: R.all(R.md)),
        child: Row(children: [
          leading ?? Icon(icon, size: 22, color: c.accentText),
          const SizedBox(width: S.x3),
          Expanded(child: Text(title, style: AppType.bodyStrong.copyWith(color: c.text))),
          Icon(Icons.chevron_right_rounded, color: c.text3),
        ]),
      ),
    );
  }
}

/// Bitta o‘rin: daraja + joy + yo‘nalish / одно место: уровень + место + направление.
class Seat {
  final String level;
  final String placeId;
  final String direction;
  final String placeLabel;
  const Seat(this.level, this.placeId, this.direction, this.placeLabel);
  Json toJson() => {'level': level, 'place_id': placeId, 'direction': direction};
}
