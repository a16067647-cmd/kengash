import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import '../api.dart';
import '../brand.dart';
import '../motion_lab.dart' show MotionLevel;
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'legal.dart';

/// Kirish: «Telegram orqali kirish» → bot → raqamni ulashish → ilovaga qaytish.
/// Вход: «Войти через Telegram» → бот → поделиться номером → вернуться в приложение.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  String? _reqId;
  String? _link;
  bool _starting = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final s = AppScope.read(context);
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final r = await s.api.post('/api/auth/telegram/start', null, const Duration(seconds: 75));
      _reqId = r['id'] as String;
      _link = r['url'] as String;
      setState(() => _starting = false);
      await s.openUrl(_link!);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    } on ApiError catch (e) {
      setState(() {
        _starting = false;
        _error = s.errText(e);
      });
    }
  }

  Future<void> _check() async {
    final id = _reqId;
    if (id == null) return;
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/auth/telegram/status', query: {'id': id});
      if (!mounted || _reqId != id) return;
      switch (r['status']) {
        case 'done':
          _poll?.cancel();
          await s.setSession(r['token'] as String, (r['me'] as Map).cast<String, dynamic>());
          s.toast(s.t('welcome_toast'), icon: Icons.waving_hand_rounded);
        case 'expired':
          _cancel();
          setState(() => _error = s.t('err_login_expired'));
        case 'blocked':
          _cancel();
          setState(() => _error = s.t('err_blocked'));
      }
    } on ApiError {
      // tarmoq uzilishi — keyingi urinishda / сбой сети — при следующей попытке
    }
  }

  void _cancel() {
    _poll?.cancel();
    setState(() {
      _reqId = null;
      _link = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final waiting = _reqId != null;

    final card = Glass(
      radius: R.xl,
      padding: const EdgeInsets.all(S.x5),
      child: AnimatedSize(
        duration: Motion.of(context, Motion.base),
        curve: Motion.curve,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!waiting) ...[
            Text(s.t('login_title'), style: AppType.title3.copyWith(color: c.text)),
            const SizedBox(height: S.x1),
            Text(s.t('login_text'), style: AppType.subhead.copyWith(color: c.text2)),
            const SizedBox(height: S.x5),
            AppButton(s.t('login_tg'),
                key: const ValueKey('login-tg'),
                icon: Icons.send_rounded,
                expand: true,
                height: 56,
                loading: _starting,
                onPressed: _starting ? null : _start),
          ] else ...[
            Row(children: [
              CupertinoActivityIndicator(color: c.accent, radius: 10),
              const SizedBox(width: S.x3),
              Expanded(child: Text(s.t('login_wait_title'), style: AppType.headline.copyWith(color: c.text))),
            ]),
            const SizedBox(height: S.x3),
            for (final (i, k) in [(1, 'login_step1'), (2, 'login_step2'), (3, 'login_step3')])
              Padding(
                padding: const EdgeInsets.only(bottom: S.x2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                    child: Text('$i', style: AppType.caption.copyWith(color: c.accentText)),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(child: Text(s.t(k), style: AppType.subhead.copyWith(color: c.text2))),
                ]),
              ),
            const SizedBox(height: S.x3),
            AppButton(s.t('login_reopen'),
                kind: BtnKind.secondary,
                icon: Icons.open_in_new_rounded,
                expand: true,
                height: 48,
                onPressed: () => s.openUrl(_link!)),
            const SizedBox(height: S.x2),
            AppButton(s.t('cancel'), kind: BtnKind.ghost, expand: true, height: 44, onPressed: _cancel),
          ],
          if (_error != null) ...[
            const SizedBox(height: S.x3),
            Text(_error!, textAlign: TextAlign.center, style: AppType.footnote.copyWith(color: c.danger)),
          ],
        ]),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        motion: MotionLevel.normal,
        child: SafeArea(
          child: Stack(children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(S.page, S.x12, S.page, S.x6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Center(child: AppLogo(size: 84)),
                    const SizedBox(height: S.x4),
                    const Center(child: Wordmark(size: 32)),
                    const SizedBox(height: S.x1),
                    Text(s.t('tagline'), textAlign: TextAlign.center, style: AppType.callout.copyWith(color: c.text2)),
                    const SizedBox(height: S.x4),
                    const Center(child: KengashLockup(height: 36)),
                    const SizedBox(height: S.x5),
                    card,
                    const SizedBox(height: S.x6),
                    LegalLinks(pages: const ['about', 'privacy', 'terms']),
                  ]),
                ),
              ),
            ),
            Positioned(
              top: S.x3,
              right: S.x4,
              child: Row(children: [
                Pressable(
                  key: const ValueKey('auth-lang'),
                  onTap: s.toggleLang,
                  semanticLabel: s.t('language'),
                  child: Glass(
                    radius: R.pill,
                    blur: 20,
                    padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
                    child: Row(children: [
                      Icon(Icons.translate_rounded, size: 16, color: c.text2),
                      const SizedBox(width: S.x1),
                      Text(s.lang == 'uz' ? 'UZ' : 'RU', style: AppType.footnote.copyWith(color: c.text)),
                    ]),
                  ),
                ),
                const SizedBox(width: S.x2),
                AppIconButton(s.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    tooltip: s.t('appearance'), onPressed: () => s.setTheme(s.isDark ? 'light' : 'dark')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
