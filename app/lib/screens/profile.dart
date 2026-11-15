import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart' show openTool;
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'admin_more.dart' show FeedbackScreen;
import 'directory.dart' show confirmSheet;
import 'legal.dart';
import 'onboarding.dart' show PhotoEditor;

/// Tasdiqlash so‘zi: tutuq belgilari va bo‘shliqsiz / слово подтверждения без апострофов и пробелов.
String _norm(String v) => v.replaceAll(RegExp(r"[\s'‘’`ʻʼ]"), '').toUpperCase();

/// Profil va sozlamalar (iOS guruhlangan ro‘yxat) / профиль и настройки (сгруппированный список iOS).
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final tg = (s.me?['tg_username'] ?? '').toString();
    final phone = (s.me?['phone'] ?? '').toString();
    final wide = isWide(context);

    void openLegal(String page) => Navigator.of(context).push(AppRoute(builder: (_) => LegalScreen(page: page)));

    return TabPage(
      children: [
        Column(children: [
          const SizedBox(height: S.x2),
          const PhotoEditor(size: 110),
          const SizedBox(height: S.x3),
          Text(s.myName, textAlign: TextAlign.center, style: AppType.title2.copyWith(color: c.text)),
          const SizedBox(height: S.x1),
          Text(s.seatLine(s.me), textAlign: TextAlign.center, style: AppType.subhead.copyWith(color: c.text2)),
          const SizedBox(height: S.x1),
          Text([if (tg.isNotEmpty) '@$tg', if (phone.isNotEmpty) phone].join(' · '),
              textAlign: TextAlign.center, style: AppType.footnote.copyWith(color: c.text3)),
          const SizedBox(height: S.x2),
          Pressable(
            key: const ValueKey('edit-name'),
            onTap: () => _editName(context),
            child: Text(s.t('edit_profile'), style: AppType.callout.copyWith(color: c.accentText)),
          ),
        ]),
        if (!wide) ...[
          SectionHeader(s.t('side_tools')),
          GroupList([
            GroupRow(
                key: const ValueKey('row-directory'),
                icon: Icons.groups_rounded,
                color: c.accent,
                title: s.t('directory'),
                onTap: () => openTool(context, 'directory')),
            if (s.isAdmin)
              GroupRow(
                  key: const ValueKey('row-admin'),
                  icon: Icons.admin_panel_settings_rounded,
                  color: const Color(0xFF34C759),
                  title: s.t('admin'),
                  onTap: () => openTool(context, 'admin')),
          ]),
        ],
        SectionHeader(s.t('settings')),
        GroupList([
          GroupRow(
            key: const ValueKey('row-theme'),
            icon: Icons.dark_mode_rounded,
            color: const Color(0xFF0A84D6),
            title: s.t('appearance'),
            value: s.t(s.theme),
            onTap: () => _choose(context, s.t('appearance'), ['system', 'light', 'dark'],
                [s.t('system'), s.t('light'), s.t('dark')], s.theme, s.setTheme),
          ),
          GroupRow(
            key: const ValueKey('row-lang'),
            icon: Icons.translate_rounded,
            color: const Color(0xFF0A6CFF),
            title: s.t('language'),
            value: s.lang == 'uz' ? 'O‘zbekcha' : 'Русский',
            onTap: () => _choose(context, s.t('language'), ['uz', 'ru'], ['O‘zbekcha', 'Русский'], s.lang, s.setLang),
          ),
          GroupRow(
            key: const ValueKey('row-notify'),
            icon: Icons.notifications_active_rounded,
            color: const Color(0xFF229ED9),
            title: s.t('notify_tg'),
            trailing: Switch.adaptive(
              value: s.me?['notify_tg'] != false,
              activeTrackColor: c.accent,
              onChanged: (v) async {
                try {
                  s.setMe(await s.api.post('/api/me/notify', {'telegram': v}));
                } on ApiError catch (e) {
                  s.toast(s.errText(e));
                }
              },
            ),
          ),
          GroupRow(
            key: const ValueKey('row-sounds'),
            icon: Icons.music_note_rounded,
            color: const Color(0xFFD6409F),
            title: s.t('sounds'),
            trailing: Switch.adaptive(value: s.sounds, activeTrackColor: c.accent, onChanged: s.setSounds),
          ),
          GroupRow(
            icon: Icons.blur_on_rounded,
            color: const Color(0xFF00A89D),
            title: s.t('bg_motion'),
            trailing: Switch.adaptive(value: s.bgMotion, activeTrackColor: c.accent, onChanged: s.setBgMotion),
          ),
        ]),
        SectionHeader(s.t('info')),
        GroupList([
          GroupRow(
              key: const ValueKey('row-feedback'),
              icon: Icons.support_agent_rounded,
              color: const Color(0xFFFF9F0A),
              title: s.t('fb_title'),
              value: s.t('fb_short'),
              onTap: () => Navigator.of(context).push(AppRoute(builder: (_) => const FeedbackScreen()))),
          GroupRow(
              icon: Icons.info_rounded, color: const Color(0xFF34C759), title: s.t('about'), onTap: () => openLegal('about')),
          GroupRow(
              icon: Icons.shield_rounded,
              color: const Color(0xFF0A6CFF),
              title: s.t('privacy'),
              onTap: () => openLegal('privacy')),
          GroupRow(
              icon: Icons.description_rounded,
              color: const Color(0xFF8E8E93),
              title: s.t('terms'),
              onTap: () => openLegal('terms')),
          GroupRow(
              icon: Icons.cookie_rounded,
              color: const Color(0xFF8E8E93),
              title: s.t('cookies'),
              onTap: () => openLegal('cookies')),
        ]),
        SectionHeader(s.t('account')),
        GroupList([
          GroupRow(
              key: const ValueKey('row-logout'),
              icon: Icons.logout_rounded,
              color: const Color(0xFF8E8E93),
              title: s.t('logout'),
              onTap: s.logout),
          GroupRow(
              key: const ValueKey('row-logout-all'),
              icon: Icons.devices_other_rounded,
              color: const Color(0xFFFF9F0A),
              title: s.t('logout_all'),
              onTap: () async {
                if (!await confirmSheet(context, s.t('logout_all_q'), s.t('logout_all'))) return;
                await s.logout(everywhere: true);
              }),
          GroupRow(
              key: const ValueKey('row-delete'),
              icon: Icons.delete_forever_rounded,
              color: const Color(0xFFFF3B30),
              title: s.t('del_account'),
              onTap: () => _delete(context)),
        ]),
        const SizedBox(height: S.navSpace - S.x6),
      ],
    );
  }

  Future<void> _choose(BuildContext context, String title, List<String> values, List<String> labels, String current,
      ValueChanged<String> onPick) async {
    final v = await showAppSheet<String>(context, builder: (ctx) {
      final c = AppScope.of(ctx).c;
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: AppType.title3.copyWith(color: c.text)),
        const SizedBox(height: S.x4),
        GroupList([
          for (var i = 0; i < values.length; i++)
            GroupRow(
              key: ValueKey('opt-${values[i]}'),
              icon: values[i] == current ? Icons.check_rounded : Icons.circle_outlined,
              color: values[i] == current ? c.accent : const Color(0xFF8E8E93),
              title: labels[i],
              onTap: () => Navigator.of(ctx).pop(values[i]),
            ),
        ]),
      ]);
    });
    if (v != null) onPick(v);
  }

  Future<void> _editName(BuildContext context) async {
    final s = AppScope.read(context);
    final ctrl = TextEditingController(text: s.myName);
    await showAppSheet<void>(context, builder: (ctx) {
      final c = AppScope.of(ctx).c;
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('edit_profile'), style: AppType.title3.copyWith(color: c.text)),
        const SizedBox(height: S.x4),
        AppTextField(controller: ctrl, label: s.t('full_name'), icon: Icons.person_rounded, maxLength: 60),
        const SizedBox(height: S.x4),
        AppButton(s.t('save'), key: const ValueKey('name-save'), expand: true, onPressed: () async {
          try {
            s.setMe(await s.api.post('/api/me/profile', {'name': ctrl.text.trim()}));
            if (ctx.mounted) Navigator.of(ctx).pop();
            s.toast(s.t('saved'), icon: Icons.check_circle_rounded);
          } on ApiError catch (e) {
            s.toast(s.errText(e));
          }
        }),
      ]);
    });
  }

  Future<void> _delete(BuildContext context) async {
    final s = AppScope.read(context);
    final ctrl = TextEditingController();
    await showAppSheet<void>(context, builder: (ctx) {
      final c = AppScope.of(ctx).c;
      final word = s.t('del_word');
      return StatefulBuilder(builder: (ctx, set) {
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: IconTile(Icons.delete_forever_rounded, size: 60, circle: true, bg: c.dangerSoft, color: c.danger)),
          const SizedBox(height: S.x4),
          Text(s.t('del_account'), textAlign: TextAlign.center, style: AppType.title3.copyWith(color: c.text)),
          const SizedBox(height: S.x2),
          Text(s.t('del_q'), textAlign: TextAlign.center, style: AppType.subhead.copyWith(color: c.text2)),
          const SizedBox(height: S.x4),
          AppTextField(
            key: const ValueKey('del-field'),
            controller: ctrl,
            label: '${s.t('del_type')} $word',
            hint: word,
            icon: Icons.keyboard_rounded,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => set(() {}),
          ),
          const SizedBox(height: S.x4),
          AppButton(s.t('del_btn'),
              key: const ValueKey('del-confirm'),
              kind: BtnKind.danger,
              expand: true,
              onPressed: _norm(ctrl.text) != _norm(word)
                  ? null
                  : () async {
                      try {
                        await s.api.post('/api/me/delete', {'confirm': ctrl.text.trim()});
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        s.toast(s.t('del_done'));
                        await s.logout();
                      } on ApiError catch (e) {
                        s.toast(s.errText(e));
                      }
                    }),
        ]);
      });
    });
  }
}
