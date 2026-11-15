import 'package:flutter/material.dart';

import '../brand.dart';
import '../main.dart' show openTool;
import '../api.dart';
import 'calendar.dart' show EventCard;
import 'onboarding.dart' show ApprovalsScreen;
import 'channels.dart' show ChannelIcon, channelTitle, openChannel, previewText;
import 'tasks.dart' show TaskCard;
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Ism (familiya emas): «Valiyev Ali» → «Ali», «Ali Valiyev» → «Ali».
/// Имя (не фамилия): «Валиев Али» → «Али».
String givenName(String full) {
  final w = full.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (w.isEmpty) return '';
  final surname = RegExp(r'(ov|ev|yev|ova|eva|yeva|ова|ева|ов|ев)$', caseSensitive: false);
  if (w.length >= 2 && surname.hasMatch(w[0]) && !surname.hasMatch(w[1])) return w[1];
  return w[0];
}

/// «Bugun»: salomlashuv, o‘rnim, tezkor havolalar. Vazifa va tadbirlar 3-bosqichda keladi.
/// «Сегодня»: приветствие, моё место, быстрые ссылки. Задачи и мероприятия — на 3-м этапе.
class TodayTab extends StatelessWidget {
  const TodayTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final h = DateTime.now().hour;
    final hello = h < 5
        ? s.t('hello_night')
        : h < 12
            ? s.t('hello_morning')
            : h < 18
                ? s.t('hello_day')
                : s.t('hello_evening');
    final first = givenName(s.myName);
    final tg = (s.me?['tg_username'] ?? '').toString();

    return TabPage(
      onRefresh: () async {
        s.todayVersion++;
        await s.refreshMe();
      },
      split: tg.isEmpty ? 3 : 2,
      children: [
        // Qahramon karta / карточка-герой
        Container(
          key: const ValueKey('hero'),
          decoration: BoxDecoration(
            gradient: c.heroGradient,
            borderRadius: R.all(R.xl),
            boxShadow: Shadows.glow(kViolet, c, strength: 0.7),
          ),
          foregroundDecoration: BoxDecoration(gradient: kGloss, borderRadius: R.all(R.xl)),
          padding: const EdgeInsets.all(S.x5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AppAvatar(url: s.myPhoto, name: s.myName, size: 52),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$hello, $first!', style: AppType.title2.copyWith(color: kWhite, shadows: kTextShadow)),
                  Text(s.seatLine(s.me), style: AppType.footnote.copyWith(color: Colors.white.withAlpha(0xDD))),
                ]),
              ),
              const KengashMark(size: 40, color: kWhite),
            ]),
          ]),
        ),
        if (tg.isEmpty)
          AppCard(
            kind: CardKind.tinted,
            tint: c.warningSoft,
            borderColor: c.warning.withAlpha(0x55),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.alternate_email_rounded, color: c.warning),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.t('no_username_title'), style: AppType.headline.copyWith(color: c.text)),
                  const SizedBox(height: S.x1),
                  Text(s.t('no_username_text'), style: AppType.subhead.copyWith(color: c.text2)),
                ]),
              ),
            ]),
          ),
        const _ApprovalsCard(),
        const _TodayPlan(),
        const _ChannelsCard(),
        GroupList([
          GroupRow(
              key: const ValueKey('quick-directory'),
              icon: Icons.groups_rounded,
              color: c.accent,
              title: s.isStudent ? s.t('my_school') : s.t('directory'),
              onTap: () => openTool(context, 'directory')),
          if (!s.isStudent)
            GroupRow(
                key: const ValueKey('quick-rating'),
                icon: Icons.emoji_events_rounded,
                color: const Color(0xFFFFBB02),
                title: s.t('rating'),
                onTap: () => openTool(context, 'rating')),
          if (s.isAdmin)
            GroupRow(
                key: const ValueKey('quick-admin'),
                icon: Icons.admin_panel_settings_rounded,
                color: const Color(0xFF34C759),
                title: s.t('admin'),
                onTap: () => openTool(context, 'admin')),
        ]),
      ],
    );
  }
}

/// Tasdiqlash kutayotgan arizalar (bo‘lsa) / заявки на подтверждение (если есть).
class _ApprovalsCard extends StatefulWidget {
  const _ApprovalsCard();

  @override
  State<_ApprovalsCard> createState() => _ApprovalsCardState();
}

