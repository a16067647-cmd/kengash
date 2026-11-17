// So‘rovnoma: kanalda ko‘rinadi, ovoz beriladi, yangisi yaratiladi.
// Опрос: виден в канале, голосование, создание нового.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show boot, shot, tap, loadFonts, settle;
import 'fake_server.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('kanal: so‘rovnoma — ovoz va yangi', (tester) async {
    final server = FakeServer(me: FakeServer.seated('school', 'it'))..withPoll = true;
    await boot(tester, server);
    await tap(tester, find.byKey(const ValueKey('nav-channels')));
    await tap(tester, find.byKey(const ValueKey('ch-dd:asaka:it')));
    expect(find.text('Uchrashuv qaysi kuni bo‘lsin?'), findsOneWidget);
    expect(find.text('58%'), findsNothing); // ovozgacha natija yashirin / до голоса результат скрыт
    await tap(tester, find.byKey(const ValueKey('poll-pl1-0')));
    await settle(tester);
    expect(server.posts.last['path'], '/api/polls/pl1/vote');
    expect(server.posts.last['options'], [0]);
    expect(find.text('62%'), findsOneWidget); // 8 / 13
    await shot(tester, 'phone-light-uz-poll');

    // yangi so‘rovnoma / новый опрос
    await tap(tester, find.byKey(const ValueKey('attach')));
    await tap(tester, find.byKey(const ValueKey('att-poll')));
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('poll-question')), matching: find.byType(TextField)),
        'Qaysi mavzu?');
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('poll-opt-0')), matching: find.byType(TextField)), 'Robototexnika');
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('poll-opt-1')), matching: find.byType(TextField)), 'Dasturlash');
    await tap(tester, find.byKey(const ValueKey('poll-add')));
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('poll-opt-2')), matching: find.byType(TextField)), 'Sun’iy intellekt');
    await tester.ensureVisible(find.byKey(const ValueKey('poll-create')));
    await tap(tester, find.byKey(const ValueKey('poll-create')));
    await settle(tester);
    expect(server.posts.last['path'], endsWith('/polls'));
    expect(server.posts.last['options'], ['Robototexnika', 'Dasturlash', 'Sun’iy intellekt']);
  });

  testWidgets('g‘olib: reytingda sertifikat', (tester) async {
    final server = FakeServer(me: FakeServer.seated('school', 'it'));
    await boot(tester, server);
    await tap(tester, find.byKey(const ValueKey('quick-rating')));
    expect(find.byKey(const ValueKey('my-cert')), findsOneWidget);
    await shot(tester, 'phone-light-uz-cert-banner');
    await tap(tester, find.byKey(const ValueKey('my-cert')));
    expect(server.posts.last['path'], '/api/certificates/mine/pdf');
    await tester.pump(const Duration(seconds: 4));
  });
}
