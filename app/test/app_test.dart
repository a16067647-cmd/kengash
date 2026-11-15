// Ilova testlari: tarjimalar, kirish oqimi, barcha ekranlar telefon/kompyuter, yorug‘/qorong‘i, uz/ru.
// Тесты приложения: переводы, вход, все экраны на телефоне/компьютере, светлая/тёмная, uz/ru.
// Ekran chegarasidan chiqish (overflow) testni yiqitadi / переполнение экрана роняет тест.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kengash/api.dart';
import 'package:kengash/i18n.dart';
import 'package:kengash/main.dart';
import 'package:kengash/screens/intro.dart';
import 'package:kengash/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

const phone = Size(390, 844);
const desktop = Size(1440, 900);
final shotsDir = Platform.environment['SCREENSHOTS_DIR'];

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(rootBundle.load(f));
    }
    await loader.load();
  }

  await family('Manrope', [
    for (final w in [400, 600, 700, 800]) 'assets/fonts/Manrope-$w.ttf'
  ]);
  await family('JetBrainsMono', ['assets/fonts/JetBrainsMono-400.ttf', 'assets/fonts/JetBrainsMono-700.ttf']);
  final icons = File(
      '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}

Future<AppState> boot(WidgetTester tester, FakeServer server,
    {Size size = phone, String lang = 'uz', String theme = 'light', bool loggedIn = true}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'lang': lang,
    'theme': theme,
    if (loggedIn) 'token': 'tok',
  });
  final s = AppState(api: Api(base: 'http://test', client: server.client()), testMode: true);
  await tester.pumpWidget(KengashApp(state: s));
  await s.init();
  await settle(tester);
  return s;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Ro‘yxatni pastga aylantirib qidiradi / ищет, прокручивая список вниз.
