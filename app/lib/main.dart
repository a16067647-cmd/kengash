import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'config.dart';
import 'motion_lab.dart' show MotionLevel;
import 'screens/admin.dart';
import 'screens/auth.dart';
import 'screens/channels.dart';
import 'screens/directory.dart';
import 'screens/intro.dart';
import 'screens/keys.dart';
import 'screens/onboarding.dart';
import 'screens/profile.dart';
import 'screens/today.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  runApp(KengashApp(state: state));
  state.init();
}

class KengashApp extends StatefulWidget {
  final AppState state;
  const KengashApp({super.key, required this.state});

  @override
  State<KengashApp> createState() => _KengashAppState();
}

class _KengashAppState extends State<KengashApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    widget.state.setPlatformBrightness(WidgetsBinding.instance.platformDispatcher.platformBrightness);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = widget.state;
    if (state == AppLifecycleState.resumed && s.loggedIn) s.refreshMe();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: Builder(builder: (context) {
        final s = AppScope.of(context);
        return MaterialApp(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          navigatorKey: s.navigatorKey,
          theme: buildTheme(kLight),
          darkTheme: buildTheme(kDark),
          themeMode: switch (s.theme) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          themeAnimationDuration: const Duration(milliseconds: 320),
          themeAnimationCurve: Motion.curve,
          home: const RootScreen(),
        );
      }),
    );
  }
}

/// Qaysi ekran: ochilish → kirish → kalit → profil → asosiy.
/// Какой экран: заставка → вход → ключ → профиль → главный.
class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final Widget screen;
    if (s.introDone == false && !s.testMode) {
      // Faqat birinchi ochilishda; bu vaqtda server ham uyg‘onadi / только при первом запуске; заодно просыпается сервер
      screen = IntroScreen(key: const ValueKey('intro'), onDone: s.finishIntro);
    } else if (!s.ready) {
      screen = const SplashScreen(key: ValueKey('splash'));
    } else if (!s.loggedIn) {
      screen = const AuthScreen(key: ValueKey('auth'));
    } else if (s.needsSeat) {
      screen = const SeatScreen(key: ValueKey('seat'));
    } else if (s.needsProfile) {
      screen = const ProfileSetupScreen(key: ValueKey('setup'));
    } else {
      screen = const HomeShell(key: ValueKey('home'));
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (s.isDark || s.introDone != true ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
      child: AnimatedSwitcher(
        duration: Motion.of(context, const Duration(milliseconds: 500)),
        switchInCurve: Motion.curve,
        switchOutCurve: Curves.easeInCubic,
        child: screen,
      ),
    );
  }
}

/// Ochilish ekrani / заставка.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: AppBackground(
        motion: MotionLevel.low,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const AppLogo(size: 96),
            const SizedBox(height: S.x5),
            const Wordmark(),
            const SizedBox(height: S.x2),
            const KengashLockup(height: 30),
            const SizedBox(height: S.x6),
            CupertinoActivityIndicator(color: c.text2, radius: 11),
            const _WakeHint(),
          ]),
        ),
      ),
    );
  }
}

/// 5 soniyadan keyin «server uyg‘onmoqda» / через 5 секунд «сервер просыпается».
class _WakeHint extends StatefulWidget {
  const _WakeHint();

  @override
  State<_WakeHint> createState() => _WakeHintState();
}

class _WakeHintState extends State<_WakeHint> {
  Timer? _t;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return AnimatedOpacity(
      opacity: _show ? 1 : 0,
      duration: Motion.of(context, Motion.slow),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.x6, S.x4, S.x6, 0),
        child: Text(s.t('waking'), textAlign: TextAlign.center, style: AppType.footnote.copyWith(color: s.c.text2)),
      ),
    );
  }
}

/// Bo‘limlar / разделы.
/// Faqat ishlaydigan bo‘limlar ko‘rinadi (soddalik). Vazifalar va taqvim 3-bosqichda qo‘shiladi.
/// Видны только работающие разделы (простота). Задачи и календарь добавятся на 3-м этапе.
const kMainTabs = ['today', 'channels', 'profile'];

