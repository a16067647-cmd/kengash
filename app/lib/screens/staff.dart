// Xodimlar («Boshqa»): ro‘yxat, yaratish, sozlash (lavozim, hudud, vakolatlar) va xodimning «Hududim» sahifasi.
// Сотрудники («Другое»): список, создание, настройка (должность, территория, полномочия) и страница «Моя территория».
import 'package:flutter/material.dart';

import '../api.dart';
import '../sound.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'admin_more.dart' show ActivityCard, BroadcastScreen, CertificatesCard, ExportCard, ReportCard;
import 'directory.dart' show confirmSheet;
import 'pickers.dart' show pickDistrict;

const kPowers = ['view', 'plan', 'announce'];
const _powerIcons = {
  'view': Icons.visibility_rounded,
  'plan': Icons.assignment_rounded,
  'announce': Icons.campaign_rounded,
};
const _powerColors = {
  'view': Color(0xFF0A84D6),
  'plan': Color(0xFF7A4CF0),
  'announce': Color(0xFFFF9F0A),
};

/// Admin: xodimlar ro‘yxati / админ: список сотрудников.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List<Json>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/admin/staff');
      if (mounted) setState(() => _list = [for (final x in r['staff'] as List) (x as Map).cast<String, dynamic>()]);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  Future<void> _open(Json? u) async {
    final changed = await Navigator.of(context).push<bool>(AppRoute(builder: (_) => StaffEditScreen(user: u)));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return PageShell(
      child: TabPage(
        title: s.t('staff_title'),
        subtitle: s.t('staff_sub'),
        onRefresh: _load,
        trailing: AppIconButton(Icons.person_add_alt_1_rounded,
            key: const ValueKey('staff-add'), tooltip: s.t('staff_new'), color: c.accentText, onPressed: () => _open(null)),
        children: [
          if (_list == null)
            const SkeletonRows(count: 3)
          else if (_list!.isEmpty)
            EmptyState(
                icon: Icons.badge_rounded,
                title: s.t('staff_none'),
                actionLabel: s.t('staff_new'),
                onAction: () => _open(null))
          else
            GroupList([
              for (final u in _list!) _StaffRow(u: u, onTap: () => _open(u)),
            ]),
        ],
      ),
    );
  }
}

/// Yaratish yoki sozlash / создание или настройка. `user == null` — yangi (raqam bo‘yicha).
class StaffEditScreen extends StatefulWidget {
  final Json? user;
  const StaffEditScreen({super.key, this.user});

  @override
  State<StaffEditScreen> createState() => _StaffEditScreenState();
}

class _StaffEditScreenState extends State<StaffEditScreen> {
  late final _name = TextEditingController(text: (widget.user?['name'] ?? '').toString());
  final _phone = TextEditingController();
  late final _title = TextEditingController(text: (widget.user?['title'] ?? '').toString());
  late String _level = (widget.user?['level'] ?? 'district').toString();
  late String? _district = widget.user?['level'] == 'district' ? widget.user!['place_id'] as String? : null;
  late final Set<String> _powers = {
    for (final p in (widget.user?['powers'] as List? ?? (widget.user == null ? const ['view'] : const [])))
      p.toString()
  };
  bool _busy = false;

  bool get _isNew => widget.user == null;

