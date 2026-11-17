// Xodimlar: admin yaratadi, «Boshqa» arizasini sozlaydi; xodimning «Hududim» sahifasi.
// Сотрудники: админ создаёт, настраивает заявку «Другое»; страница «Моя территория» сотрудника.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kengash/i18n.dart';

import 'app_test.dart' show boot, shot, tap, loadFonts, reveal, settle;
import 'fake_server.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('admin: yangi xodim (raqam, lavozim, hudud, vakolatlar)', (tester) async {
    final server = FakeServer(me: FakeServer.admin());
    await boot(tester, server);
    await reveal(tester, find.byKey(const ValueKey('quick-admin')));
    await tap(tester, find.byKey(const ValueKey('quick-admin')));
    await tap(tester, find.byKey(const ValueKey('admin-staff')));
    expect(find.text(tr('uz', 'staff_none')), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('staff-add')));
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('staff-name')), matching: find.byType(TextField)),
        'Toshmatov Bekzod');
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('staff-phone')), matching: find.byType(TextField)),
        '+998 93 555 44 33');
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('staff-job')), matching: find.byType(TextField)),
        'Asaka Kelajak Markazi direktori');
    await tester.pump();
    await tap(tester, find.byKey(const ValueKey('staff-district')));
    await tap(tester, find.text('Asaka tumani').last);
    await tester.ensureVisible(find.byKey(const ValueKey('power-plan')));
    await tap(tester, find.byKey(const ValueKey('power-plan')));
    await tester.pump(const Duration(milliseconds: 300));
    await shot(tester, 'phone-light-uz-staff-edit');
    await tester.ensureVisible(find.byKey(const ValueKey('staff-save')));
    await tap(tester, find.byKey(const ValueKey('staff-save')));
    await settle(tester);
    expect(server.lastBody['phone'], '+998 93 555 44 33');
    expect(server.lastBody['level'], 'district');
    expect(server.lastBody['place_id'], 'asaka');
    expect(server.lastBody['powers'], ['view', 'plan']);
    expect(find.text('Toshmatov Bekzod'), findsOneWidget);
    await shot(tester, 'phone-light-uz-staff-list');
  });

  testWidgets('admin: «Boshqa» arizasi — Sozlash', (tester) async {
    final server = FakeServer(me: FakeServer.admin());
    server.approvals.add({...FakeServer.staffUser(powers: const []), 'id': 'p9', 'status': 'pending', 'title': '', 'level': null,
      'place': null, 'phone': '+998935550001'});
    await boot(tester, server);
    await tap(tester, find.byKey(const ValueKey('today-approvals')));
    expect(find.byKey(const ValueKey('setup-p9')), findsOneWidget);
    expect(find.byKey(const ValueKey('approve-p9')), findsNothing);
    await tap(tester, find.byKey(const ValueKey('setup-p9')));
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('staff-job')), matching: find.byType(TextField)),
        'Metodist');
    await tap(tester, find.byKey(const ValueKey('staff-level')).last);
    await tap(tester, find.text(tr('uz', 'staff_region')));
    await tester.ensureVisible(find.byKey(const ValueKey('staff-save')));
    await tap(tester, find.byKey(const ValueKey('staff-save')));
    await settle(tester);
    expect(server.lastBody['level'], 'region');
    expect(server.lastBody['place_id'], 'andijon');
    expect(server.lastBody['powers'], ['view']);
  });

  testWidgets('xodim: Hududim — faollik, e’lon, hisobot (kitoblarsiz)', (tester) async {
    final server = FakeServer(me: FakeServer.staffUser());
    final s = await boot(tester, server);
    expect(s.seatLine(s.me), 'Asaka Kelajak Markazi direktori · Asaka tumani');
    await reveal(tester, find.byKey(const ValueKey('quick-area')));
    await tap(tester, find.byKey(const ValueKey('quick-area')));
    expect(find.byKey(const ValueKey('area-broadcast')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-card')), findsOneWidget);
    expect(find.text('77%'), findsOneWidget);
    await shot(tester, 'phone-light-uz-staff-report');
    await tap(tester, find.byKey(const ValueKey('rep-send')));
    expect(find.text(tr('uz', 'rep_sent')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await reveal(tester, find.byKey(const ValueKey('export-users')));
    expect(find.byKey(const ValueKey('export-books')), findsNothing);
    await shot(tester, 'phone-dark-uz-staff-area');
  });
}