(IconData, String) tabMeta(AppState s, String id) => switch (id) {
      'today' => (Icons.wb_sunny_rounded, s.t('tab_today')),
      'channels' => (Icons.forum_rounded, s.t('tab_channels')),
      'tasks' => (Icons.task_alt_rounded, s.t('tab_tasks')),
      'calendar' => (Icons.event_rounded, s.t('tab_calendar')),
      'directory' => (Icons.groups_rounded, s.t('directory')),
      'keys' => (Icons.key_rounded, s.t('keys')),
      'admin' => (Icons.admin_panel_settings_rounded, s.t('admin')),
      _ => (Icons.person_rounded, s.t('tab_profile')),
    };

Widget tabBody(String id) => switch (id) {
      'channels' => const ChannelsTab(),
      'tasks' => const TasksTab(),
      'calendar' => const CalendarTab(),
      'profile' => const ProfileTab(),
      'directory' => const DirectoryScreen(),
      'keys' => const KeysScreen(),
      'admin' => const AdminScreen(),
      _ => const TodayTab(),
    };

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final wide = isWide(context);
    final tools = ['directory', if (s.canKeys) 'keys', if (s.isAdmin) 'admin'];
    var tab = s.tab;
    if (!kMainTabs.contains(tab) && !(wide && tools.contains(tab))) tab = 'today';
    final sel = kMainTabs.contains(tab) ? kMainTabs.indexOf(tab) : 0;

    final switcher = AnimatedSwitcher(
      duration: Motion.of(context, Motion.base),
      switchInCurve: Motion.curve,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.012), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey('$tab-${s.lang}'), child: tabBody(tab)),
    );
    final navItems = [for (final k in kMainTabs) (k, tabMeta(s, k).$1, tabMeta(s, k).$2)];
    // Jonli fon faqat «Bugun» va profil sahifalarida (jadval va ro‘yxatlarda — yo‘q).
    // Живой фон только на «Сегодня» и в профиле (в таблицах и списках — нет).
    final motion = tab == 'today' || tab == 'profile' ? MotionLevel.normal : MotionLevel.off;

    return PopScope(
      canPop: tab == 'today',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) s.go('today');
      },
      child: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Scaffold(
          extendBody: true,
          backgroundColor: s.c.bg,
          body: AppBackground(
            motion: motion,
            child: SafeArea(
              bottom: false,
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _DeskNav(tab: tab, tools: tools),
                      Expanded(child: switcher),
                    ])
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: switcher),
                    ),
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : FloatingNavBar(
                  items: navItems,
                  index: sel,
                  onTap: (i) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    s.go(kMainTabs[i]);
                  }),
        ),
      ),
    );
  }
}

/// Telefonda vosita sahifasini ochish, kompyuterda — yon menyu orqali.
/// На телефоне открыть страницу инструмента, на компьютере — через боковое меню.
void openTool(BuildContext context, String id) {
  final s = AppScope.read(context);
  if (isWide(context)) {
    s.go(id);
  } else {
    Navigator.of(context).push(AppRoute(builder: (_) => PageShell(child: tabBody(id))));
  }
}

/// Kompyuter yon menyusi / боковое меню компьютера.
class _DeskNav extends StatelessWidget {
  final String tab;
  final List<String> tools;
  const _DeskNav({required this.tab, required this.tools});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final open = s.sideOpen;
    void go(String id) {
      FocusManager.instance.primaryFocus?.unfocus();
      s.go(id);
    }

    Widget item(String id) {
      final m = tabMeta(s, id);
      return Padding(
        padding: const EdgeInsets.only(bottom: S.x1),
        child: SideItem(
            key: ValueKey('side-$id'), icon: m.$1, label: m.$2, selected: tab == id, collapsed: !open, onTap: () => go(id)),
      );
    }

