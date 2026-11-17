// Tashabbuslar: ro‘yxat, ovoz, yangi g‘oya / инициативы: список, голос, новая идея.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show boot, shot, tap, loadFonts, reveal, settle;
import 'fake_server.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('tashabbuslar: ovoz va yangi g‘oya', (tester) async {
    final server = FakeServer(me: FakeServer.seated('school', 'it'));
    await boot(tester, server);
    await reveal(tester, find.byKey(const ValueKey('quick-ideas')));
    await tap(tester, find.byKey(const ValueKey('quick-ideas')));
    expect(find.text('Maktab hovlisida kitob javoni'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('idea-vote-i2')));
    expect(server.posts.last['path'], '/api/ideas/i2/vote');
    expect(server.posts.last['vote'], true);
    expect(find.text('12'), findsOneWidget);
    await shot(tester, 'phone-light-uz-ideas');
    await tap(tester, find.byKey(const ValueKey('idea-add')));
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('idea-title')), matching: find.byType(TextField)),
        'Har oy ekologik shanbalik');
    await tap(tester, find.byKey(const ValueKey('idea-send')));
    await settle(tester);
    expect(server.posts.last['title'], 'Har oy ekologik shanbalik');
    expect(find.text('Har oy ekologik shanbalik'), findsOneWidget);
  });
}
