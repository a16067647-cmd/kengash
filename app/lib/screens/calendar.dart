import 'package:flutter/material.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'audience.dart';
import 'channels.dart' show PresetTile, channelPresets;
import 'directory.dart' show confirmSheet;
import 'tasks.dart' show WhenPicker, fromTs, toTs, two, whenLabel;

/// Sana sarlavhasi: «Bugun», «Ertaga», «Shanba, 21 noyabr» / заголовок даты.
String dayTitle(AppState s, DateTime d) {
  final now = DateTime.now();
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (diff == 0) return s.t('today_w');
  if (diff == 1) return s.t('tomorrow');
  final days = s.lang == 'ru'
      ? ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье']
      : ['Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba', 'Yakshanba'];
  final months = s.lang == 'ru'
      ? ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря']
      : ['yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun', 'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr'];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  List<Json>? _list;
  bool _canCreate = false;
  bool _past = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _canCreate = AppScope.read(context).canGive;
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/events', query: {'when': _past ? 'past' : 'upcoming'});
      if (!mounted) return;
      setState(() {
        _list = [for (final x in r['events'] as List) (x as Map).cast<String, dynamic>()];
        _canCreate = r['can_create'] == true;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final groups = <String, List<Json>>{};
    for (final e in _list ?? const <Json>[]) {
      groups.putIfAbsent(dayTitle(s, fromTs(e['starts_at'] as num)), () => []).add(e);
    }
    return TabPage(
      title: s.t('tab_calendar'),
      onRefresh: _load,
      trailing: _canCreate
          ? AppIconButton(Icons.add_rounded, key: const ValueKey('new-event'), tooltip: s.t('event_new'), color: c.accentText,
              onPressed: () async {
              final ok = await Navigator.of(context).push<bool>(AppRoute(builder: (_) => const CreateEventScreen()));
              if (ok == true) _load();
            })
          : null,
      children: [
        if (_error != null)
          EmptyState(icon: Icons.wifi_off_rounded, title: _error!, error: true, actionLabel: s.t('retry'), onAction: _load)
        else if (_list == null)
          const SkeletonRows(count: 4)
        else if (_list!.isEmpty)
          EmptyState(
              icon: Icons.event_rounded,
              title: s.t(_past ? 'events_none_past' : 'events_none'),
              message: _past ? null : s.t('events_none_text'))
        else
          for (final g in groups.entries) ...[
            SectionHeader(g.key),
            for (final e in g.value) EventCard(event: e, onChanged: _load),
          ],
        Center(
          child: TextButton(
            key: const ValueKey('past-toggle'),
            onPressed: () {
              setState(() {
                _past = !_past;
                _list = null;
              });
              _load();
            },
            child: Text(s.t(_past ? 'events_upcoming' : 'events_past')),
          ),
        ),
        const SizedBox(height: S.navSpace - S.x6),
      ],
    );
  }
}

class EventCard extends StatelessWidget {
  final Json event;
  final VoidCallback? onChanged;
  const EventCard({super.key, required this.event, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final d = fromTs(event['starts_at'] as num);
    final rsvp = event['my_rsvp'] as String?;
    return AppCard(
      key: ValueKey('event-${event['id']}'),
      onTap: () async {
        await Navigator.of(context).push(AppRoute(builder: (_) => EventScreen(eventId: event['id'] as String)));
        onChanged?.call();
      },
      child: Row(children: [
        Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: S.x2),
          decoration: BoxDecoration(color: c.accentSoft, borderRadius: R.all(R.md)),
          child: Column(children: [
            Text('${d.day}', style: AppType.title2.copyWith(color: c.accentText, height: 1)),
            Text('${two(d.hour)}:${two(d.minute)}', style: AppType.caption.copyWith(color: c.accentText)),
          ]),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event['title'] as String,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.headline.copyWith(color: c.text)),
            if ((event['place'] ?? '').toString().isNotEmpty)
              Text('📍 ${event['place']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2)),
            const SizedBox(height: 2),
            Text('${event['yes']} ${s.t('going_count')}', style: AppType.caption.copyWith(color: c.text3)),
          ]),
        ),
        if (rsvp == 'yes') AppPill(s.t('going'), tone: Tone.yellow, small: true, icon: Icons.check_rounded),
        if (rsvp == 'no') AppPill(s.t('not_going'), small: true),
      ]),
    );
  }
}

