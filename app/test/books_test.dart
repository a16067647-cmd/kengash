// Oy kitobi: javon, kitob sahifasi, «O‘qidim», admin tahrirlovchisi.
// Книга месяца: полка, страница книги, «Прочитал», редактор админа.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kengash/i18n.dart';

import 'app_test.dart' show boot, shot, tap, back, loadFonts, reveal;
import 'fake_server.dart';
import 'png_http.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('Oy kitobi: Bugun javoni, kitob, O‘qidim', (tester) async {
    HttpOverrides.global = PngHttp(await makePng(tester, w: 600, h: 900, a: const Color(0xFF3D1E8C), b: const Color(0xFFFFBB02)));
    addTearDown(() => HttpOverrides.global = null);
    final server = FakeServer(me: FakeServer.seated('school', 'sport'))..booksCovers = true;
    await boot(tester, server);
    await reveal(tester, find.byKey(const ValueKey('books-shelf')));
    expect(find.text(tr('uz', 'books_title')), findsNothing); // sarlavha emoji bilan / заголовок с эмодзи
    expect(find.text('📚 ${tr('uz', 'books_title')}'), findsOneWidget);
    // o‘z yo‘nalishi birinchi / своё направление первым
    final first = tester.getTopLeft(find.byKey(const ValueKey('book-sport'))).dx;
    final other = tester.getTopLeft(find.byKey(const ValueKey('book-lider'))).dx;
    expect(first, lessThan(other));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await shot(tester, 'phone-light-uz-15-books-shelf');

    // IT kitobi: o‘qidim / прочитал
    await tester.ensureVisible(find.byKey(const ValueKey('books-shelf')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('book-it')), 200,
        scrollable: find.descendant(of: find.byKey(const ValueKey('books-shelf')), matching: find.byType(Scrollable)).first);
    await tap(tester, find.byKey(const ValueKey('book-it')));
    expect(find.text('Sun’iy intellekt asoslari'), findsOneWidget);
    expect(find.text('👥 ${tr('uz', 'book_reads')}: 41'), findsOneWidget);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await shot(tester, 'phone-light-uz-16-book');
    await tap(tester, find.byKey(const ValueKey('book-mark')));
    expect(find.text('👥 ${tr('uz', 'book_reads')}: 42'), findsOneWidget);
    expect(find.text(tr('uz', 'book_done')), findsOneWidget);
    await back(tester);
  });

  testWidgets('o‘quvchi ham Oy kitobini ko‘radi; admin kitob qo‘shadi', (tester) async {
    final server = FakeServer(me: FakeServer.student());
    await boot(tester, server, theme: 'dark', lang: 'ru');
    await reveal(tester, find.byKey(const ValueKey('books-shelf')));
    expect(find.byKey(const ValueKey('book-lider')), findsOneWidget);
    await shot(tester, 'phone-dark-ru-books-shelf');

    final admin = FakeServer(me: FakeServer.admin());
    await boot(tester, admin);
    await tap(tester, find.byKey(const ValueKey('quick-admin')));
    await tap(tester, find.byKey(const ValueKey('admin-books')));
    expect(find.byKey(const ValueKey('admin-book-it')), findsOneWidget);
    await shot(tester, 'phone-light-uz-17-admin-books');
    await tap(tester, find.byKey(const ValueKey('admin-book-it')));
    expect(find.byKey(const ValueKey('book-save')), findsOneWidget);
    // bor kitob: tuzatish rejimi — nomi to‘ldirilgan, saqlanadi (o‘qiganlar saqlanadi)
    // существующая книга: режим исправления — поля заполнены, сохраняется
    expect(find.text('Sun’iy intellekt asoslari'), findsOneWidget);
    await shot(tester, 'phone-light-uz-18-book-editor');
    await tester.enterText(find.byKey(const ValueKey('book-title')).first, 'Sun’iy intellekt asoslari (2-nashr)');
    await tap(tester, find.byKey(const ValueKey('book-save')));
    expect(admin.posts.last['path'], '/api/admin/books');
    expect(admin.posts.last['edit'], true);
    expect(admin.posts.last['title'], 'Sun’iy intellekt asoslari (2-nashr)');
    // yangi oy kitobi: muqova va PDF majburiy / новая книга: обложка и PDF обязательны
    await tap(tester, find.byKey(const ValueKey('admin-book-it')));
    await tap(tester, find.byKey(const ValueKey('book-new')));
    await tap(tester, find.byKey(const ValueKey('book-save')));
    expect(find.text(tr('uz', 'book_fill')), findsOneWidget);
  });
}
