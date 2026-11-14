import 'package:flutter/material.dart';

import '../brand.dart';
import '../main.dart' show openTool;
import 'channels.dart' show ChannelIcon, channelTitle, openChannel, previewText;
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
      onRefresh: s.refreshMe,
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
        const _ChannelsCard(),
        GroupList([
          GroupRow(
              key: const ValueKey('quick-directory'),
              icon: Icons.groups_rounded,
              color: c.accent,
              title: s.t('directory'),
              onTap: () => openTool(context, 'directory')),
          if (s.canKeys)
            GroupRow(
                key: const ValueKey('quick-keys'),
                icon: Icons.key_rounded,
                color: const Color(0xFFFF9F0A),
                title: s.t('keys'),
                value: s.t('quick_keys_short'),
                onTap: () => openTool(context, 'keys')),
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

/// Keyingi bosqichlarda to‘ladigan bo‘limlar / разделы следующих этапов.
class _ComingTab extends StatelessWidget {
  final String titleKey;
  final IconData icon;
  final String textKey;
  const _ComingTab({required this.titleKey, required this.icon, required this.textKey});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return TabPage(title: s.t(titleKey), children: [
      EmptyState(icon: icon, title: s.t('soon_title'), message: s.t(textKey)),
    ]);
  }
}

class TasksTab extends StatelessWidget {
  const TasksTab({super.key});
  @override
  Widget build(BuildContext context) =>
      const _ComingTab(titleKey: 'tab_tasks', icon: Icons.task_alt_rounded, textKey: 'soon_tasks');
}

class CalendarTab extends StatelessWidget {
  const CalendarTab({super.key});
  @override
  Widget build(BuildContext context) =>
      const _ComingTab(titleKey: 'tab_calendar', icon: Icons.event_rounded, textKey: 'soon_calendar');
}