class EventScreen extends StatefulWidget {
  final String eventId;
  const EventScreen({super.key, required this.eventId});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  Json? _e;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final e = await s.api.get('/api/events/${widget.eventId}');
      if (mounted) setState(() => _e = e);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = s.errText(e));
    }
  }

  Future<void> _rsvp(String v) async {
    final s = AppScope.read(context);
    try {
      await s.api.post('/api/events/${widget.eventId}/rsvp', {'rsvp': v});
      _load();
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final e = _e;
    if (e == null) {
      return PageShell(
          child: TabPage(children: [
        if (_error != null)
          EmptyState(icon: Icons.wifi_off_rounded, title: _error!, error: true)
        else
          const SkeletonRows(count: 4)
      ]));
    }
    final rsvp = e['my_rsvp'] as String?;
    final people = [for (final x in (e['people'] as List? ?? [])) (x as Map).cast<String, dynamic>()];
    Widget rsvpBtn(String v, String label, IconData icon) {
      final on = rsvp == v;
      return Expanded(
        child: AppButton(label,
            key: ValueKey('rsvp-$v'),
            icon: on ? icon : null,
            kind: on ? BtnKind.primary : BtnKind.secondary,
            height: 50,
            onPressed: () => _rsvp(on ? '' : v)),
      );
    }

    return PageShell(
      child: TabPage(
        title: e['title'] as String,
        onRefresh: _load,
        children: [
          AppCard(
            kind: CardKind.inset,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.event_rounded, color: c.accentText),
                const SizedBox(width: S.x2),
                Expanded(child: Text(whenLabel(s, e['starts_at'] as num), style: AppType.callout.copyWith(color: c.text))),
              ]),
              if ((e['place'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: S.x2),
                Row(children: [
                  Icon(Icons.place_rounded, color: c.accentText),
                  const SizedBox(width: S.x2),
                  Expanded(child: SelectableText(e['place'] as String, style: AppType.callout.copyWith(color: c.text))),
                ]),
              ],
              const SizedBox(height: S.x2),
              Text('${s.t('from')}: ${((e['by'] as Map?)?['name'] ?? '')}', style: AppType.footnote.copyWith(color: c.text2)),
              if ((e['description'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: S.x3),
                SelectableText(e['description'] as String, style: AppType.body.copyWith(color: c.text)),
              ],
            ]),
          ),
          if (rsvp != null)
            Row(children: [
              rsvpBtn('yes', s.t('going'), Icons.check_rounded),
              const SizedBox(width: S.x3),
              rsvpBtn('no', s.t('not_going'), Icons.close_rounded),
            ]),
          if (e['is_organizer'] == true) ...[
            AppCard(
              child: Row(children: [
                Expanded(child: _Count(label: s.t('going'), value: e['yes'] as int, color: c.yellowText)),
                Expanded(child: _Count(label: s.t('not_going'), value: e['no'] as int, color: c.danger)),
                Expanded(
                    child: _Count(
                        label: s.t('no_answer'),
                        value: (e['guests'] as int) - (e['yes'] as int) - (e['no'] as int),
                        color: c.text2)),
              ]),
            ),
            if (people.isNotEmpty)
              GroupList([
                for (final p in people)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
                    child: Row(children: [
                      AppAvatar(
                          url: s.photoUrl((p['user'] as Map)['photo']),
                          name: ((p['user'] as Map)['name'] ?? '').toString(),
                          size: 34),
                      const SizedBox(width: S.x3),
                      Expanded(
                          child: Text(((p['user'] as Map)['name'] ?? '').toString(),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body.copyWith(color: c.text))),
                      Icon(
                          p['rsvp'] == 'yes'
                              ? Icons.check_circle_rounded
                              : p['rsvp'] == 'no'
                                  ? Icons.cancel_rounded
                                  : Icons.help_outline_rounded,
                          color: p['rsvp'] == 'yes' ? c.yellow : (p['rsvp'] == 'no' ? c.danger : c.text3)),
                    ]),
                  ),
              ]),
            AppButton(s.t('event_cancel'), kind: BtnKind.danger, icon: Icons.delete_rounded, expand: true, onPressed: () async {
              if (!await confirmSheet(context, s.t('event_cancel_q'), s.t('event_cancel'))) return;
              try {
                await s.api.post('/api/events/${widget.eventId}/delete');
                if (context.mounted) Navigator.of(context).pop();
              } on ApiError catch (err) {
                s.toast(s.errText(err));
              }
            }),
          ],
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _Count({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Column(children: [
      Text('$value', style: AppType.number.copyWith(color: color)),
      Text(label, textAlign: TextAlign.center, style: AppType.caption.copyWith(color: c.text2)),
    ]);
  }
}

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _title = TextEditingController();
  final _place = TextEditingController();
  final _desc = TextEditingController();
  DateTime? _when;
  String? _preset;
  AudiencePick? _audience;
  bool _busy = false;
  String? _error;
  late final presets = channelPresets(AppScope.read(context));

  @override
  void initState() {
    super.initState();
    if (presets.isNotEmpty) {
      _preset = presets.first.$1;
      _audience = presets.first.$3;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final s = AppScope.read(context);
    if (_title.text.trim().length < 2) return setState(() => _error = s.t('err_event_title'));
    if (_when == null) return setState(() => _error = s.t('err_pick_time'));
    if (_audience == null || _audience!.isEmpty) return setState(() => _error = s.t('aud_pick'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await s.api.post('/api/events', {
        'title': _title.text.trim(),
        'place': _place.text.trim(),
        'description': _desc.text.trim(),
        'starts_at': toTs(_when!),
        ..._audience!.toJson(),
      });
      s.toast('${s.t('event_created')} · ${r['guests']} ${s.t('aud_people')}', icon: Icons.check_circle_rounded);
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
        title: s.t('event_new'),
        children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppTextField(
                  key: const ValueKey('event-title'),
                  controller: _title,
                  label: s.t('event_what'),
                  hint: s.t('event_what_hint'),
                  icon: Icons.event_rounded,
                  maxLength: 120),
              const SizedBox(height: S.x3),
              AppTextField(controller: _place, label: s.t('event_place'), icon: Icons.place_rounded, maxLength: 200),
              const SizedBox(height: S.x3),
              AppTextField(
                  controller: _desc, label: s.t('task_details'), icon: Icons.notes_rounded, maxLines: 4, maxLength: 2000),
            ]),
          ),
          SectionHeader(s.t('event_when')),
          WhenPicker(value: _when, onChanged: (d) => setState(() => _when = d)),
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
          AppButton(s.t('event_create'),
              key: const ValueKey('event-create'),
              icon: Icons.check_rounded,
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : _create),
        ],
      ),
    );
  }
}
