// Yangi versiya haqida xabar (faqat Android APK). Sayt o‘zi yangilanadi.
// Сообщение о новой версии (только Android APK). Сайт обновляется сам.
import 'package:flutter/material.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Yuqoridagi ixcham banner: «Yangi versiya bor» · Yangilash · ✕.
/// Компактный баннер сверху: «Есть новая версия» · Обновить · ✕.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final show = s.updateAvailable && s.ready && (s.introDone != false || s.testMode); // ochilish animatsiyasidan keyin / после заставки
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: Motion.of(context, const Duration(milliseconds: 380)),
          switchInCurve: Motion.curve,
          transitionBuilder: (child, a) => SlideTransition(
            position: Tween(begin: const Offset(0, -1.2), end: Offset.zero).animate(a),
            child: FadeTransition(opacity: a, child: child),
          ),
          child: !show
              ? const SizedBox.shrink()
              : Padding(
                  key: const ValueKey('update-banner'),
                  padding: const EdgeInsets.fromLTRB(S.x3, S.x2, S.x3, 0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x2, S.x3),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: R.all(R.xl),
                          border: Border.all(color: c.accent.withValues(alpha: 0.35)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Row(children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                            child: Icon(Icons.system_update_rounded, color: c.accent, size: 22),
                          ),
                          const SizedBox(width: S.x3),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text(s.t('upd_title'), style: AppType.headline.copyWith(color: c.text)),
                              if (s.updateProgress != null)
                                Padding(padding: const EdgeInsets.only(top: 4), child: _Progress(s.updateProgress!))
                              else
                                Text(s.t('upd_sub'),
                                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: c.text2)),
                            ]),
                          ),
                          const SizedBox(width: S.x2),
                          AppButton(s.t('upd_go'),
                              key: const ValueKey('update-go'),
                              height: 40,
                              loading: s.updateProgress != null,
                              onPressed: s.updateProgress != null ? null : () => _install(context)),
                          // Navigator ustida Overlay yo‘q — Tooltip’siz oddiy tugma
                          // над Navigator нет Overlay — простая кнопка без Tooltip
                          Semantics(
                            button: true,
                            label: s.t('upd_later'),
                            child: InkResponse(
                              key: const ValueKey('update-later'),
                              onTap: s.hideUpdate,
                              radius: 22,
                              child: Padding(
                                padding: const EdgeInsets.all(S.x3),
                                child: Icon(Icons.close_rounded, color: c.text3, size: 20),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

Future<void> _install(BuildContext context) => AppScope.read(context).installUpdate();

/// Yuklanish chizig‘i / полоса загрузки.
class _Progress extends StatelessWidget {
  final double value;
  const _Progress(this.value);

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      ClipRRect(
        borderRadius: R.all(R.pill),
        child: LinearProgressIndicator(
            key: const ValueKey('update-progress'), value: value, minHeight: 6, color: c.accent, backgroundColor: c.surfaceAlt),
      ),
      const SizedBox(height: 4),
      Text('${s.t('upd_loading')} ${(value * 100).round()}%', style: AppType.caption.copyWith(color: c.text2)),
    ]);
  }
}

/// Majburiy yangilanish: eski versiya ishlamaydi / обязательное обновление: старая версия не работает.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(S.x6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                  child: Icon(Icons.system_update_rounded, color: c.accent, size: 44),
                ),
                const SizedBox(height: S.x5),
                Text(s.t('upd_req_title'), textAlign: TextAlign.center, style: AppType.title2.copyWith(color: c.text)),
                const SizedBox(height: S.x2),
                Text(s.t('upd_req_sub'), textAlign: TextAlign.center, style: AppType.body.copyWith(color: c.text2)),
                const SizedBox(height: S.x6),
                if (s.updateProgress != null)
                  _Progress(s.updateProgress!)
                else
                  AppButton(s.t('upd_go'),
                      key: const ValueKey('update-required-go'),
                      expand: true,
                      icon: Icons.download_rounded,
                      onPressed: () => _install(context)),
                const SizedBox(height: S.x3),
                Text(s.t('upd_how2'), textAlign: TextAlign.center, style: AppType.footnote.copyWith(color: c.text3)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
