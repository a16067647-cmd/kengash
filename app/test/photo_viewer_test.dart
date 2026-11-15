import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kengash/screens/media.dart';
import 'package:kengash/state.dart';

import 'app_test.dart' show boot, shot, loadFonts;
import 'fake_server.dart';
import 'png_http.dart';

void main() {
  setUpAll(loadFonts);
  testWidgets('surat to‘liq ekranda ochiladi / фото открывается на весь экран', (tester) async {
    HttpOverrides.global = PngHttp(await makePng(tester));
    addTearDown(() => HttpOverrides.global = null);
    final server = FakeServer(me: FakeServer.admin());
    final s = await boot(tester, server);
    s.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const PhotoViewer(url: 'https://x/a.jpg')));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    // surat butun ekranni egallashi kerak (xato: 48 px balandlikda tepada qolardi)
    // фото должно занимать весь экран (баг: сжималось до 48 px сверху)
    final r = tester.getRect(find.byKey(const ValueKey('photo-full')));
    expect(r.size, tester.view.physicalSize / tester.view.devicePixelRatio);
    await shot(tester, 'phone-light-uz-photo-viewer');
    expect(s.loggedIn, isTrue);
  });
}
