import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sound.dart';
import '../theme.dart';

/// Ochilish animatsiyasi (har safar ilova ochilganda, tugmasiz, ~5 soniya):
/// 8 nuqta (8 yo‘nalish) har tomondan uchib keladi, halqa atrofida birlashadi →
/// O‘quvchilar Kengashi belgisi → «Kengash» va Kelajak Markazlari logotipi → ilovaga silliq o‘tish.
///
/// Вступительная анимация (при каждом запуске, без кнопок, ~5 секунд):
/// 8 точек (8 направлений) слетаются со всех сторон и собираются вокруг кольца →
/// знак Совета учеников → «Kengash» и логотип Kelajak Markazlari → плавный переход в приложение.
class IntroScreen extends StatefulWidget {
  final VoidCallback onDone;
  const IntroScreen({super.key, required this.onDone});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  static const total = Duration(milliseconds: 5200);
  late final AnimationController _c = AnimationController(vsync: this, duration: total)..addListener(_sound);
  bool _done = false;
  int _chimes = 0;
  bool _chord = false;

  /// Har nuqta halqaga qo‘nganda — bitta shisha nota (ko‘tarilib boradi), belgi tugaganda — akkord.
  /// Каждая точка садится на кольцо — стеклянная нота (по возрастающей), знак готов — аккорд.
  void _sound() {
    final t = _c.value;
    while (_chimes < 8 && t >= 0.04 + _chimes * 0.035 + 0.30 * 0.55) {
      Sfx.chime(_chimes);
      _chimes++;
    }
    if (!_chord && t >= 0.585) {
      _chord = true;
      Sfx.introChord();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      // «Harakatni kamaytirish»: yakuniy kadr 1.5 soniya / «уменьшение движения»: финальный кадр 1.5 с
      _c.value = 1;
      Future.delayed(const Duration(milliseconds: 1500), _finish);
    } else {
      _c.forward().whenComplete(_finish);
    }
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// [a]..[b] oralig‘ida 0→1 / от 0 до 1 на отрезке [a, b].
  static double seg(double t, double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final markSize = math.min(size.shortestSide * 0.5, 240.0);
    return Scaffold(
      backgroundColor: kViolet,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // Belgi biroz yuqoriga suriladi va kichrayadi / знак поднимается и чуть уменьшается
          final lift = seg(t, 0.64, 0.80, Curves.easeInOutCubic);
          final pulse = 1 + 0.07 * math.sin(math.pi * seg(t, 0.56, 0.66, Curves.easeInOut));
          final scale = (1 - 0.18 * lift) * pulse;
          final word = seg(t, 0.70, 0.84);
          final lockup = seg(t, 0.76, 0.90);
          final kelajak = seg(t, 0.80, 0.94);
          return Stack(fit: StackFit.expand, children: [
            // Yumshoq yorug‘lik / мягкое свечение
            Opacity(
              opacity: seg(t, 0.0, 0.25),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.25),
                    radius: 0.9,
                    colors: [Color(0xFF5A32B0), kViolet],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment(0, -0.16 - 0.20 * lift),
              child: Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: markSize,
                  height: markSize,
                  child: CustomPaint(painter: _GatherPainter(t, size, markSize)),
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.24),
              child: Opacity(
                opacity: word,
                child: Transform.translate(
                  offset: Offset(0, 18 * (1 - word)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('Kengash',
                        style:
                            AppType.largeTitle.copyWith(color: kWhite, fontSize: 44, letterSpacing: -1.4, shadows: kTextShadow)),
                    const SizedBox(height: S.x3),
                    Opacity(
                      opacity: lockup,
                      child: Text('O‘QUVCHILAR KENGASHI',
                          style: AppType.overline.copyWith(color: Colors.white.withAlpha(0xD9), fontSize: 13, letterSpacing: 3)),
                    ),
                  ]),
                ),
              ),
            ),
            // Kelajak Markazlari (rasm foni ham shu binafsha) / фон картинки тоже этот фиолетовый
            Align(
              alignment: const Alignment(0, 0.86),
              child: Opacity(
                opacity: kelajak,
                child: Image.asset('assets/brand/kelajak_white.png', width: 110),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// 8 nuqta uchib kelib, halqa chiziladi / 8 точек слетаются, рисуется кольцо.
class _GatherPainter extends CustomPainter {
  final double t;
  final Size screen;
  final double side;
  _GatherPainter(this.t, this.screen, this.side);

  static const _order = ['lider', 'talim', 'ijtimoiy', 'it', 'media', 'ekologiya', 'sport', 'madaniyat'];
  // Har bir nuqta qaysi tomondan uchib keladi (gradus) / откуда прилетает каждая точка (градусы)
  static const _from = [250.0, 20.0, 145.0, 300.0, 75.0, 200.0, 335.0, 110.0];

  Color _col(String d) => d == 'it' ? const Color(0xFF9B7BFF) : directionColor(d);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 260;
    final c = size.center(Offset.zero);
    final far = screen.longestSide / k;

    // Halqa (oq) chiziladi / рисуется кольцо (белое)
    final ring = _IntroScreenState.seg(t, 0.40, 0.60, Curves.easeInOutCubic);
    if (ring > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 62 * k),
        -math.pi / 2,
        2 * math.pi * ring,
        false,
        Paint()
          ..color = kWhite
          ..style = PaintingStyle.stroke
          ..strokeWidth = 20 * k
          ..strokeCap = ring < 1 ? StrokeCap.round : StrokeCap.butt,
      );
    }

    for (var i = 0; i < 8; i++) {
      final start = 0.04 + i * 0.035;
      final p = _IntroScreenState.seg(t, start, start + 0.30, Curves.easeOutBack);
      if (t < start) continue;
      final target = -math.pi / 2 + i * math.pi / 4;
      final fromA = _from[i] * math.pi / 180;
      final end = Offset(math.cos(target), math.sin(target)) * 100;
      final begin = Offset(math.cos(fromA), math.sin(fromA)) * far;
      // Egri yo‘l (aylanib keladi) / изогнутая траектория
      final swirl = Offset(-end.dy, end.dx) * 0.35 * math.sin(math.pi * p.clamp(0.0, 1.0));
      final pos = Offset.lerp(begin, end, p)! + swirl;
      final col = _col(_order[i]);
      final r = 19.0 * (0.6 + 0.4 * p.clamp(0.0, 1.0));
      // Iz (quyruq) / след
      if (p < 1) {
        final tail = Offset.lerp(begin, end, (p - 0.08).clamp(0.0, 1.0))! + swirl * 0.9;
        canvas.drawLine(
          c + tail * k,
          c + pos * k,
          Paint()
            ..color = col.withAlpha(0x55)
            ..strokeWidth = r * k * 1.2
            ..strokeCap = StrokeCap.round,
        );
      }
      // Yengil nur / лёгкое свечение
      canvas.drawCircle(c + pos * k, r * 1.9 * k, Paint()..color = col.withAlpha(0x30));
      canvas.drawCircle(c + pos * k, r * k, Paint()..color = col);
    }
  }

  @override
  bool shouldRepaint(_GatherPainter old) => old.t != t || old.side != side;
}
