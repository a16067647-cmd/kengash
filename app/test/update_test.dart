// Yangi versiya banneri va majburiy yangilanish / баннер новой версии и обязательное обновление.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kengash/i18n.dart';
import 'package:kengash/state.dart';

import 'app_test.dart' show boot, shot, tap, loadFonts, settle;
import 'fake_server.dart';

Future<void> _check(WidgetTester tester, AppState s, String json) async {
  s
    ..appBuild = 40
    ..updateCheckOn = true
    ..fetchText = (url) async {
      expect(url.path, endsWith('/version.json'));
      return json;
    };
  await s.checkUpdate(force: true);
  await settle(tester);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('yangi versiya: banner, Keyinroq', (tester) async {
    final s = await boot(tester, FakeServer(me: FakeServer.seated('school', 'sport')));
    expect(find.byKey(const ValueKey('update-banner')), findsNothing); // test yig‘ish — tekshirilmaydi
    await _check(tester, s, '{"build": 40, "min": 0}');
    expect(find.byKey(const ValueKey('update-banner')), findsNothing); // shu versiya / та же версия
    await _check(tester, s, '{"build": 41, "min": 0, "apk": "Kengash.apk"}');
    expect(find.byKey(const ValueKey('update-banner')), findsOneWidget);
    expect(find.text(tr('uz', 'upd_title')), findsOneWidget);
    await shot(tester, 'phone-light-uz-update-banner');
    await tap(tester, find.byKey(const ValueKey('update-go')));
    expect(find.text(tr('uz', 'upd_how')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tap(tester, find.byKey(const ValueKey('update-later')));
    await settle(tester);
    expect(find.byKey(const ValueKey('update-banner')), findsNothing);
  });

  testWidgets('majburiy yangilanish: eski versiya ishlamaydi', (tester) async {
    final s = await boot(tester, FakeServer(me: FakeServer.seated('school', 'sport')), theme: 'dark', lang: 'ru');
    await _check(tester, s, '{"build": 45, "min": 42}');
    expect(find.byKey(const ValueKey('update-required')), findsOneWidget);
    expect(find.byKey(const ValueKey('update-banner')), findsNothing);
    expect(find.text(tr('ru', 'upd_req_title')), findsOneWidget);
    await shot(tester, 'phone-dark-ru-update-required');
    await tap(tester, find.byKey(const ValueKey('update-required-go')));
  });
}
