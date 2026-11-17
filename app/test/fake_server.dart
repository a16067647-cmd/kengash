import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Testlar uchun soxta server / фейковый сервер для тестов.
class FakeServer {
  Map<String, dynamic> me;
  int statusPolls = 0;
  final List<String> calls = [];
  final List<Map<String, dynamic>> sent = [];
  final List<Map<String, dynamic>> created = [];
  Map<String, dynamic> lastBody = {};
  final List<Map<String, dynamic>> posts = [];
  String rsvp = '';
  String myStatus = 'new';
  final List<Map<String, dynamic>> approvals = [];
  int points = 0;
  bool iRead = false;
  int readCount = 41;
  bool booksCovers = false;
  bool feedbackDone = false;

  Map<String, dynamic> task({bool given = false}) => {
        'id': 't1', 'title': 'Robototexnika to‘garagi hisoboti', 'description': 'To‘garakda nechta o‘quvchi borligini yozing.',
        'deadline': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
        'photo_required': false, 'created_at': 0,
        'by': {'id': 'ait', 'name': 'Asaka IT', 'photo': '', 'direction': 'it'},
        'total': 62, 'counts': {'new': 20, 'submitted': 3, 'accepted': 38, 'returned': 1}, 'done': 41,
        'is_giver': given, 'overdue': false,
        if (!given) 'my': {'status': myStatus, 'comment': '', 'review_note': '', 'photos': [], 'submitted_at': 0, 'photo_urls': []},
      };

