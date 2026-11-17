// «Mening yo‘lim» — portfolio va ochiq havola / портфолио и открытая ссылка.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show boot, shot, tap, loadFonts, reveal;
import 'fake_server.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('portfolio: statistika, sertifikat, ochiq havola', (tester) async {
    final server = FakeServer(me: FakeServer.seated('school', 'it'));
    await boot(tester, server);
    await tap(tester, find.byKey(const ValueKey('nav-profile')));
    await reveal(tester, find.byKey(const ValueKey('row-portfolio')));
    await tap(tester, find.byKey(const ValueKey('row-portfolio')));
    expect(find.text('14'), findsOneWidget);
    expect(find.text('2/48'), findsOneWidget);
    await shot(tester, 'phone-light-uz-portfolio');
    await tap(tester, find.byKey(const ValueKey('pf-share-switch')));
    expect(server.posts.last['path'], '/api/portfolio/share');
    expect(find.byKey(const ValueKey('pf-open')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await reveal(tester, find.text('Robototexnika to‘garagi hisoboti'));
    expect(find.text('Robototexnika to‘garagi hisoboti'), findsOneWidget);
  });
}
