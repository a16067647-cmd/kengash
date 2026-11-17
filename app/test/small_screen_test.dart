// Kichik telefon (320×640) va katta shrift (1.3×): asosiy bo‘limlarda hech narsa sig‘may qolmasligi kerak.
// Маленький телефон и крупный шрифт: в основных разделах ничего не должно вылезать за край.
// Sig‘masa Flutter «RenderFlex overflowed» xatosini beradi — test yiqiladi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show boot, tap, loadFonts, settle;
import 'fake_server.dart';

void main() {
  setUpAll(loadFonts);

  for (final (who, me) in [
    ('maktab koordinatori', FakeServer.seated('school', 'it')),
    ('admin', FakeServer.admin()),
    ('o‘quvchi', FakeServer.student()),
  ]) {
    for (final lang in ['uz', 'ru']) {
      testWidgets('kichik ekran: $who, $lang', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await boot(tester, FakeServer(me: me), size: const Size(320, 640), lang: lang);
        for (final tab in ['channels', 'tasks', 'calendar', 'profile', 'today']) {
          final f = find.byKey(ValueKey('nav-$tab'));
          if (f.evaluate().isEmpty) continue;
          await tap(tester, f);
          await settle(tester);
          // pastgacha aylantirib, hamma qismini chizdiramiz / прокручиваем вниз, чтобы отрисовать всё
          for (var i = 0; i < 6; i++) {
            final lists = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
            if (lists.evaluate().isEmpty) break;
            await tester.drag(lists.last, const Offset(0, -400), warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 150));
          }
        }
      });
    }
  }
}