class _ApprovalsCardState extends State<_ApprovalsCard> {
  int _n = 0;
  int _version = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    if (s.todayVersion != _version && !s.isStudent) {
      _version = s.todayVersion;
      _load();
    }
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/approvals');
      if (mounted) setState(() => _n = (r['users'] as List).length);
    } on ApiError catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    if (_n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x4),
      child: AppCard(
        key: const ValueKey('today-approvals'),
        kind: CardKind.tinted,
        tint: c.warningSoft,
        borderColor: c.warning.withAlpha(0x55),
        onTap: () async {
          await Navigator.of(context).push(AppRoute(builder: (_) => const ApprovalsScreen()));
          _load();
        },
        child: Row(children: [
          Icon(Icons.how_to_reg_rounded, color: c.warning),
          const SizedBox(width: S.x3),
          Expanded(child: Text('${s.t('approvals')}: $_n', style: AppType.headline.copyWith(color: c.text))),
          Icon(Icons.chevron_right_rounded, color: c.text3),
        ]),
      ),
    );
  }
}

/// Bugungi ishlar: tekshirish, muddati yaqin vazifalar, yaqin tadbirlar. Bo‘sh bo‘lsa — hech narsa ko‘rinmaydi.
/// Дела на сегодня: проверка, задачи со сроком, ближайшие мероприятия. Если пусто — ничего не видно.
class _TodayPlan extends StatefulWidget {
  const _TodayPlan();

  @override
  State<_TodayPlan> createState() => _TodayPlanState();
}

class _TodayPlanState extends State<_TodayPlan> {
  Json? _d;
  int _version = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    if (s.todayVersion != _version) {
      _version = s.todayVersion;
      _load();
    }
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final d = await s.api.get('/api/today');
      if (mounted) setState(() => _d = d);
    } on ApiError catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final d = _d;
    if (d == null) return const SizedBox.shrink();
    final tasks = [for (final x in d['tasks'] as List) (x as Map).cast<String, dynamic>()];
    final events = [for (final x in d['events'] as List) (x as Map).cast<String, dynamic>()];
    final review = (d['to_review'] as num?)?.toInt() ?? 0;
    if (tasks.isEmpty && events.isEmpty && review == 0) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (review > 0) ...[
        AppCard(
          key: const ValueKey('today-review'),
          kind: CardKind.tinted,
          onTap: () {
            s.tasksBox = 'given';
            s.go('tasks');
          },
          child: Row(children: [
            Icon(Icons.fact_check_rounded, color: c.accentText),
            const SizedBox(width: S.x3),
            Expanded(child: Text('${s.t('to_review')}: $review', style: AppType.headline.copyWith(color: c.text))),
            Icon(Icons.chevron_right_rounded, color: c.text3),
          ]),
        ),
        const SizedBox(height: S.x4),
      ],
      if (tasks.isNotEmpty) ...[
        SectionHeader(s.t('today_tasks')),
        const SizedBox(height: S.x3),
        for (final t in tasks.take(3)) ...[TaskCard(task: t, onChanged: _load), const SizedBox(height: S.x3)],
        if (tasks.length > 3)
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => s.go('tasks'), child: Text('${s.t('all')} (${tasks.length})'))),
        const SizedBox(height: S.x2),
      ],
      if (events.isNotEmpty) ...[
        SectionHeader(s.t('today_events')),
        const SizedBox(height: S.x3),
        for (final e in events.take(3)) ...[EventCard(event: e, onChanged: _load), const SizedBox(height: S.x3)],
      ],
    ]);
  }
}

/// Yangi xabarlar / новые сообщения.
class _ChannelsCard extends StatelessWidget {
  const _ChannelsCard();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return ListenableBuilder(
      listenable: s.chat,
      builder: (context, _) {
        final list = s.chat.channels;
        final unread = s.chat.unreadTotal;
        final top = (list ?? []).where((x) => (x['unread'] as num? ?? 0) > 0 && x['muted'] != true).take(3).toList();
        return AppCard(
          key: const ValueKey('today-channels'),
          onTap: () => s.go('channels'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconTile(Icons.forum_rounded, size: 40, bg: c.accentSoft, color: c.accentText),
              const SizedBox(width: S.x3),
              Expanded(child: Text(s.t('tab_channels'), style: AppType.headline.copyWith(color: c.text))),
              AppPill(unread == 0 ? s.t('ch_all_read') : '$unread ${s.t('ch_new_msgs')}',
                  tone: unread == 0 ? Tone.neutral : Tone.accent, small: true),
            ]),
            for (final ch in top) ...[
              const SizedBox(height: S.x3),
              Pressable(
                onTap: () => openChannel(context, ch['id'] as String),
                scale: 0.99,
                child: Row(children: [
                  ChannelIcon(ch, size: 32),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(channelTitle(s, ch),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.subhead.copyWith(color: c.text)),
                      Text(previewText(s, (ch['last'] as Map?)?.cast<String, dynamic>()),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2)),
                    ]),
                  ),
                  AppPill('${ch['unread']}', tone: Tone.accent, small: true),
                ]),
              ),
            ],
          ]),
        );
      },
    );
  }
}
