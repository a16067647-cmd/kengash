import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Testlar uchun soxta server / фейковый сервер для тестов.
class FakeServer {
  Map<String, dynamic> me;
  int statusPolls = 0;
  final List<String> calls = [];

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
          case 'POST /api/auth/logout':
            out = {'ok': true};
          default:
            out = {'ok': true};
        }
        return http.Response.bytes(utf8.encode(jsonEncode(out)), 200, headers: {'content-type': 'application/json'});
      });
}
