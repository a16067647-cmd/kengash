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

  List<Map<String, dynamic>> channels() => [
        ch('c-all', 'all', 'Kengash e’lonlari', 'Объявления Kengash',
            mode: 'announce',
            unread: 2,
            canPost: me['role'] == 'admin',
            role: me['role'] == 'admin' ? 'admin' : 'member',
            text: 'Ertaga yig‘ilish soat 14:00 da'),
        ch('c-dd', 'dd:asaka:it', 'Asaka tumani · IT va sun’iy intellekt', 'Асакинский район · IT и искусственный интеллект',
            unread: 5, text: 'Kim tanlovga tayyor?'),
        ch('c-sch', 'school:s59', '59-maktab jamoasi', 'Команда: Школа №59', text: 'Rahmat!'),
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
        'status': 'active',
        'consent': false,
        'needs_seat': true,
        'needs_profile': true,
        'can_keys': false,
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
      'consent': true,
      'needs_seat': false,
      'needs_profile': false,
      'can_keys': level != 'school' || role == 'admin',
    };
  }

  static Map<String, dynamic> admin() => {
        ...newUser(),
        'name': 'Mamajonov Bexruz',
        'tg_username': 'behruz_sk',
        'role': 'admin',
        'consent': true,
        'needs_seat': false,
        'needs_profile': false,
        'can_keys': true,
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
          case 'POST /api/me/redeem-key':
            if ((body['code'] as String).replaceAll('-', '') != 'KNGABCD2345') {
              return http.Response(jsonEncode({'error': 'bad_key'}), 400);
            }
            me = {...seated('school', 'it'), 'needs_profile': true, 'consent': false};
            out = me;
          case 'POST /api/me/profile':
            me = {...me, 'name': body['name'], 'needs_profile': false, 'consent': true};
            out = me;
          case 'GET /api/schools':
            out = {'schools': schools};
          case 'GET /api/seats':
            final level = req.url.queryParameters['level']!;
            out = {
              'place': school59,
              'seats': [
                for (final d in directions)
                  {
                    'direction': d['id'],
                    'user': d['id'] == 'it'
                        ? person('m59it', 'Karimova Madina', level, 'it', phone: me['role'] == 'admin')
                        : d['id'] == 'lider'
                            ? person('m59l', 'Toshpo‘latov Sardorbek Akmaljon o‘g‘li', level, 'lider')
                            : null,
                    'contact': d['id'] == 'sport' ? 'asaka_sport' : '',
                    'can_manage': me['role'] == 'admin' || me['level'] == 'district',
                  }
              ],
            };
          case 'GET /api/key-contacts':
            out = {
              'contacts': [
                {'kind': 'user', 'user': person('ait', 'Asaka IT', 'district', 'it')},
                {
                  'kind': 'contact',
                  'level': 'region',
                  'place': seated('region', 'it')['place'],
                  'direction': 'it',
                  'tg_username': 'viloyat_it'
                },
              ],
              'admin': admin(),
              'taken': false,
            };
          case 'GET /api/users/search':
            out = {
              'users': [person('m59it', 'Karimova Madina', 'school', 'it')]
            };
          case 'GET /api/keys':
            out = {
              'keys': [
                {
                  'id': 'a' * 16,
                  'hint': 'X7Q2',
                  'level': 'school',
                  'place_id': 's59',
                  'direction': 'it',
                  'place': school59,
                  'state': 'active',
                  'created_at': 0,
                  'expires_at': 0,
                  'used_name': ''
                },
                {
                  'id': 'b' * 16,
                  'hint': 'M3RD',
                  'level': 'school',
                  'place_id': 's58',
                  'direction': 'it',
                  'place': school59,
                  'state': 'used',
                  'created_at': 0,
                  'expires_at': 0,
                  'used_name': 'Karimova Madina'
                },
              ]
            };
          case 'POST /api/keys':
            final seats = (body['seats'] as List).cast<Map>();
            out = {
              'keys': [
                for (final (i, x) in seats.indexed) {...x, 'code': 'KNG-TEST-${1000 + i}', 'place': school59, 'expires_at': 0}
              ],
              'skipped': [],
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
          case 'GET /api/channels':
            out = {
              'channels': [...channels(), ...created],
              'can_create': me['role'] == 'admin' || me['level'] == 'district' || me['level'] == 'region'
            };
          case 'POST /api/channels':
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
              ]
            };
          case 'POST /api/auth/logout':
            out = {'ok': true};
          default:
            final seg = path.split('/');
            if (req.method == 'GET' && seg.length == 4 && seg[2] == 'channels') {
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
              out = {'ok': true};
            }
        }
        return http.Response.bytes(utf8.encode(jsonEncode(out)), 200, headers: {'content-type': 'application/json'});
      });
}
