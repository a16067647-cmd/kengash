import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'config.dart';
import 'theme.dart';
import 'widgets.dart';

/// O‘quvchilar Kengashi belgisi: halqa va 8 nuqta (har biri — bitta yo‘nalish), yuqoridagisi sariq.
/// Знак Совета учеников: кольцо и 8 точек (по одной на направление), верхняя — жёлтая.
/// Kod bilan chiziladi — har qanday o‘lchamda tiniq / рисуется кодом — чёткий в любом размере.
class KengashMark extends StatelessWidget {
  final double size;
  final Color? color;

  /// true: nuqtalar yo‘nalish ranglarida / точки в цветах направлений.
  final bool directions;
  const KengashMark({super.key, this.size = 48, this.color, this.directions = false});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final col = color ?? (c.isDark ? kWhite : kKengashBlue);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(col, directions)),
    );
  }
}

const _order = ['lider', 'talim', 'ijtimoiy', 'it', 'media', 'ekologiya', 'sport', 'madaniyat'];

class _MarkPainter extends CustomPainter {
  final Color color;
  final bool directions;
  _MarkPainter(this.color, this.directions);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 260;
    final center = size.center(Offset.zero);
    canvas.drawCircle(
        center,
        62 * k,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 20 * k
          ..isAntiAlias = true);
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final col = i == 0 ? kSun : (directions ? directionColor(_order[i]) : color);
      canvas.drawCircle(center + Offset(math.cos(a), math.sin(a)) * 100 * k, 19 * k, Paint()..color = col);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color || old.directions != directions;
}

/// "O‘QUVCHILAR KENGASHI" logotipi (belgi + yozuv) / логотип (знак + надпись).
class KengashLockup extends StatelessWidget {
  final double height;
  const KengashLockup({super.key, this.height = 44});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final col = c.isDark ? kWhite : kKengashBlue;
    final style =
        TextStyle(fontFamily: kBody, fontWeight: w8, fontSize: height * 0.36, height: 1.02, color: col, letterSpacing: 0.2);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      KengashMark(size: height),
      SizedBox(width: height * 0.22),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('O‘QUVCHILAR', style: style),
        Text('KENGASHI', style: style),
      ]),
    ]);
  }
}

/// Ilova ikonkasi (Kelajak Markazlari) / иконка приложения.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 88});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.235),
        boxShadow: Shadows.glow(kViolet, c, strength: 0.7),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.235),
        child: Image.asset('assets/icon/icon.png', fit: BoxFit.cover, filterQuality: FilterQuality.medium),
      ),
    );
  }
}

/// Ilova nomi (so‘z belgisi) / название приложения.
class Wordmark extends StatelessWidget {
  final double size;
  final Color? color;
  const Wordmark({super.key, this.size = 26, this.color});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Text(kAppName, style: AppType.title1.copyWith(fontSize: size, color: color ?? c.text, letterSpacing: -size * 0.03));
  }
}

/// Yo‘nalish belgisi (rangli plitka) / значок направления (цветная плитка).
class DirectionTile extends StatelessWidget {
  final String? direction;
  final double size;
  const DirectionTile(this.direction, {super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    final col = directionColor(direction);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(size * 0.27)),
      child: Icon(directionIcon(direction), size: size * 0.6, color: direction == 'lider' ? kBlack : kWhite),
    );
  }
}
