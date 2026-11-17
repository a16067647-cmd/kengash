import 'package:flutter/material.dart';

import '../brand.dart';
import '../main.dart' show openTool;
import '../api.dart';
import 'calendar.dart' show EventCard, dayTitle;
import 'admin_more.dart' show BroadcastScreen, FeedbackScreen;
import 'books.dart' show AdminBooksScreen, BooksShelf;
import 'onboarding.dart' show ApprovalsScreen;
import 'channels.dart' show ChannelIcon, channelTitle, openChannel, previewText, timeLabel;
import 'ideas.dart' show IdeasScreen;
import 'staff.dart' show AreaScreen;
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

/// «Bugun»: salomlashuv, bir qarashda (4 ta ko‘rsatkich), reja, Oy kitobi, kanallar.
/// Kompyuterda — ikki ustunli to‘r: bo‘sh joy qolmaydi.
/// «Сегодня»: приветствие, «с первого взгляда» (4 показателя), план, книга месяца, каналы.
/// На компьютере — сетка из двух колонок без пустот.
class TodayTab extends StatefulWidget {
  const TodayTab({super.key});

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  Json? _today;
  int? _score;
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
      if (mounted) setState(() => _today = d);
    } on ApiError catch (_) {}
    if (!s.isStudent && !s.isAdmin && s.me?['kind'] == 'coordinator') {
      try {
        final r = await s.api.get('/api/rating');
        if (mounted) setState(() => _score = ((r['me'] as Map?)?['score'] as num?)?.toInt());
      } on ApiError catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final wide = isWide(context);
    final tg = (s.me?['tg_username'] ?? '').toString();
    final header = _Greeting(wide: wide);
    final glance = _Glance(today: _today, score: _score, wide: wide);
    final plan = _TodayPlan(data: _today, onChanged: _load);
    final tools = GroupList([
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
      GroupRow(
          key: const ValueKey('quick-ideas'),
          icon: Icons.lightbulb_rounded,
          color: const Color(0xFFFFB800),
          title: s.t('ideas'),
          value: wide ? null : s.t('ideas_short'),
          onTap: () => Navigator.of(context).push(AppRoute(builder: (_) => const IdeasScreen()))),
      GroupRow(
          key: const ValueKey('quick-feedback'),
          icon: Icons.support_agent_rounded,
          color: const Color(0xFFFF9F0A),
          title: s.t('fb_title'),
          value: wide ? null : s.t('fb_short'),
          onTap: () => Navigator.of(context).push(AppRoute(builder: (_) => const FeedbackScreen()))),
      if (s.isStaff && (s.canViewArea || s.canAnnounce))
        GroupRow(
            key: const ValueKey('quick-area'),
            icon: Icons.space_dashboard_rounded,
            color: const Color(0xFF0A84D6),
            title: s.t('my_area'),
            value: wide ? null : s.t('my_area_sub'),
            onTap: () => Navigator.of(context).push(AppRoute(builder: (_) => const AreaScreen()))),
      if (s.isAdmin)
        GroupRow(
            key: const ValueKey('quick-admin'),
            icon: Icons.admin_panel_settings_rounded,
            color: const Color(0xFF34C759),
            title: s.t('admin'),
            onTap: () => openTool(context, 'admin')),
    ]);
    final noUsername = tg.isEmpty
        ? AppCard(
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
          )
        : null;

    Widget gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: S.x5), child: w);
    final List<Widget> body;
    if (wide) {
      body = [
        Appear(index: 0, child: header),
        const SizedBox(height: S.x5),
        Appear(index: 1, child: glance),
        const SizedBox(height: S.x6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (noUsername != null) gap(noUsername),
              const Appear(index: 2, child: _ApprovalsCard()),
              gap(Appear(index: 3, child: plan)),
              const Appear(index: 4, child: BooksShelf()),
            ]),
          ),
          const SizedBox(width: S.x6),
          Expanded(
            flex: 2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              gap(const Appear(index: 3, child: _ChannelsCard(recent: 5))),
              Appear(index: 4, child: tools),
            ]),
          ),
        ]),
      ];
    } else {
      body = [
        Appear(index: 0, child: header),
        const SizedBox(height: S.x4),
        gap(Appear(index: 1, child: glance)),
        if (noUsername != null) gap(noUsername),
        const Appear(index: 2, child: _ApprovalsCard()),
        gap(Appear(index: 2, child: plan)),
        gap(const Appear(index: 3, child: BooksShelf())),
        gap(const Appear(index: 4, child: _ChannelsCard(recent: 3))),
        tools,
      ];
    }
    Widget list = ListView(
      padding: EdgeInsets.fromLTRB(wide ? S.x8 : S.page, wide ? S.x8 : S.x6, wide ? S.x8 : S.page,
          MediaQuery.paddingOf(context).bottom + (wide ? S.x8 : S.navSpace)),
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      children: body,
    );
    if (wide) {
      list = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1240), child: list),
      );
    }
    return RefreshIndicator.adaptive(
      color: c.accent,
      onRefresh: () async {
        s.todayVersion++;
        await s.refreshMe();
      },
      child: list,
    );
  }
}