  @override
  void initState() {
    super.initState();
    if (widget.user?['status'] == 'pending' && _powers.isEmpty) _powers.add('view');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppScope.read(context);
    if (_title.text.trim().length < 2) {
      s.toast(s.t('staff_job_hint'));
      return;
    }
    if (_level == 'district' && _district == null) {
      s.toast(s.t('err_bad_place'));
      return;
    }
    setState(() => _busy = true);
    final body = {
      'title': _title.text.trim(),
      'level': _level,
      'place_id': _level == 'region' ? 'andijon' : _district,
      'powers': [for (final p in kPowers) if (_powers.contains(p)) p],
      if (_isNew) 'name': _name.text.trim(),
      if (_isNew) 'phone': _phone.text.trim(),
    };
    try {
      await s.api.post(_isNew ? '/api/admin/staff' : '/api/admin/staff/${widget.user!['id']}', body);
      Sfx.success();
      s.toast(s.t('saved'), icon: Icons.check_circle_rounded);
      s.todayVersion++;
      if (mounted) Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final s = AppScope.read(context);
    if (!await confirmSheet(context, s.t('staff_remove_q'), s.t('staff_remove'))) return;
    try {
      await s.api.post('/api/admin/staff/${widget.user!['id']}', {'remove': true});
      s.toast(s.t('deleted'), icon: Icons.check_circle_rounded);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final districtName = () {
      final m = s.districts.where((x) => x['id'] == _district).toList();
      return m.isEmpty ? s.t('choose') : s.pick(m.first, 'name');
    }();
    final u = widget.user;
    return PageShell(
      child: TabPage(
        title: s.t(_isNew ? 'staff_new' : 'staff_edit'),
        subtitle: _isNew ? s.t('staff_phone_hint') : (u?['name'] ?? '').toString(),
        children: [
          if (_isNew) ...[
            AppTextField(
                key: const ValueKey('staff-name'),
                controller: _name,
                label: s.t('staff_name'),
                icon: Icons.person_rounded,
                maxLength: 60,
                textCapitalization: TextCapitalization.words),
            AppTextField(
                key: const ValueKey('staff-phone'),
                controller: _phone,
                label: s.t('staff_phone'),
                hint: '+998 90 123 45 67',
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                maxLength: 20),
          ] else if ((u?['phone'] ?? '').toString().isNotEmpty || (u?['tg_username'] ?? '').toString().isNotEmpty)
            AppCard(
              child: Row(children: [
                AppAvatar(url: s.photoUrl(u?['photo']), name: (u?['name'] ?? '').toString(), size: 44),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Text(
                      [if ((u?['phone'] ?? '') != '') u!['phone'], if ((u?['tg_username'] ?? '') != '') '@${u!['tg_username']}']
                          .join(' · '),
                      style: AppType.subhead.copyWith(color: c.text2)),
                ),
              ]),
            ),
          AppTextField(
              key: const ValueKey('staff-job'),
              controller: _title,
              label: s.t('staff_job'),
              hint: s.t('staff_job_hint'),
              icon: Icons.badge_rounded,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences),
          SectionHeader(s.t('staff_area')),
          Segmented<String>(
            key: const ValueKey('staff-level'),
            values: const ['district', 'region'],
            labels: [s.t('lvl_district'), s.t('staff_region')],
            value: _level,
            onChanged: (v) => setState(() => _level = v),
          ),
          if (_level == 'district')
            GroupList([
              GroupRow(
                key: const ValueKey('staff-district'),
                icon: Icons.map_rounded,
                color: const Color(0xFF0A84D6),
                title: s.t('district'),
                value: districtName,
                onTap: () async {
                  final v = await pickDistrict(context);
                  if (v != null) setState(() => _district = v);
                },
              ),
            ]),
          SectionHeader(s.t('staff_powers')),
          GroupList([
            for (final p in kPowers)
              _PowerRow(
                power: p,
                on: _powers.contains(p),
                onChanged: (v) => setState(() => v ? _powers.add(p) : _powers.remove(p)),
              ),
          ]),
          const SizedBox(height: S.x2),
          AppButton(s.t(u?['status'] == 'pending' ? 'approve' : 'save'),
              key: const ValueKey('staff-save'),
              expand: true,
              loading: _busy,
              icon: Icons.check_rounded,
              onPressed: _busy ? null : _save),
          if (!_isNew)
            AppButton(s.t(u?['status'] == 'pending' ? 'reject' : 'staff_remove'),
                key: const ValueKey('staff-remove'), expand: true, kind: BtnKind.ghost, onPressed: _remove),
        ],
      ),
    );
  }
}

class _StaffRow extends StatelessWidget {
  final Json u;
  final VoidCallback onTap;
  const _StaffRow({required this.u, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final sub = u['status'] == 'pending'
        ? '⏳ ${s.t('staff_pending')}'
        : [s.seatLine(u), if (u['linked'] == false) s.t('staff_not_linked')].join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('staff-${u['id']}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
          child: Row(children: [
            AppAvatar(url: s.photoUrl(u['photo']), name: (u['name'] ?? '').toString(), size: 40),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((u['name'] ?? '').toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong.copyWith(color: c.text)),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2)),
              ]),
            ),
            for (final p in kPowers)
              if ((u['powers'] as List? ?? []).contains(p))
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(_powerIcons[p], size: 18, color: _powerColors[p]),
                ),
            const SizedBox(width: S.x1),
            Icon(Icons.chevron_right_rounded, color: c.text3),
          ]),
        ),
      ),
    );
  }
}

class _PowerRow extends StatelessWidget {
  final String power;
  final bool on;
  final ValueChanged<bool> onChanged;
  const _PowerRow({required this.power, required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final color = _powerColors[power]!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('power-$power'),
        onTap: () => onChanged(!on),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: color, borderRadius: R.all(R.xs + 2)),
              child: Icon(_powerIcons[power], color: Colors.white, size: 19),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('pw_$power'), style: AppType.bodyStrong.copyWith(color: c.text)),
                Text(s.t('pw_${power}_sub'), style: AppType.footnote.copyWith(color: c.text2)),
              ]),
            ),
            Switch.adaptive(value: on, activeTrackColor: c.accent, onChanged: onChanged),
          ]),
        ),
      ),
    );
  }
}

/// Xodimning sahifasi: faollik (view), e’lon va Excel (announce) — faqat o‘z hududi.
/// Страница сотрудника: активность (view), рассылка и Excel (announce) — только своя территория.
class AreaScreen extends StatelessWidget {
  const AreaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return PageShell(
      child: TabPage(
        title: s.t('my_area'),
        subtitle: s.seatLine(s.me),
        children: [
          if (s.canAnnounce)
            GroupList([
              GroupRow(
                key: const ValueKey('area-broadcast'),
                icon: Icons.campaign_rounded,
                color: _powerColors['announce']!,
                title: s.t('bc_title'),
                trailing: Icon(Icons.chevron_right_rounded, color: c.text3),
                onTap: () => Navigator.of(context).push(AppRoute(builder: (_) => const BroadcastScreen())),
              ),
            ]),
          if (s.canViewArea) const ReportCard(),
          if (s.canViewArea) const CertificatesCard(),
          if (s.canViewArea) const ActivityCard(),
          if (s.canAnnounce) const ExportCard(books: false),
        ],
      ),
    );
  }
}
