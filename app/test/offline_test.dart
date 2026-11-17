// Tez ochilish: internet yo‘q bo‘lsa ham oxirgi ma’lumot darhol ko‘rinadi; chiqishda tozalanadi.
// Мгновенный старт: даже без сети сразу видны последние данные; при выходе очищаются.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kengash/api.dart';
import 'package:kengash/main.dart';
import 'package:kengash/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_test.dart' show boot, loadFonts, settle, tap;
import 'fake_server.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('avval kirgan: internetsiz ham darhol ochiladi', (tester) async {
    // 1) internet bor — ma’lumot saqlanadi / 1) сеть есть — данные сохраняются
    final server = FakeServer(me: FakeServer.seated('school', 'it'));
    await boot(tester, server);
    final prefs = await SharedPreferences.getInstance();
    final saved = {for (final k in prefs.getKeys()) k: prefs.get(k)};
    expect(saved.keys, contains('c:/api/today'));
    expect(saved.keys, contains('c:/api/channels'));

    // 2) internet yo‘q (har so‘rov xato) — baribir «Bugun» darhol / 2) сети нет — всё равно сразу «Сегодня»
    SharedPreferences.setMockInitialValues(saved.cast<String, Object>());
    final down = MockClient((_) async => throw http.ClientException('offline'));
    final s = AppState(api: Api(base: 'http://test', client: down), testMode: true);
    await tester.pumpWidget(KengashApp(state: s));
    await s.init();
    await settle(tester);
    expect(s.ready, isTrue);
    expect(s.loggedIn, isTrue);
    expect(find.byKey(const ValueKey('nav-today')), findsOneWidget);
    expect(s.api.peek('/api/today'), isNotNull);
    expect(s.chat.channels, isNotEmpty); // kanallar ham / и каналы
  });

  testWidgets('chiqishda saqlangan ma’lumot o‘chadi', (tester) async {
    final s = await boot(tester, FakeServer(me: FakeServer.seated('school', 'it')));
    expect(s.api.peek('/api/today'), isNotNull);
    await tap(tester, find.byKey(const ValueKey('nav-profile')));
    await s.logout();
    await settle(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('c:')), isEmpty);
    expect(jsonEncode(s.api.peek('/api/today')), 'null');
  });
}