/// Salomlashuv: rangli plashka o‘rniga — katta, toza tipografiya fonning ustida.
/// Приветствие: вместо цветной плашки — крупная чистая типографика поверх фона.
class _Greeting extends StatelessWidget {
  final bool wide;
  const _Greeting({required this.wide});

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
    final emoji = h < 5 ? '🌙' : (h < 12 ? '☀️' : (h < 18 ? '🌤' : '🌆'));
    final first = givenName(s.myName);
    final dir = s.me?['direction'] as String?;
    final dot = dir == null ? c.accent : directionColor(dir);
    final big = (wide ? AppType.largeTitle.copyWith(fontSize: 46, height: 1.04) : AppType.largeTitle.copyWith(fontSize: 34))
        .copyWith(color: c.text, letterSpacing: -1.2);
    return Row(
      key: const ValueKey('hero'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${dayTitle(s, DateTime.now(), full: true)}'.toUpperCase(),
                key: const ValueKey('hero-date'),
                style: AppType.caption.copyWith(color: c.accentText, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
            const SizedBox(height: S.x2),
            Text('$hello $emoji', style: AppType.title3.copyWith(color: c.text2, fontWeight: FontWeight.w600)),
            ShaderMask(
              shaderCallback: (r) => LinearGradient(colors: [c.text, Color.lerp(c.text, c.accent, 0.55)!]).createShader(r),
              child: Text('$first!', maxLines: 1, overflow: TextOverflow.ellipsis, style: big.copyWith(color: kWhite)),
            ),
            const SizedBox(height: S.x3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: c.isDark ? 0.35 : 0.7),
                borderRadius: R.all(R.pill),
                border: Border.all(color: c.hairline),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(s.seatLine(s.me),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2)),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(width: S.x4),
        // oddiy halqa, nur sochmasdan / простое кольцо без свечения
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: dot, width: 2)),
          child: AppAvatar(url: s.myPhoto, name: s.myName, size: wide ? 80 : 56),
        ),
      ],
    );
  }
}

/// «Bir qarashda»: 4 ta shisha plitka — vazifalar, tadbirlar, xabarlar, reyting/kitoblar.
/// «С первого взгляда»: 4 стеклянные плитки — задачи, мероприятия, сообщения, рейтинг/книги.
class _Glance extends StatelessWidget {
  final Json? today;
  final int? score;
  final bool wide;
  const _Glance({required this.today, required this.score, required this.wide});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final tasks = (today?['tasks'] as List?)?.length;
    final events = (today?['events'] as List?)?.length;
    final review = (today?['to_review'] as num?)?.toInt() ?? 0;
    return ListenableBuilder(
      listenable: s.chat,
      builder: (context, _) {
        final unread = s.chat.channels == null ? null : s.chat.unreadTotal;
        final tiles = [
          _Tile(
            key: ValueKey(review > 0 ? 'today-review' : 'glance-tasks'),
            icon: Icons.task_alt_rounded,
            color: const Color(0xFF5B2DC9),
            value: review > 0 ? review : tasks,
            label: s.t(review > 0 ? 'to_review' : 'glance_tasks'),
            onTap: () {
              if (review > 0) s.tasksBox = 'given';
              s.go('tasks');
            },
          ),
          _Tile(
            key: const ValueKey('glance-events'),
            icon: Icons.event_rounded,
            color: const Color(0xFF0A84D6),
            value: events,
            label: s.t('glance_events'),
            onTap: () => s.go('calendar'),
          ),
          _Tile(
            key: const ValueKey('glance-messages'),
            icon: Icons.forum_rounded,
            color: const Color(0xFF00A89D),
            value: unread,
            label: s.t('glance_messages'),
            onTap: () => s.go('channels'),
          ),
          if (score != null)
            _Tile(
              key: const ValueKey('glance-rating'),
              icon: Icons.emoji_events_rounded,
              color: const Color(0xFFE8A200),
              value: score,
              signed: true,
              label: s.t('glance_rating'),
              onTap: () => openTool(context, 'rating'),
            )
          else
            _Tile(
              key: const ValueKey('glance-feedback'),
              icon: Icons.support_agent_rounded,
              color: const Color(0xFFFF7A45),
              emoji: '💬',
              label: s.t('fb_title'),
              onTap: () => Navigator.of(context).push(AppRoute(builder: (_) => const FeedbackScreen())),
            ),
        ];
        if (wide) {
          return Row(children: [
            for (final (i, t) in tiles.indexed) ...[if (i > 0) const SizedBox(width: S.x4), Expanded(child: t)],
          ]);
        }
        return Column(children: [
          Row(children: [Expanded(child: tiles[0]), const SizedBox(width: S.x3), Expanded(child: tiles[1])]),
          const SizedBox(height: S.x3),
          Row(children: [Expanded(child: tiles[2]), const SizedBox(width: S.x3), Expanded(child: tiles[3])]),
        ]);
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int? value;
  final String? emoji;
  final bool signed;
  final String label;
  final VoidCallback onTap;
  const _Tile(
      {super.key,
      required this.icon,
      required this.color,
      this.value,
      this.emoji,
      this.signed = false,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final v = value;
    final text = emoji ?? (v == null ? '–' : (signed && v > 0 ? '+$v' : '$v'));
    // Sodda: oq (qorong‘ida — sirt) karta, rangli kichik belgi / просто: карта-поверхность и маленький цветной значок
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(S.x4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: c.isDark ? 0.22 : 0.12), borderRadius: R.all(R.sm)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: S.x3),
          Text(text, style: AppType.title1.copyWith(color: c.text, height: 1.05, fontSize: emoji != null ? 26 : null)),
          const SizedBox(height: 2),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2, height: 1.2)),
      ]),
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
class _TodayPlan extends StatelessWidget {
  final Json? data;
  final VoidCallback onChanged;
  const _TodayPlan({required this.data, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final d = data;
    if (d == null) return const SkeletonRows(count: 2);
    final tasks = [for (final x in d['tasks'] as List) (x as Map).cast<String, dynamic>()];
    final events = [for (final x in d['events'] as List) (x as Map).cast<String, dynamic>()];
    final review = (d['to_review'] as num?)?.toInt() ?? 0;
    if (tasks.isEmpty && events.isEmpty) return const _CalmDay();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (tasks.isNotEmpty) ...[
        SectionHeader(s.t('today_tasks')),
        const SizedBox(height: S.x3),
        for (final t in tasks.take(3)) ...[TaskCard(task: t, onChanged: onChanged), const SizedBox(height: S.x3)],
        if (tasks.length > 3)
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => s.go('tasks'), child: Text('${s.t('all')} (${tasks.length})'))),
        const SizedBox(height: S.x2),
      ],
      if (events.isNotEmpty) ...[
        SectionHeader(s.t('today_events')),
        const SizedBox(height: S.x3),
        for (final e in events.take(3)) ...[EventCard(event: e, onChanged: onChanged), const SizedBox(height: S.x3)],
      ],
    ]);
  }
}

