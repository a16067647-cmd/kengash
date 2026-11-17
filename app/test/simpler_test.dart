// Soddaroq: aqlli standartlar, effektlar bitta qatorda, ovozli hisobot tugmasi.
// Проще: умные значения по умолчанию, эффекты в одной строке, кнопка голосового отчёта.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kengash/state.dart';

import 'app_test.dart' show boot, shot, tap, back, loadFonts, settle;
import 'fake_server.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('vazifa: faqat nomini yozish yetarli (muddat — 3 kundan keyin 18:00)', (tester) async {
    final server = FakeServer(me: FakeServer.seated('district', 'it'));
    await boot(tester, server);
    await tap(tester, find.byKey(const ValueKey('nav-tasks')));
    await tap(tester, find.byKey(const ValueKey('new-task')));
    await tester.enterText(find.byKey(const ValueKey('task-title')).first, 'Hisobot');
    await tap(tester, find.byKey(const ValueKey('task-create')));
    final p = server.posts.last;
    expect(p['title'], 'Hisobot');
    final now = DateTime.now();
    expect(p['deadline'], DateTime(now.year, now.month, now.day + 3, 18).millisecondsSinceEpoch ~/ 1000);
    expect(p['audience'], isNotEmpty);
  });

  testWidgets('tadbir: oxirgi joy eslab qolinadi', (tester) async {
    final server = FakeServer(me: FakeServer.seated('district', 'it'));
    await boot(tester, server);
    await tap(tester, find.byKey(const ValueKey('nav-calendar')));
    await tap(tester, find.byKey(const ValueKey('new-event')));
    await tester.enterText(find.byKey(const ValueKey('event-title')).first, 'Uchrashuv');
    await tester.enterText(find.byKey(const ValueKey('event-place')).first, 'Yoshlar markazi');
    await tap(tester, find.byKey(const ValueKey('when-1')));
    await tap(tester, find.byKey(const ValueKey('event-create')));
    expect(server.posts.last['place'], 'Yoshlar markazi');
    await tap(tester, find.byKey(const ValueKey('new-event')));
    expect(find.text('Yoshlar markazi'), findsOneWidget); // ikkinchi marta — tayyor / во второй раз — уже заполнено
  });

  testWidgets('profil: effektlar bitta qatorda yashirin', (tester) async {
    await boot(tester, FakeServer(me: FakeServer.seated('school', 'it')));
    await tap(tester, find.byKey(const ValueKey('nav-profile')));
    expect(find.byKey(const ValueKey('row-glass')), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('row-effects')), 200);
    await tap(tester, find.byKey(const ValueKey('row-effects')));
    expect(find.byKey(const ValueKey('row-glass')), findsOneWidget);
    expect(find.byKey(const ValueKey('row-bg')), findsOneWidget);
    await shot(tester, 'phone-light-uz-effects');
  });

  testWidgets('hisobot: «Ovoz bilan aytish» tugmasi bor', (tester) async {
    await boot(tester, FakeServer(me: FakeServer.seated('school', 'it')));
    await tap(tester, find.byKey(const ValueKey('nav-tasks')));
    await tap(tester, find.byKey(const ValueKey('task-t1')));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('report-mic')), 200, scrollable: find.byType(Scrollable).last);
    expect(find.byKey(const ValueKey('report-mic')), findsOneWidget);
    await shot(tester, 'phone-light-uz-report-voice');
    await back(tester);
  });

  testWidgets('Telegram ichida ochilsa — darhol kiradi', (tester) async {
    AppState.telegramInitData = 'good';
    addTearDown(() => AppState.telegramInitData = null);
    await boot(tester, FakeServer(me: FakeServer.seated('school', 'it')), loggedIn: false);
    expect(find.byKey(const ValueKey('nav-today')), findsOneWidget);
  });

  testWidgets('Telegram ichida, lekin ro‘yxatdan o‘tmagan — oddiy kirish ekrani', (tester) async {
    AppState.telegramInitData = 'new-person';
    addTearDown(() => AppState.telegramInitData = null);
    await boot(tester, FakeServer(me: FakeServer.seated('school', 'it')), loggedIn: false);
    expect(find.byKey(const ValueKey('nav-today')), findsNothing);
  });

  testWidgets('e’lon: muallif «Ko‘rdi 9/12» ni ko‘radi va bir marta eslatadi', (tester) async {
    final server = FakeServer(me: FakeServer.seated('district', 'it'));
    await boot(tester, server);
    await tap(tester, find.byKey(const ValueKey('nav-channels')));
    await tap(tester, find.text('IT tanlovi 2026').first);
    expect(find.textContaining('9/12'), findsOneWidget);
    await tester.longPress(find.textContaining('Men tayyorman', findRichText: true));
    await settle(tester);
    expect(find.byKey(const ValueKey('seen-line')), findsOneWidget);
    await shot(tester, 'phone-light-uz-remind');
    await tap(tester, find.byKey(const ValueKey('act-remind')));
    expect(server.posts.last['path'], '/api/messages/x5/remind');
  });
}