    Widget label(String text) => open
        ? Padding(
            padding: const EdgeInsets.fromLTRB(S.x3, S.x4, S.x3, S.x2),
            child: Text(text.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: AppType.caption.copyWith(color: c.text3, fontWeight: w7, letterSpacing: 0.8)),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3, horizontal: S.x3),
            child: Container(height: 1, color: c.hairline),
          );
    final themeIcon = switch (s.theme) {
      'light' => Icons.light_mode_rounded,
      'dark' => Icons.dark_mode_rounded,
      _ => Icons.brightness_auto_rounded,
    };
    void nextTheme() => s.setTheme(switch (s.theme) { 'system' => 'light', 'light' => 'dark', _ => 'system' });

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: open ? 256 : 84,
      margin: const EdgeInsets.all(S.x4),
      child: Glass(
        radius: R.xxl,
        blur: 30,
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 44,
            child: open
                ? Row(children: [
                    const SizedBox(width: S.x1),
                    const KengashMark(size: 36),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Text(kAppName,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: AppType.title3.copyWith(color: c.text)),
                    ),
                    _NavIconBtn(
                        key: const ValueKey('side-toggle'),
                        icon: Icons.keyboard_double_arrow_left_rounded,
                        tip: s.t('side_hide'),
                        onTap: s.toggleSide),
                  ])
                : Center(
                    child: _NavIconBtn(
                        key: const ValueKey('side-toggle'), icon: Icons.menu_rounded, tip: s.t('side_show'), onTap: s.toggleSide),
                  ),
          ),
          const SizedBox(height: S.x3),
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              for (final k in kMainTabs)
                if (k != 'profile') item(k),
              label(s.t('side_tools')),
              for (final k in tools) item(k),
              label(s.t('settings')),
              Padding(
                padding: const EdgeInsets.only(bottom: S.x1),
                child: SideItem(
                  key: const ValueKey('side-lang'),
                  icon: Icons.translate_rounded,
                  label: s.t('language'),
                  collapsed: !open,
                  onTap: s.toggleLang,
                  trailing: _Chip(s.lang == 'uz' ? 'UZ' : 'RU'),
                ),
              ),
              SideItem(
                key: const ValueKey('side-theme'),
                icon: themeIcon,
                label: s.t('appearance'),
                collapsed: !open,
                onTap: nextTheme,
                trailing: _Chip(s.t(s.theme)),
              ),
            ]),
          ),
          const SizedBox(height: S.x3),
          _ProfileCard(selected: tab == 'profile', collapsed: !open, onTap: () => go('profile')),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: 3),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: R.all(R.sm)),
      child: Text(text, style: AppType.caption.copyWith(color: c.accentText, fontWeight: w7)),
    );
  }
}

class _NavIconBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  const _NavIconBtn({super.key, required this.icon, required this.tip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Tooltip(
      message: tip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Pressable(
          onTap: onTap,
          semanticLabel: tip,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: c.glass, borderRadius: R.all(R.md), border: Border.all(color: c.glassEdge)),
            foregroundDecoration: BoxDecoration(gradient: kGloss, borderRadius: R.all(R.md)),
            child: Icon(icon, size: 22, color: c.text2),
          ),
        ),
      ),
    );
  }
}

/// Pastdagi profil kartasi / карточка профиля внизу.
class _ProfileCard extends StatelessWidget {
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  const _ProfileCard({required this.selected, required this.collapsed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final avatar = Container(
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? kWhite : c.surface, width: 2)),
      child: AppAvatar(url: s.myPhoto, name: s.myName, size: 38),
    );
    return Tooltip(
      message: collapsed ? s.t('tab_profile') : '',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Pressable(
          key: const ValueKey('side-profile'),
          onTap: onTap,
          scale: 0.98,
          semanticLabel: s.t('tab_profile'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.all(collapsed ? S.x1 : S.x2),
            decoration: BoxDecoration(
              gradient: selected ? c.accentGradient : null,
              color: selected ? null : c.glass,
              borderRadius: R.all(R.lg),
              border: Border.all(color: selected ? const Color(0x55FFFFFF) : c.glassEdge),
              boxShadow: selected ? Shadows.glow(c.accent, c, strength: 0.6) : null,
            ),
            foregroundDecoration: BoxDecoration(gradient: kGloss, borderRadius: R.all(R.lg)),
            child: collapsed
                ? Center(child: avatar)
                : Row(children: [
                    avatar,
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.myName.isEmpty ? kAppName : s.myName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.subhead.copyWith(color: selected ? kWhite : c.text, fontWeight: w7)),
                        Text(s.isAdmin ? s.t('role_admin') : s.dirName(s.me?['direction']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.caption.copyWith(color: selected ? Colors.white70 : c.text2)),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: selected ? kWhite : c.text3),
                  ]),
          ),
        ),
      ),
    );
  }
}