/// Reja bo‘sh bo‘lsa: chiroyli «tinch kun» kartasi (admin uchun — tezkor amallar).
/// План пуст: красивая карточка «спокойный день» (для админа — быстрые действия).
class _CalmDay extends StatelessWidget {
  const _CalmDay();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    Widget action(String key, IconData icon, String label, VoidCallback onTap) => Expanded(
          child: Pressable(
            key: ValueKey(key),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: S.x3, horizontal: S.x2),
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: c.isDark ? 0.4 : 0.85),
                borderRadius: R.all(R.lg),
                border: Border.all(color: c.hairline),
              ),
              child: Column(children: [
                Icon(icon, color: c.accentText),
                const SizedBox(height: 6),
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: AppType.caption.copyWith(color: c.text, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );
    return Glass(
      key: const ValueKey('calm-day'),
      color: Color.alphaBlend(c.accent.withValues(alpha: c.isDark ? 0.12 : 0.06), c.glass),
      padding: const EdgeInsets.all(S.x5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('🌿', style: TextStyle(fontSize: 34)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.t('calm_title'), style: AppType.title3.copyWith(color: c.text)),
              const SizedBox(height: 2),
              Text(s.t(s.isAdmin ? 'calm_admin' : 'calm_text'), style: AppType.subhead.copyWith(color: c.text2)),
            ]),
          ),
        ]),
        if (s.isAdmin) ...[
          const SizedBox(height: S.x4),
          Row(children: [
            action('calm-broadcast', Icons.campaign_rounded, s.t('bc_title'),
                () => Navigator.of(context).push(AppRoute(builder: (_) => const BroadcastScreen()))),
            const SizedBox(width: S.x2),
            action('calm-books', Icons.menu_book_rounded, s.t('books_title'),
                () => Navigator.of(context).push(AppRoute(builder: (_) => const AdminBooksScreen()))),
            const SizedBox(width: S.x2),
            action('calm-admin', Icons.insights_rounded, s.t('act_title'), () => openTool(context, 'admin')),
          ]),
        ],
      ]),
    );
  }
}

/// Yangi xabarlar / новые сообщения.
class _ChannelsCard extends StatelessWidget {
  final int recent;
  const _ChannelsCard({this.recent = 3});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return ListenableBuilder(
      listenable: s.chat,
      builder: (context, _) {
        final list = s.chat.channels;
        final unread = s.chat.unreadTotal;
        // avval o‘qilmaganlar, keyin so‘nggi faol kanallar / сначала непрочитанные, затем недавние
        final all = (list ?? []).where((x) => x['last'] != null).toList();
        final top = [
          ...all.where((x) => (x['unread'] as num? ?? 0) > 0 && x['muted'] != true),
          ...all.where((x) => !((x['unread'] as num? ?? 0) > 0 && x['muted'] != true)),
        ].take(recent).toList();
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
                  if ((ch['unread'] as num? ?? 0) > 0)
                    AppPill('${ch['unread']}', tone: Tone.accent, small: true)
                  else
                    Text(timeLabel(s, (ch['last'] as Map?)?['created_at'] as num?),
                        style: AppType.caption.copyWith(color: c.text3)),
                ]),
              ),
            ],
          ]),
        );
      },
    );
  }
}
