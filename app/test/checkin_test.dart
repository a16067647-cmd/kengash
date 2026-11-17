// QR davomat: tashkilotchi QR ko‘rsatadi; mehmon kodni yozadi → keldi.
// QR-посещаемость: организатор показывает QR; гость вводит код → пришёл.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kengash/i18n.dart';
import 'package:kengash/screens/checkin.dart' show parseCheckin;

import 'app_test.dart' show boot, shot, tap, back, loadFonts, settle;
import 'fake_server.dart';

void main() {
  setUpAll(loadFonts);

  test('QR havolasini o‘qish / разбор ссылки QR', () {
    final p = parseCheckin('https://a16067647-cmd.github.io/kengash/?checkin=e1&code=482915');
    expect(p?.eid, 'e1');
    expect(p?.code, '482915');
    expect(parseCheckin('https://example.com/?checkin=e1&code=12'), isNull);
    expect(parseCheckin('salom'), isNull);
  });

  testWidgets('tashkilotchi: QR davomat', (tester) async {
    final server = FakeServer(me: FakeServer.seated('district', 'it'));
    await boot(tester, server);
    await tap(tester, find.byKey(const ValueKey('nav-calendar')));
    await tap(tester, find.byKey(const ValueKey('event-e1')));
    expect(find.byKey(const ValueKey('event-checkin')), findsNothing);
    await tap(tester, find.byKey(const ValueKey('event-qr')));
    expect(find.byKey(const ValueKey('qr-code')), findsOneWidget);
    expect(find.text('482 915'), findsOneWidget);
    expect(find.text('27 / 62'), findsOneWidget);
    await shot(tester, 'phone-light-uz-qr-organizer');
    await back(tester);
  });

  testWidgets('mehmon: kodni yozadi → keldi', (tester) async {
    final server = FakeServer(me: FakeServer.seated('school', 'it'))..rsvp = 'yes';
    await boot(tester, server, theme: 'dark');
    await tap(tester, find.byKey(const ValueKey('nav-calendar')));
    await tap(tester, find.byKey(const ValueKey('event-e1')));
    await tap(tester, find.byKey(const ValueKey('event-checkin')));
    final field = find.descendant(of: find.byKey(const ValueKey('ci-code')), matching: find.byType(TextField));
    await tester.enterText(field, '111111');
    await tap(tester, find.byKey(const ValueKey('ci-send')));
    expect(find.text(tr('uz', 'err_bad_code')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.enterText(field, '482915');
    await tap(tester, find.byKey(const ValueKey('ci-send')));
    await settle(tester);
    expect(server.posts.last['path'], '/api/events/e1/checkin');
    expect(find.byKey(const ValueKey('ci-done')), findsOneWidget);
    await shot(tester, 'phone-dark-uz-checkin-done');
  });
}