Future<void> reveal(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 25 && f.evaluate().isEmpty; i++) {
    final lists = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    if (lists.evaluate().isEmpty) break;
    await tester.drag(lists.last, const Offset(0, -300), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Orqaga / назад.
Future<void> back(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await settle(tester);
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await reveal(tester, f);
  if (f.evaluate().isEmpty) {
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText()).join(' | ');
    fail('Topilmadi: $f\nEkranda: $texts');
  }
  await tester.ensureVisible(f.first);
  // aylantirish tugashini kutamiz / ждём окончания прокрутки
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(f.first);
  await settle(tester);
}

Future<void> shot(WidgetTester tester, String name) async {
  if (shotsDir == null) return;
  if (!name.contains('intro')) {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }
  await tester.runAsync(() async {
    final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(shotsDir!).createSync(recursive: true);
    File('$shotsDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(loadFonts);

  group('i18n', () {
    test('uz va ru kalitlari bir xil / одинаковые ключи', () {
      final uz = kStrings['uz']!.keys.toSet();
      final ru = kStrings['ru']!.keys.toSet();
      expect(uz.difference(ru), isEmpty, reason: 'ru da yo‘q');
      expect(ru.difference(uz), isEmpty, reason: 'uz da yo‘q');
    });

    test('o‘zbekchada oddiy apostrof yo‘q / нет простого апострофа', () {
      for (final e in kStrings['uz']!.entries) {
        expect(e.value.contains("'"), isFalse, reason: e.key);
      }
    });

    test('koddagi barcha kalitlar lug‘atda bor / все ключи из кода есть в словаре', () {
      final re = RegExp(r"\.t\('([a-z0-9_]+)'\)");
      final missing = <String>{};
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        for (final m in re.allMatches(f.readAsStringSync())) {
          if (!kStrings['uz']!.containsKey(m.group(1))) missing.add('${m.group(1)} (${f.path})');
        }
      }
      expect(missing, isEmpty);
    });
  });

  testWidgets('to‘liq kirish: Telegram → bot orqali ro‘yxat → Bugun', (tester) async {
    final server = FakeServer();
    final s = await boot(tester, server, loggedIn: false);
    expect(find.byKey(const ValueKey('login-tg')), findsOneWidget);
    await shot(tester, 'phone-light-uz-1-login');

    await tap(tester, find.byKey(const ValueKey('login-tg')));
    expect(find.text(tr('uz', 'login_wait_title')), findsOneWidget);
    await shot(tester, 'phone-light-uz-2-login-wait');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(s.loggedIn, isTrue);
    // yangi odam — faqat bitta tugma: botni ochish / новый — одна кнопка: открыть бота
    expect(find.byKey(const ValueKey('open-bot')), findsOneWidget);
    expect(find.text(tr('uz', 'reg_title')), findsOneWidget);
    await shot(tester, 'phone-light-uz-3-register');
    await tap(tester, find.byKey(const ValueKey('open-bot')));

    // botda ro‘yxatdan o‘tdi (o‘quvchi) → ilova o‘zi ochiladi / зарегистрировался в боте → приложение открывается само
    server.me = FakeServer.student();
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.byKey(const ValueKey('hero')), findsOneWidget);
    expect(find.textContaining('Jasur!'), findsOneWidget);
    await shot(tester, 'phone-light-uz-4-today-student');
  });

  testWidgets('tasdiq kutilmoqda: kim tasdiqlashi ko‘rinadi', (tester) async {
    final server = FakeServer(me: FakeServer.pending());
    await boot(tester, server);
    expect(find.text(tr('uz', 'pending_title')), findsOneWidget);
    expect(find.text('Qodirova Nilufar'), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-today')), findsNothing);
    await shot(tester, 'phone-light-uz-5-pending');
    server.me = FakeServer.seated('school', 'it');
    await tester.pump(const Duration(seconds: 16));
    await settle(tester);
    expect(find.byKey(const ValueKey('hero')), findsOneWidget);
  });

  testWidgets('maslahatchi arizani tasdiqlaydi va o‘quvchilarni ko‘radi', (tester) async {
    final server = FakeServer(me: FakeServer.seated('school', 'maslahatchi'));
    server.approvals.add({...FakeServer.pending(), 'id': 'p1', 'name': 'Sobirov Doston', 'direction': 'sport'});
    await boot(tester, server);
    await tap(tester, find.byKey(const ValueKey('today-approvals')));
    expect(find.text('Sobirov Doston'), findsOneWidget);
    await shot(tester, 'phone-light-uz-6-approvals');
    await tap(tester, find.byKey(const ValueKey('approve-p1')));
    expect(server.calls, contains('POST /api/approvals/p1'));
    expect(find.text(tr('uz', 'approvals_none')), findsOneWidget);
    await back(tester);

    await tap(tester, find.byKey(const ValueKey('quick-directory')));
    await tap(tester, find.byKey(const ValueKey('dist-asaka')));
    await tap(tester, find.byKey(const ValueKey('sch-59')));
    expect(find.text('Qodirova Nilufar'), findsOneWidget);
    await shot(tester, 'phone-light-uz-7-school-seats');
    await tap(tester, find.byKey(const ValueKey('students-card')));
    expect(find.text('Olimov Jasur'), findsOneWidget);
    expect(find.text('7-B · 1'), findsOneWidget);
    await shot(tester, 'phone-light-uz-8-students');
  });

  testWidgets('o‘quvchi: faqat o‘z maktabi, vazifa bera olmaydi', (tester) async {
    final server = FakeServer(me: FakeServer.student());
    final s = await boot(tester, server);
    expect(s.isStudent, isTrue);
    expect(s.canGive, isFalse);
    expect(find.byKey(const ValueKey('today-approvals')), findsNothing);
    await tap(tester, find.byKey(const ValueKey('quick-directory')));
    // to‘g‘ridan-to‘g‘ri o‘z maktabi, o‘quvchilar ro‘yxati yo‘q / сразу своя школа, без списка учеников
    expect(find.text('Karimova Madina'), findsOneWidget);
    expect(find.byKey(const ValueKey('students-card')), findsNothing);
    expect(find.byKey(const ValueKey('dist-asaka')), findsNothing);
    await shot(tester, 'phone-light-uz-9-student-school');
  });

  for (final (size, sizeName) in [(phone, 'phone'), (desktop, 'desktop')]) {
    for (final (theme, lang) in [('light', 'uz'), ('dark', 'ru')]) {
      final tag = '$sizeName-$theme-$lang';
      testWidgets('admin ekranlari $tag', (tester) async {
        final server = FakeServer(me: FakeServer.admin());
        await boot(tester, server, size: size, theme: theme, lang: lang);
        expect(find.byKey(const ValueKey('hero')), findsOneWidget);
        await shot(tester, '$tag-today');
        final wide = size == desktop;

        Future<void> open(String id) async {
          if (wide) {
            await tap(tester, find.byKey(ValueKey('side-$id')));
          } else {
            await tap(tester, find.byKey(ValueKey('quick-$id')));
          }
        }

        Future<void> close() async {
          if (!wide) await back(tester);
        }

        // koordinatorlar / координаторы
        await open('directory');
        await shot(tester, '$tag-directory');
        await tap(tester, find.byKey(const ValueKey('dist-asaka')));
        await tap(tester, find.byKey(const ValueKey('sch-59')));
        expect(find.text('Karimova Madina'), findsOneWidget);
        await shot(tester, '$tag-seats');
        await tap(tester, find.text('Karimova Madina'));
        expect(find.byKey(const ValueKey('sheet-tg')), findsOneWidget);
        await shot(tester, '$tag-user-sheet');
        await tester.tapAt(const Offset(10, 10));
        await settle(tester);
        await back(tester);
        await back(tester);
        await close();

        // admin
        await open('admin');
        await shot(tester, '$tag-admin-stats');
        await tap(tester, find.text(tr(lang, 'users')).first);
        expect(find.text('Karimova Madina'), findsOneWidget);
        await shot(tester, '$tag-admin-users');
        await tap(tester, find.text(tr(lang, 'schools')).last);
        await tap(tester, find.byKey(const ValueKey('admin-district')));
        await tap(tester, find.byKey(const ValueKey('district-asaka')));
        await shot(tester, '$tag-admin-schools');
        await close();

        // profil / профиль
        if (wide) {
          await tap(tester, find.byKey(const ValueKey('side-profile')));
        } else {
          await tap(tester, find.byKey(const ValueKey('nav-profile')));
        }
        expect(find.byKey(const ValueKey('row-notify')), findsOneWidget);
        await reveal(tester, find.byKey(const ValueKey('row-delete')));
        expect(find.byKey(const ValueKey('row-delete')), findsOneWidget);
        await shot(tester, '$tag-profile');
        await tap(tester, find.text(tr(lang, 'about')));
        expect(find.text('Mamajonov Bexruz'), findsOneWidget);
        await shot(tester, '$tag-about');
        await back(tester);
        await tap(tester, find.byKey(const ValueKey('row-delete')));
        expect(find.byKey(const ValueKey('del-field')), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await settle(tester);

        // bo‘sh bo‘limlar / пустые разделы
        if (!wide) {
          for (final t in ['channels', 'tasks', 'calendar']) {
            await tap(tester, find.byKey(ValueKey('nav-$t')));
          }
          await shot(tester, '$tag-calendar');
        }
      });
    }
  }

  for (final (size, sizeName) in [(phone, 'phone'), (desktop, 'desktop')]) {
    testWidgets('ochilish animatsiyasi $sizeName: tugmasiz, o‘zi tugaydi', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      var done = 0;
      await tester.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, home: IntroScreen(onDone: () => done++)));
      for (final (ms, name) in [(600, 'a'), (900, 'b'), (1000, 'c'), (900, 'd'), (1200, 'e')]) {
        await tester.pump(Duration(milliseconds: ms));
        await shot(tester, '$sizeName-intro-$name');
      }
      // Hech qanday tugma yo‘q / никаких кнопок
      expect(find.byType(ButtonStyleButton), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
      expect(done, 0);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(done, 1);
    });
  }

  for (final (size, sizeName) in [(phone, 'phone'), (desktop, 'desktop')]) {
    testWidgets('kanallar $sizeName: ro‘yxat, suhbat, yozish, amallar', (tester) async {
      final server = FakeServer(me: FakeServer.seated('school', 'it'));
      final s = await boot(tester, server, size: size);
      // «Bugun»dagi kanallar kartasi / карточка каналов на «Сегодня»
      expect(find.byKey(const ValueKey('today-channels')), findsOneWidget);
      expect(find.text('7 ${tr('uz', 'ch_new_msgs')}'), findsOneWidget);
      if (size == phone) {
        await tap(tester, find.byKey(const ValueKey('nav-channels')));
      } else {
        await tap(tester, find.byKey(const ValueKey('side-channels')));
      }
      expect(find.text('Asaka tumani · IT va sun’iy intellekt'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-channel')), findsNothing);
      await shot(tester, '$sizeName-light-uz-channels');
      await tap(tester, find.byKey(const ValueKey('ch-dd:asaka:it')));
      expect(find.text('Men tayyorman 👍'), findsOneWidget);
      expect(find.text('Tanlov nizomi.pdf'), findsOneWidget);
      expect(find.text(tr('uz', 'msg_deleted')), findsOneWidget);
      await shot(tester, '$sizeName-light-uz-chat');
      await tester.enterText(find.byKey(const ValueKey('composer')), 'Salom hammaga!');
      await tap(tester, find.byKey(const ValueKey('send')));
      expect(server.sent.single['text'], 'Salom hammaga!');
      expect(find.text('Salom hammaga!'), findsOneWidget);
      // xabar amallari / действия с сообщением
      await tester.longPress(find.textContaining('Batafsil', findRichText: true));
      await settle(tester);
      expect(find.byKey(const ValueKey('act-report')), findsOneWidget);
      expect(find.byKey(const ValueKey('act-delete')), findsNothing);
      await shot(tester, '$sizeName-light-uz-actions');
      await tap(tester, find.byKey(const ValueKey('act-reply')));
      expect(find.byKey(const ValueKey('cancel-ctx')), findsOneWidget);
      await shot(tester, '$sizeName-light-uz-reply');
      expect(s.chat.openChannel, 'c-dd');
      await back(tester);
      // e’lon kanali: yozib bo‘lmaydi / канал объявлений: писать нельзя
      await tap(tester, find.byKey(const ValueKey('ch-all')));
      expect(find.byKey(const ValueKey('composer')), findsNothing);
      expect(find.text(tr('uz', 'read_only')), findsOneWidget);
      await shot(tester, '$sizeName-light-uz-announce');
    });
  }

  testWidgets('tuman koordinatori kanal yaratadi', (tester) async {
    final server = FakeServer(me: FakeServer.seated('district', 'it'));
    await boot(tester, server, theme: 'dark', lang: 'ru');
    await tap(tester, find.byKey(const ValueKey('nav-channels')));
    await tap(tester, find.byKey(const ValueKey('new-channel')));
    await tester.enterText(find.byKey(const ValueKey('ch-title')).first, 'Robototexnika');
    await tap(tester, find.byKey(const ValueKey('ch-create')));
    expect(find.text(tr('ru', 'err_pick_mode')), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('mode-announce')));
    // tayyor guruh tanlangan: tumanimdagi maktablar — IT / готовая группа уже выбрана
    expect(find.byKey(const ValueKey('preset-d-schools')), findsOneWidget);
    expect(find.textContaining(tr('ru', 'preset_d_schools')), findsOneWidget);
    await shot(tester, 'phone-dark-ru-create-channel');
    await tap(tester, find.byKey(const ValueKey('ch-create')));
    expect(server.created.single['title_uz'], 'Robototexnika');
    expect(server.lastBody['audience'], [
      {'level': 'school', 'district_ids': ['asaka'], 'directions': ['it']}
    ]);
    expect(server.calls.where((c) => c == 'POST /api/channels').length, 1);
    await shot(tester, 'phone-dark-ru-new-channel-chat');
  });

  testWidgets('maktab koordinatori: bugungi vazifa, hisobot, tadbir', (tester) async {
    final server = FakeServer(me: FakeServer.seated('school', 'it'));
    await boot(tester, server);
    expect(find.text('Robototexnika to‘garagi hisoboti'), findsOneWidget);
    expect(find.text('IT koordinatorlar uchrashuvi'), findsOneWidget);
    await shot(tester, 'phone-light-uz-today-plan');
    await tap(tester, find.byKey(const ValueKey('task-t1')));
    expect(find.byKey(const ValueKey('task-submit')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-accept')), findsNothing);
    await shot(tester, 'phone-light-uz-task');
    await tester.enterText(find.byKey(const ValueKey('report-comment')).first, '15 o‘quvchi qatnashdi');
    await tap(tester, find.byKey(const ValueKey('task-submit')));
    expect(server.posts.last['path'], '/api/tasks/t1/submit');
    expect(server.posts.last['comment'], '15 o‘quvchi qatnashdi');
    await back(tester);
    await tap(tester, find.byKey(const ValueKey('nav-calendar')));
    expect(find.byKey(const ValueKey('new-event')), findsNothing);
    await tap(tester, find.byKey(const ValueKey('event-e1')));
    await tap(tester, find.byKey(const ValueKey('rsvp-yes')));
    expect(server.rsvp, 'yes');
    await shot(tester, 'phone-light-uz-event');
  });

  testWidgets('tuman koordinatori vazifa beradi va hisobotni ko‘radi', (tester) async {
    final server = FakeServer(me: FakeServer.seated('district', 'it'));
    await boot(tester, server, theme: 'dark', lang: 'ru');
    expect(find.byKey(const ValueKey('today-review')), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('nav-tasks')));
    await tap(tester, find.byKey(const ValueKey('new-task')));
    await tester.enterText(find.byKey(const ValueKey('task-title')).first, 'Hisobot yuboring');
    await tap(tester, find.byKey(const ValueKey('when-1')));
    expect(find.byKey(const ValueKey('preset-d-team')), findsNothing); // vazifa faqat pastdagilarga
    await shot(tester, 'phone-dark-ru-task-create');
    await tap(tester, find.byKey(const ValueKey('task-create')));
    final p = server.posts.last;
    expect(p['title'], 'Hisobot yuboring');
    expect(p['audience'], [
      {'level': 'school', 'district_ids': ['asaka'], 'directions': ['it']}
    ]);
    expect(p['deadline'] as int, greaterThan(DateTime.now().millisecondsSinceEpoch ~/ 1000));
    await tap(tester, find.byKey(const ValueKey('task-t1')));
    expect(find.text('41 / 62'), findsOneWidget);
    await shot(tester, 'phone-dark-ru-task-progress');
    await tap(tester, find.byKey(const ValueKey('person-m59it')));
    await tap(tester, find.byKey(const ValueKey('review-accept')));
    expect(server.posts.last['path'], '/api/tasks/t1/review');
    expect(server.posts.last['action'], 'accept');
    await back(tester);
    await tap(tester, find.byKey(const ValueKey('nav-calendar')));
    await tap(tester, find.byKey(const ValueKey('new-event')));
    await tester.enterText(find.byKey(const ValueKey('event-title')).first, 'Uchrashuv');
    await tap(tester, find.byKey(const ValueKey('when-2')));
    await tap(tester, find.byKey(const ValueKey('event-create')));
    expect(server.posts.last['path'], '/api/events');
    await shot(tester, 'phone-dark-ru-calendar');
  });

  testWidgets('admin shikoyatlarni ko‘radi', (tester) async {
    final server = FakeServer(me: FakeServer.admin());
    await boot(tester, server, size: desktop);
    await tap(tester, find.byKey(const ValueKey('side-admin')));
    await tap(tester, find.text(tr('uz', 'reports')));
    expect(find.byKey(const ValueKey('report-r1')), findsOneWidget);
    await shot(tester, 'desktop-light-uz-admin-reports');
    await tap(tester, find.byKey(const ValueKey('rep-del-r1')));
    expect(server.calls, contains('POST /api/admin/reports/r1'));
  });

  testWidgets('ochilish animatsiyasi har safar ko‘rinadi', (tester) async {
    tester.view.physicalSize = phone * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    for (var launch = 0; launch < 2; launch++) {
      // avvalgi ochilishdan qolgan sozlamalar bilan ham / даже с настройками прошлого запуска
      SharedPreferences.setMockInitialValues({'intro_done': true, 'lang': 'uz'});
      final s = AppState(api: Api(base: 'http://test', client: FakeServer().client()));
      await tester.pumpWidget(KengashApp(key: ValueKey(launch), state: s));
      await s.init();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(IntroScreen), findsOneWidget, reason: 'launch $launch');
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(IntroScreen), findsNothing);
      expect(s.introDone, isTrue);
    }
  });

  testWidgets('maktab koordinatori: admin yo‘q, chiqish ishlaydi', (tester) async {
    final server = FakeServer(me: FakeServer.seated('school', 'it'));
    final s = await boot(tester, server);
    expect(find.byKey(const ValueKey('quick-admin')), findsNothing);
    await tap(tester, find.byKey(const ValueKey('nav-profile')));
    await tap(tester, find.byKey(const ValueKey('row-logout')));
    expect(s.loggedIn, isFalse);
    expect(find.byKey(const ValueKey('login-tg')), findsOneWidget);
  });

  testWidgets('tuman koordinatori: admin yo‘q', (tester) async {
    final server = FakeServer(me: FakeServer.seated('district', 'it'));
    await boot(tester, server, size: desktop);
    expect(find.byKey(const ValueKey('side-directory')), findsOneWidget);
    expect(find.byKey(const ValueKey('side-admin')), findsNothing);
  });
}