  Map<String, dynamic> event() => {
        'id': 'e1', 'title': 'IT koordinatorlar uchrashuvi', 'description': '', 'place': 'Asaka, Yoshlar markazi',
        'starts_at': DateTime.now().add(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000, 'ends_at': 0,
        'by': {'id': 'ait', 'name': 'Asaka IT'}, 'is_organizer': me['level'] != 'school', 'guests': 62, 'yes': 40, 'no': 3, 'my_rsvp': rsvp,
      };

  static Map<String, dynamic> ch(String id, String key, String uz, String ru,
          {String mode = 'group',
          int unread = 0,
          bool canPost = true,
          String kind = 'auto',
          String role = 'member',
          String text = ''}) =>
      {
        'id': id,
        'kind': kind,
        'auto_key': kind == 'auto' ? key : null,
        'title_uz': uz,
        'title_ru': ru,
        'description': '',
        'icon': kind == 'custom' ? '🏆' : '',
        'mode': mode,
        'members': 12,
        'created_by': 'u1',
        'last_msg_at': 1794600000 - unread,
        'seq': 10,
        'unread': unread,
        'muted': false,
        'role': role,
        'member': true,
        'can_post': canPost,
        'can_manage': kind == 'custom',
        'is_mod': role != 'member',
        'pinned': null,
        'last': text.isEmpty
            ? null
            : {
                'text': text,
                'deleted': false,
                'kind': '',
                'user_name': 'Karimova Madina',
                'user_id': 'm59it',
                'created_at': 1794600000
              },
      };

  List<Map<String, dynamic>> channels() => [for (final x in _channels()) {...x, 'can_media': me['kind'] != 'student'}];

  List<Map<String, dynamic>> _channels() => [
        ch('c-all', 'all', 'Kengash e’lonlari', 'Объявления Kengash',
            mode: 'announce',
            unread: 2,
            canPost: me['role'] == 'admin',
            role: me['role'] == 'admin' ? 'admin' : 'member',
            text: 'Ertaga yig‘ilish soat 14:00 da'),
        ch('c-dd', 'dd:asaka:it', 'Asaka tumani · IT va sun’iy intellekt', 'Асакинский район · IT и искусственный интеллект',
            unread: 5, text: 'Kim tanlovga tayyor?'),
        ch('c-sch', 'school:s59', '59-maktab jamoasi', 'Команда: Школа №59', text: 'Rahmat!'),
        if (me['role'] == 'admin')
          {...ch('c-chat', 'chat:s60', '60-maktab chati', 'Чат: Школа №60', text: 'Salom hammaga'), 'member': false},
        ch('c-cu', '', 'IT tanlovi 2026', 'IT tanlovi 2026',
            kind: 'custom', role: 'owner', mode: 'announce', text: 'Ro‘yxat tayyor'),
      ];

  List<Map<String, dynamic>> messagesFor(String cid) {
    final madina = {'id': 'm59it', 'name': 'Karimova Madina', 'photo': '', 'direction': 'it', 'level': 'school', 'role': 'user'};
    final sardor = {
      'id': 'm59l',
      'name': 'Toshpo‘latov Sardorbek',
      'photo': '',
      'direction': 'lider',
      'level': 'school',
      'role': 'user'
    };
    final mine = {
      'id': me['id'],
      'name': me['name'],
      'photo': '',
      'direction': me['direction'],
      'level': me['level'],
      'role': me['role']
    };
    final t = 1794600000;
    return [
      for (final m in sent.reversed) m,
      {
        'id': 'x5',
        'channel_id': cid,
        'seq': 5,
        'created_at': t,
        'user': mine,
        'text': 'Men tayyorman 👍',
        'attachments': [],
        'reply': {'id': 'x3', 'text': 'Kim tanlovga tayyor?', 'user': madina},
        'edited': false,
        'deleted': false,
        'seen': 9
      },
      {
        'id': 'x4',
        'channel_id': cid,
        'seq': 4,
        'created_at': t - 60,
        'user': sardor,
        'text': '',
        'attachments': [
          {'kind': 'file', 'path': '$cid/a.pdf', 'name': 'Tanlov nizomi.pdf', 'size': 248000, 'url': ''}
        ],
        'reply': null,
        'edited': false,
        'deleted': false,
        'seen': 8
      },
      {
        'id': 'x3',
        'channel_id': cid,
        'seq': 3,
        'created_at': t - 120,
        'user': madina,
        'text': 'Kim tanlovga tayyor? Batafsil: https://kelajak.uz',
        'attachments': [],
        'reply': null,
        'edited': true,
        'deleted': false,
        'seen': 10
      },
      {
        'id': 'x2',
        'channel_id': cid,
        'seq': 2,
        'created_at': t - 180,
        'user': madina,
        'text': '',
        'attachments': [
          {'kind': 'voice', 'path': '$cid/v.m4a', 'name': 'voice.m4a', 'size': 40000, 'duration': 14, 'url': ''}
        ],
        'reply': null,
        'edited': false,
        'deleted': false
      },
      {
        'id': 'x1',
        'channel_id': cid,
        'seq': 1,
        'created_at': t - 86400,
        'user': sardor,
        'text': '',
        'attachments': [],
        'reply': null,
        'edited': false,
        'deleted': true
      },
    ];
  }

  FakeServer({Map<String, dynamic>? me}) : me = me ?? newUser();

  static Map<String, dynamic> newUser() => {
        'id': 'u1',
        'name': 'Ali Valiyev',
        'tg_username': 'ali_v',
        'photo': '',
        'phone': '+998901234567',
        'level': null,
        'place_id': null,
        'direction': null,
        'place': null,
        'role': 'user',
        'status': 'new',
        'kind': '',
        'class_name': '',
        'consent': false,
        'needs_registration': true,
        'can_give': false,
        'can_create_channels': false,
        'locked': false,
        'notify_tg': true,
        'paid_until': 0,
        'payments': false,
      };

  static const school59 = {
    'level': 'school',
    'id': 's59',
    'name_uz': '59-maktab',
    'name_ru': 'Школа №59',
    'district_id': 'asaka',
    'district_uz': 'Asaka tumani',
    'district_ru': 'Асакинский район',
  };

  static Map<String, dynamic> seated(String level, String direction, {String role = 'user'}) {
    final place = switch (level) {
      'region' => {'level': 'region', 'id': 'andijon', 'name_uz': 'Andijon viloyati', 'name_ru': 'Андижанская область'},
      'district' => {
          'level': 'district',
          'id': 'asaka',
          'name_uz': 'Asaka tumani',
          'name_ru': 'Асакинский район',
          'region_id': 'andijon'
        },
      _ => school59,
    };
    return {
      ...newUser(),
      'level': level,
      'place_id': place['id'],
      'direction': direction,
      'place': place,
      'role': role,
      'status': 'active',
      'kind': direction == 'maslahatchi' ? 'maslahatchi' : 'coordinator',
      'consent': true,
      'needs_registration': false,
      'can_give': true,
      'can_create_channels': level != 'school' || role == 'admin' || direction == 'maslahatchi',
    };
  }

  static Map<String, dynamic> student() => {
        ...seated('school', 'it'),
        'id': 'st1',
        'name': 'Olimov Jasur',
        'direction': null,
        'kind': 'student',
        'class_name': '7-B',
        'can_give': false,
        'can_create_channels': false,
      };

  static Map<String, dynamic> pending() => {
        ...seated('school', 'it'),
        'status': 'pending',
        'can_give': false,
        'approvers': [
          {'id': 'mas', 'name': 'Qodirova Nilufar', 'tg_username': 'nilufar_m', 'photo': '', 'direction': 'maslahatchi', 'level': 'school', 'place': school59, 'kind': 'maslahatchi'}
        ],
      };


  /// Xodim: Asaka Kelajak Markazi direktori / сотрудник: директор Kelajak Markazi Асаки.
  static Map<String, dynamic> staffUser({List<String> powers = const ['announce', 'plan', 'view']}) => {
        ...seated('district', 'it'),
        'id': 'dir1',
        'name': 'Karimova Dilnoza',
        'direction': null,
        'kind': 'staff',
        'title': 'Asaka Kelajak Markazi direktori',
        'powers': powers,
        'can_give': powers.contains('plan'),
        'can_view_area': powers.contains('view'),
        'can_announce': powers.contains('announce'),
        'can_create_channels': false,
      };

  final List<Map<String, dynamic>> staff = [];

  static Map<String, dynamic> admin() => {
        ...newUser(),
        'name': 'Mamajonov Bexruz',
        'tg_username': 'behruz_sk',
        'role': 'admin',
        'status': 'active',
        'consent': true,
        'needs_registration': false,
        'can_give': true,
        'can_create_channels': true,
      };

  static final directions = [
    for (final d in [
      ['lider', 'Lider', 'Лидер'],
      ['talim', 'Ta’lim', 'Образование'],
      ['ijtimoiy', 'Ijtimoiy tashabbus', 'Социальная инициатива'],
      ['it', 'IT va sun’iy intellekt', 'IT и искусственный интеллект'],
      ['media', 'Media', 'Медиа'],
      ['ekologiya', 'Ekologiya', 'Экология'],
      ['sport', 'Sport', 'Спорт'],
      ['madaniyat', 'Madaniyat', 'Культура'],
    ])
      {'id': d[0], 'uz': d[1], 'ru': d[2]}
  ];

  static final districts = [
    {
      'id': 'and-shahar',
      'region_id': 'andijon',
      'name_uz': 'Andijon shahri',
      'name_ru': 'г. Андижан',
      'kind': 'shahar',
      'sort': 0,
      'hidden': 0
    },
    {
      'id': 'asaka',
      'region_id': 'andijon',
      'name_uz': 'Asaka tumani',
      'name_ru': 'Асакинский район',
      'kind': 'tuman',
      'sort': 3,
      'hidden': 0
    },
    {
      'id': 'baliqchi',
      'region_id': 'andijon',
      'name_uz': 'Baliqchi tumani',
      'name_ru': 'Балыкчинский район',
      'kind': 'tuman',
      'sort': 4,
      'hidden': 0
    },
    {
      'id': 'qorgontepa',
      'region_id': 'andijon',
      'name_uz': 'Qo‘rg‘ontepa tumani',
      'name_ru': 'Кургантепинский район',
      'kind': 'tuman',
      'sort': 10,
      'hidden': 0
    },
  ];

  static final schools = [
    for (final n in [58, 59, 60])
      {
        'id': 's$n',
        'district_id': 'asaka',
        'number': n,
        'name': '',
        'hidden': 0,
        'filled': n == 59 ? 3 : 0,
        'name_uz': '$n-maktab',
        'name_ru': 'Школа №$n'
      }
  ];

  Map<String, dynamic> person(String id, String name, String level, String dir, {bool phone = false}) => {
        ...seated(level, dir),
        'id': id,
        'name': name,
        'tg_username': id,
        if (phone) 'phone': '+998900000000' else 'phone': null,
      }..removeWhere((k, v) => v == null);

  http.Client client() => MockClient((req) async {
        final path = req.url.path;
        calls.add('${req.method} $path');
        Map<String, dynamic> body = {};
        if (req.body.isNotEmpty) body = jsonDecode(req.body) as Map<String, dynamic>;
        Object? out;
        switch ('${req.method} $path') {
          case 'GET /api/meta':
            out = {
              'regions': [
                {'id': 'andijon', 'name_uz': 'Andijon viloyati', 'name_ru': 'Андижанская область'}
              ],
              'districts': districts,
              'directions': directions,
              'legal_version': '2026-11-14',
              'bot': 'KengashAppBot',
            };
          case 'POST /api/auth/telegram/start':
            out = {'id': 'r1', 'url': 'https://t.me/KengashAppBot?start=login_r1'};
          case 'GET /api/auth/telegram/status':
            statusPolls++;
            out = statusPolls < 2 ? {'status': 'waiting'} : {'status': 'done', 'token': 'tok', 'me': me};
          case 'GET /api/me':
            out = me;
          case 'GET /api/schools':
            out = {'schools': schools};
          case 'GET /api/seats':
            final level = req.url.queryParameters['level']!;
            final staff = me['role'] == 'admin' || (me['level'] == 'school' && me['kind'] != 'student');
            out = {
              'place': school59,
              'students': 2,
              'can_see_students': staff,
              'seats': [
                if (level == 'school')
                  {
                    'direction': 'maslahatchi',
                    'user': person('mas', 'Qodirova Nilufar', level, 'maslahatchi'),
                    'can_manage': me['role'] == 'admin',
                  },
                for (final d in directions)
                  {
                    'direction': d['id'],
                    'user': d['id'] == 'it'
                        ? person('m59it', 'Karimova Madina', level, 'it', phone: me['role'] == 'admin')
                        : d['id'] == 'lider'
                            ? person('m59l', 'Toshpo‘latov Sardorbek Akmaljon o‘g‘li', level, 'lider')
                            : null,
                    'can_manage': me['role'] == 'admin' || me['level'] == 'district',
                  }
              ],
            };
          case 'GET /api/schools/s59/students':
            out = {
              'students': [
                {...student(), 'phone': '+998901112233'},
                {...student(), 'id': 'st2', 'name': 'Karimova Zuhra', 'class_name': '9-A'},
              ]
            };
          case 'GET /api/admin/staff':
            out = {'staff': staff};
          case 'POST /api/admin/staff':
            lastBody = body;
            final u = {
              ...staffUser(powers: [for (final p in body['powers'] as List) p.toString()]),
              'id': 'new${staff.length}', 'name': body['name'], 'title': body['title'], 'linked': false, 'status': 'active',
            };
            staff.add(u);
            out = u;
          case 'GET /api/approvals':
            out = {'users': approvals};
          case 'POST /api/approvals/p1':
            approvals.clear();
            out = {'ok': true};
          case 'GET /api/books':
            final mine = me['direction'];
            final list = [
              for (final (i, d) in directions.indexed)
                {
                  'id': 'b${d['id']}',
                  'direction': d['id'],
                  'title': ['Yetakchilik san’ati', 'O‘qishni o‘rganish', 'Kichik qadamlar', 'Sun’iy intellekt asoslari',
                    'Hikoya qilish sirlari', 'Yashil sayyora', 'Chempion odatlari', 'Ming bir kecha'][i],
                  'author': 'Muallif ${i + 1}',
                  'description': 'Bu oy o‘qiladigan kitob: qisqa, foydali va qiziqarli. Har kuni 20 bet.',
                  'month': 'Noyabr 2026',
                  'cover_url': booksCovers ? 'https://storage.test/books/${d['id']}.jpg' : '',
                  'pdf_url': 'https://storage.test/books/${d['id']}.pdf',
                  'reads': d['id'] == 'it' ? readCount : 12 + i,
                  'my_read': d['id'] == 'it' && iRead,
                  'pdf_size': 3000000,
                  'created_at': 0,
                  'colors': d['id'] == 'it' ? ['#e4ded2', '#cdb682', '#979188'] : [],
                  'readers': d['id'] == 'it'
                      ? [
                          {'id': 'r1', 'name': 'Karimova Madina', 'photo': ''},
                          {'id': 'r2', 'name': 'Yusupov Jasur', 'photo': ''},
                          {'id': 'r3', 'name': 'Aliyeva Nodira', 'photo': ''},
                        ]
                      : [],
                }
            ]..sort((a, b) => (a['direction'] == mine ? 0 : 1).compareTo(b['direction'] == mine ? 0 : 1));
            out = {'books': list};
          case 'POST /api/books/bit/read':
            iRead = body['read'] == true;
            readCount += iRead ? 1 : -1;
            out = {'ok': true, 'reads': readCount, 'my_read': iRead};
          case 'GET /api/rating':
            final lvl = req.url.queryParameters['level'] ?? (me['level'] == 'district' ? 'district' : 'school');
            out = {
              'quarter': '2026 · IV',
              'level': lvl,
              'place_id': lvl == 'school' ? 'asaka' : 'andijon',
              'people': [
                {'rank': 1, 'score': 7, 'user': person('m59it', 'Karimova Madina', lvl, 'it')},
                {'rank': 2, 'score': 4, 'user': person('m59l', 'Toshpo‘latov Sardorbek', lvl, 'lider')},
                {'rank': 3, 'score': 2, 'user': {...me}},
                {'rank': 4, 'score': 0, 'user': person('m60it', 'Yusupov Jasur', lvl, 'it')},
                {'rank': 5, 'score': -2, 'user': person('m61s', 'Aliyeva Nodira', lvl, 'sport')},
              ],
              'total': 5,
              'me': {'score': 2, 'rank': 3, 'rated': me['role'] != 'admin'},
            };
          case 'GET /api/users/search':
            out = {
              'users': [person('m59it', 'Karimova Madina', 'school', 'it')]
            };
          case 'GET /api/admin/stats':
            out = {
              'users': 128,
              'seated': 120,
              'active_week': 97,
              'schools': 640,
              'seats_total': 5256,
              'by_district': [
                for (final d in districts)
                  {'id': d['id'], 'name_uz': d['name_uz'], 'name_ru': d['name_ru'], 'users': 12, 'schools': 40}
              ],
            };
          case 'GET /api/admin/users':
            out = {
              'total': 2,
              'users': [
                person('m59it', 'Karimova Madina', 'school', 'it', phone: true),
                {...newUser(), 'id': 'x', 'name': 'Yangi bola', 'status': 'blocked'}
              ],
            };
          case 'GET /api/today':
            out = {'tasks': me['level'] == 'school' && myStatus == 'new' ? [task()] : [], 'events': [event()], 'to_review': me['level'] == 'school' ? 0 : 3};
          case 'GET /api/tasks':
            final given = req.url.queryParameters['box'] == 'given';
            out = {'tasks': given ? [task(given: true)] : (me['level'] == 'school' ? [task()] : []), 'can_give': me['level'] != 'school' || me['role'] == 'admin'};
          case 'POST /api/tasks':
            posts.add({'path': path, ...body});
            out = {...task(given: true), 'total': 12};
          case 'GET /api/events':
            out = {'events': [event()], 'can_create': me['level'] != 'school' || me['role'] == 'admin'};
          case 'POST /api/events':
            posts.add({'path': path, ...body});
            out = {...event(), 'guests': 12};
          case 'GET /api/channels':
            out = {
              'channels': [...channels(), ...created],
              'can_create': me['role'] == 'admin' || me['level'] == 'district' || me['level'] == 'region'
            };
          case 'POST /api/channels':
            lastBody = body;
            final c = ch('c-new', '', body['title'] as String, body['title'] as String,
                kind: 'custom', role: 'owner', mode: body['mode'] as String);
            c['members'] = 7;
            created.add(c);
            out = c;
          case 'GET /api/admin/reports':
            out = {
              'reports': [
                {
                  'id': 'r1',
                  'reason': 'insult',
                  'note': '',
                  'created_at': 1794600000,
                  'channel_id': 'c-sch',
                  'status': 'open',
                  'channel': {'title_uz': '59-maktab jamoasi', 'title_ru': 'Команда: Школа №59'},
                  'message': messagesFor('c-sch')[2],
                  'reporter': person('m59l', 'Toshpo‘latov Sardorbek', 'school', 'lider')
                },
                if (!feedbackDone)
                  {
                    'id': 'f1',
                    'kind': 'feedback',
                    'reason': 'taklif',
                    'note': 'Kitoblar uchun audio versiya ham bo‘lsa zo‘r bo‘lardi!',
                    'created_at': 1794600000,
                    'status': 'open',
                    'reply': '',
                    'photo_url': '',
                    'reporter': {...student(), 'tg_username': 'jasur_o'},
                  },
              ]
            };
          case 'POST /api/admin/feedback/f1/reply':
            posts.add({'path': path, ...body});
            feedbackDone = true;
            out = {'ok': true};
          case 'GET /api/admin/activity':
            out = {
              'inactive_count': 3,
              'inactive': [
                {...person('m60it', 'Yusupov Jasur', 'school', 'it'), 'last_seen': 0}
              ],
              'districts': [
                for (final (i, d) in districts.indexed)
                  {'id': d['id'], 'name_uz': d['name_uz'], 'name_ru': d['name_ru'], 'tasks': 20, 'done_pct': 40 + i * 15,
                    'schools': 60, 'schools_empty': 50 - i * 10}
              ],
              'top_schools': [
                {'place': school59, 'messages': 128}
              ],
            };
          case 'POST /api/admin/broadcast/count':
            out = {'count': (body['filter'] as Map).isEmpty ? 1240 : 37};
          case 'POST /api/admin/export':
            posts.add({'path': path, ...body});
            out = {'url': 'https://storage.test/exports/x.xlsx', 'size': 1000};
          case 'POST /api/auth/logout':
            out = {'ok': true};
          default:
            final seg = path.split('/');
            if (req.method == 'GET' && path == '/api/tasks/t1') {
              out = {
                ...task(given: me['level'] != 'school'),
                'can_review': me['level'] != 'school',
                'people': me['level'] == 'school'
                    ? []
                    : [
                        {'user': person('m59it', 'Karimova Madina', 'school', 'it'), 'status': 'submitted', 'comment': '15 o‘quvchi qatnashdi',
                          'review_note': '', 'photos': [], 'photo_urls': [], 'submitted_at': 0, 'can_rate': true, 'points': points},
                        {'user': person('m60it', 'Yusupov Jasur', 'school', 'it'), 'status': 'new', 'comment': '', 'review_note': '',
                          'photos': [], 'photo_urls': [], 'submitted_at': 0, 'can_rate': true, 'points': 0},
                      ],
              };
            } else if (req.method == 'POST' && path.startsWith('/api/tasks/t1/')) {
              posts.add({'path': path, ...body});
              if (path.endsWith('/submit')) myStatus = 'submitted';
              if (path.endsWith('/rate')) points = body['value'] as int;
              out = {'ok': true};
            } else if (req.method == 'GET' && path == '/api/events/e1') {
              out = {
                ...event(),
                if (me['level'] != 'school')
                  'people': [
                    {'user': person('m59it', 'Karimova Madina', 'school', 'it'), 'rsvp': 'yes', 'can_mark': true, 'came': null},
                    {'user': person('m60it', 'Yusupov Jasur', 'school', 'it'), 'rsvp': '', 'can_mark': true, 'came': false},
                  ],
              };
            } else if (req.method == 'POST' && path == '/api/events/e1/attendance') {
              posts.add({'path': path, ...body});
              out = {'ok': true};
            } else if (req.method == 'POST' && path.startsWith('/api/admin/staff/')) {
              lastBody = body;
              final id = path.split('/').last;
              approvals.removeWhere((x) => x['id'] == id);
              out = {'ok': true};
            } else if (req.method == 'POST' && path == '/api/events/e1/rsvp') {
              rsvp = body['rsvp'] as String;
              posts.add({'path': path, ...body});
              out = {'ok': true};
            } else if (req.method == 'GET' && seg.length == 4 && seg[2] == 'channels') {
              out = [...channels(), ...created].firstWhere((c) => c['id'] == seg[3]);
            } else if (req.method == 'GET' && path.endsWith('/messages')) {
              out = {'messages': messagesFor(seg[3]), 'has_more': false, 'my_read': 5};
            } else if (req.method == 'GET' && path.endsWith('/members')) {
              out = {
                'members': [
                  {...person('m59it', 'Karimova Madina', 'school', 'it'), 'channel_role': 'member'},
                  {...me, 'channel_role': 'owner'},
                ]
              };
            } else if (req.method == 'POST' && path.endsWith('/messages')) {
              final m = {
                'id': 'new${sent.length}',
                'channel_id': seg[3],
                'seq': 100 + sent.length,
                'created_at': 1794600100,
                'user': {'id': me['id'], 'name': me['name'], 'photo': '', 'direction': me['direction']},
                'text': body['text'],
                'attachments': body['attachments'] ?? [],
                'reply': null,
                'edited': false,
                'deleted': false,
              };
              sent.add(m);
              out = m;
            } else {
              if (req.method == 'POST') posts.add({'path': path, ...body});
              out = {'ok': true, 'count': 37};
            }
        }
        return http.Response.bytes(utf8.encode(jsonEncode(out)), 200, headers: {'content-type': 'application/json'});
      });
}
