// Adminga yozish, uzoq bosib tahrirlash, admin vositalari.
// Написать админу, правка долгим нажатием, инструменты админа.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kengash/i18n.dart';

import 'app_test.dart' show boot, shot, tap, back, loadFonts, reveal, settle;
import 'fake_server.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('o‘quvchi adminga taklif yuboradi', (tester) async {
    final server = FakeServer(me: FakeServer.student());
    await boot(tester, server);
    await tap(tester, find.byKey(const ValueKey('quick-feedback')));
    expect(find.text(tr('uz', 'fb_title')), findsWidgets);
    await tap(tester, find.text(tr('uz', 'fb_taklif')));
    await tester.enterText(find.byKey(const ValueKey('fb-text')).first, 'Tungi rejim kerak');
    await shot(tester, 'phone-light-uz-19-feedback');
    await tap(tester, find.byKey(const ValueKey('fb-send')));
    final p = server.posts.last;
    expect(p['path'], '/api/feedback');
    expect(p['topic'], 'taklif');
    expect(p['text'], 'Tungi rejim kerak');
    expect(find.text(tr('uz', 'fb_sent')), findsOneWidget);
  });

  testWidgets('admin: shikoyatga javob, e’lon, faollik, Excel, tahrirlash', (tester) async {
    final server = FakeServer(me: FakeServer.admin());
    await boot(tester, server);
    await tap(tester, find.byKey(const ValueKey('quick-admin')));
    // faollik va Excel / активность и Excel
    await reveal(tester, find.byKey(const ValueKey('act-districts')));
    expect(find.byKey(const ValueKey('act-districts')), findsOneWidget);
    await shot(tester, 'phone-light-uz-20-activity');
    await tap(tester, find.byKey(const ValueKey('export-users')));
    expect(server.posts.last['path'], '/api/admin/export');
    expect(server.posts.last['what'], 'users');

    // shikoyatlar: foydalanuvchi xabariga javob / ответ на сообщение пользователя
    await tester.drag(find.byType(Scrollable).last, const Offset(0, 3000));
    await settle(tester);
    await tap(tester, find.text(tr('uz', 'reports')).first);
    expect(find.text('Kitoblar uchun audio versiya ham bo‘lsa zo‘r bo‘lardi!'), findsOneWidget);
    await shot(tester, 'phone-light-uz-21-feedback-admin');
    await tester.enterText(find.byKey(const ValueKey('fb-reply-f1')).first, 'Rahmat, qo‘shamiz!');
    await tap(tester, find.byKey(const ValueKey('fb-reply-send-f1')));
    expect(server.posts.last['text'], 'Rahmat, qo‘shamiz!');

    // e’lon / рассылка
    await tap(tester, find.byKey(const ValueKey('admin-broadcast')));
    expect(find.textContaining('1240'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('bc-text')).first, 'Ertaga soat 15:00 da yig‘ilish');
    await shot(tester, 'phone-light-uz-22-broadcast');
    await tap(tester, find.byKey(const ValueKey('bc-send')));
    expect(server.posts.last['path'], '/api/admin/broadcast');
    expect(server.posts.last['text'], 'Ertaga soat 15:00 da yig‘ilish');

    // foydalanuvchini tahrirlash / правка пользователя
    await tap(tester, find.text(tr('uz', 'users')).first);
    await tap(tester, find.text('Karimova Madina'));
    await tap(tester, find.byKey(const ValueKey('user-edit')));
    expect(find.byKey(const ValueKey('eu-name')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('eu-name')).first, 'Karimova Madina Akmal qizi');
    await shot(tester, 'phone-light-uz-23-edit-user');
    await tap(tester, find.byKey(const ValueKey('eu-save')));
    expect(server.posts.last['path'], '/api/admin/users/m59it/edit');
    expect(server.posts.last['name'], 'Karimova Madina Akmal qizi');
    expect(server.posts.last['direction'], 'it');
  });

  testWidgets('uzoq bosish: kanal, vazifa, tadbir', (tester) async {
    final server = FakeServer(me: FakeServer.seated('district', 'it'));
    await boot(tester, server);
    // kanal: uzoq bosib o‘chirish / канал: удалить долгим нажатием
    await tap(tester, find.byKey(const ValueKey('nav-channels')));
    await tester.longPress(find.byKey(const ValueKey('ch-IT tanlovi 2026')));
    await settle(tester);
    expect(find.byKey(const ValueKey('act-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('act-photo')), findsOneWidget);
    await shot(tester, 'phone-light-uz-24-channel-longpress');
    await tap(tester, find.byKey(const ValueKey('act-edit')));
    await tester.enterText(find.byKey(const ValueKey('edit-title')).first, 'IT tanlovi 2027');
    await tap(tester, find.byKey(const ValueKey('edit-save')));
    expect(server.posts.last['path'], '/api/channels/c-cu');
    expect(server.posts.last['title'], 'IT tanlovi 2027');
    // avtomatik kanal — tegib bo‘lmaydi / автоматический канал — нельзя
    await tester.longPress(find.byKey(const ValueKey('ch-all')));
    await settle(tester);
    expect(find.byKey(const ValueKey('act-delete')), findsNothing);

    // vazifa / задача
    await tap(tester, find.byKey(const ValueKey('nav-tasks')));
    await tap(tester, find.text(tr('uz', 'box_given')));
    await tester.longPress(find.byKey(const ValueKey('task-t1')));
    await settle(tester);
    await tap(tester, find.byKey(const ValueKey('act-edit')));
    await tester.enterText(find.byKey(const ValueKey('edit-title')).first, 'Robototexnika hisoboti (yangi)');
    await tap(tester, find.byKey(const ValueKey('edit-save')));
    expect(server.posts.last['path'], '/api/tasks/t1/edit');
    expect(server.posts.last['title'], 'Robototexnika hisoboti (yangi)');

    // tadbir / мероприятие
    await tap(tester, find.byKey(const ValueKey('nav-calendar')));
    await tester.longPress(find.byKey(const ValueKey('event-e1')));
    await settle(tester);
    await tap(tester, find.byKey(const ValueKey('act-delete')));
    await tap(tester, find.text(tr('uz', 'delete')).last);
    expect(server.posts.last['path'], '/api/events/e1/delete');
  });
}
