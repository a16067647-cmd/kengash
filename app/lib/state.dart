import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sound.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'chat.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart' show AppToast;

/// Boshlang‘ich ro‘yxat (server javob bermaguncha) / начальный список (пока сервер не ответил).
const List<Map<String, dynamic>> kFallbackDirections = [
  {'id': 'lider', 'uz': 'Lider', 'ru': 'Лидер'},
  {'id': 'talim', 'uz': 'Ta’lim', 'ru': 'Образование'},
  {'id': 'ijtimoiy', 'uz': 'Ijtimoiy tashabbus', 'ru': 'Социальная инициатива'},
  {'id': 'it', 'uz': 'IT va sun’iy intellekt', 'ru': 'IT и искусственный интеллект'},
  {'id': 'media', 'uz': 'Media', 'ru': 'Медиа'},
  {'id': 'ekologiya', 'uz': 'Ekologiya', 'ru': 'Экология'},
  {'id': 'sport', 'uz': 'Sport', 'ru': 'Спорт'},
  {'id': 'madaniyat', 'uz': 'Madaniyat', 'ru': 'Культура'},
];

typedef Json = Map<String, dynamic>;

/// APK raqami (CI: --dart-define=BUILD=N). 0 — mahalliy/test yig‘ish.
/// Номер сборки APK (CI: --dart-define=BUILD=N). 0 — локальная/тестовая сборка.
const int kAppBuild = int.fromEnvironment('BUILD');

/// Saytda: {"build": N, "min": M, "apk": "Kengash.apk"} — CI har chiqishda yozadi.
/// На сайте: {"build": N, "min": M, "apk": "Kengash.apk"} — CI пишет при каждом выпуске.
const String kSiteUrl = 'https://a16067647-cmd.github.io/kengash/';

class AppState extends ChangeNotifier {
  AppState({Api? api, this.testMode = false}) : api = api ?? Api() {
    chat = ChatStore(this.api, testMode: testMode);
    if (testMode) Sfx.muted = true;
  }

  late final ChatStore chat;

  final Api api;
  final bool testMode;
  final navigatorKey = GlobalKey<NavigatorState>();
  SharedPreferences? _prefs;

  // ---------------------------------------------------------------- sozlamalar / настройки
  String lang = 'uz';
  String theme = 'system';
  // Ikkalasi ham standart o‘chiq (tezlik) — Profilda yoqiladi / оба выключены по умолчанию (скорость)
  bool bgMotion = false;

  // ---------------------------------------------------------------- yangilanish / обновление
  int appBuild = kAppBuild;
  bool updateCheckOn = !kIsWeb && defaultTargetPlatform == TargetPlatform.android && kAppBuild > 0;
  Future<String?> Function(Uri url)? fetchText; // testlar uchun / для тестов
  Json? update; // yangi versiya haqida / о новой версии
  /// Saytda telefon kamerasi bilan skanerlangan QR havolasi / ссылка QR, отсканированная камерой телефона на сайте
  ({String eid, String code})? pendingCheckin = _webCheckin();
  bool updateHidden = false; // «Keyinroq» bosildi (shu ochilishgacha) / нажали «Позже» (до перезапуска)
  DateTime? _updateCheckedAt;
  bool get updateAvailable => update != null && !updateHidden && !updateRequired;
  bool get updateRequired => update != null && ((update!['min'] as num?)?.toInt() ?? 0) > appBuild;
  bool glassFx = false;
  bool sounds = true;
  bool sideOpen = true;
  Brightness platformBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;

  bool get isDark => theme == 'dark' || (theme == 'system' && platformBrightness == Brightness.dark);
  AppColors get c => isDark ? kDark : kLight;

  String t(String key) => tr(lang, key);

  // ---------------------------------------------------------------- holat / состояние
  bool ready = false;

  /// Shu safar ochilish animatsiyasi ko‘rsatildimi (null — sozlamalar hali yuklanmagan).
  /// Показана ли заставка в этот запуск (null — настройки ещё не загружены).
  bool? introDone;
  bool connError = false;
  Json? me;
  List<Json> districts = [];
  List<Json> directions = kFallbackDirections;
  List<Json> regions = [];
  String bot = 'KengashAppBot';
  String tab = 'today';
  String tasksBox = 'mine';
  int todayVersion = 0;

  bool get loggedIn => me != null;
  bool get isAdmin => me?['role'] == 'admin';
  bool get needsRegistration => me?['needs_registration'] == true;
  bool get isPending => me?['status'] == 'pending';
  bool get isLocked => me?['locked'] == true;
  bool get isStudent => me?['kind'] == 'student';
  bool get isMaslahatchi => me?['direction'] == 'maslahatchi';
  bool get canGive => me?['can_give'] == true;
  bool get isStaff => me?['kind'] == 'staff';
  bool get canViewArea => me?['can_view_area'] == true;
  bool get canAnnounce => me?['can_announce'] == true;
  bool get canCreateChannels => me?['can_create_channels'] == true;
  String get myName => (me?['name'] ?? '').toString();
  String get myPhoto => photoUrl(me?['photo']);

  String photoUrl(Object? path) {
    final p = (path ?? '').toString();
    if (p.isEmpty) return '';
    return p.startsWith('http') ? p : '${api.base}$p';
  }

  // ---------------------------------------------------------------- nomlar / названия
  String dirName(String? id) {
    if (id == 'maslahatchi') return t('maslahatchi');
    for (final d in directions) {
      if (d['id'] == id) return (d[lang] ?? d['uz']).toString();
    }
    return id ?? '';
  }

  String pick(Json? m, String field) => m == null ? '' : (m['${field}_$lang'] ?? m['${field}_uz'] ?? '').toString();

  String districtName(String? id) {
    for (final d in districts) {
      if (d['id'] == id) return pick(d, 'name');
    }
    return '';
  }

  String regionName(String? id) {
    for (final r in regions) {
      if (r['id'] == id) return pick(r, 'name');
    }
    return lang == 'ru' ? 'Андижанская область' : 'Andijon viloyati';
  }

  /// "59-maktab · Asaka tumani" / "Школа №59 · Асакинский район"
  String placeLine(Json? place) {
    if (place == null) return '';
    final name = pick(place, 'name');
    if (place['level'] == 'school') return '$name · ${pick(place, 'district')}';
    return name;
  }

  String levelName(String? level) => switch (level) {
        'school' => t('lvl_school'),
        'district' => t('lvl_district'),
        'region' => t('lvl_region'),
        _ => '',
      };

  /// "IT va sun’iy intellekt · 59-maktab · Asaka tumani"
  String seatLine(Json? u) {
    if (u == null) return '';
    if (u['role'] == 'admin' && u['level'] == null) return t('role_admin');
    if (u['kind'] == 'staff') {
      // xodim: lavozim · hudud / сотрудник: должность · территория
      final title = (u['title'] ?? '').toString();
      final head = title.isEmpty ? t('staff_kind') : title;
      return u['level'] == null ? head : '$head · ${placeLine(u['place'] as Json?)}';
    }
    if (u['level'] == null) return t('no_seat');
    if (u['kind'] == 'student') {
      final cls = (u['class_name'] ?? '').toString();
      return '${t('student')}${cls.isEmpty ? '' : ' · $cls'} · ${placeLine(u['place'] as Json?)}';
    }
    return '${dirName(u['direction'])} · ${placeLine(u['place'] as Json?)}';
  }

  // ---------------------------------------------------------------- ishga tushirish / запуск
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final p = _prefs;
    if (p != null) {
      lang = p.getString('lang') ?? 'uz';
      theme = p.getString('theme') ?? 'system';
      bgMotion = p.getBool('bg_on') ?? false;
      glassFx = p.getBool('glass_fx') ?? false;
      sounds = p.getBool('sounds') ?? true;
      Sfx.enabled = sounds;
      sideOpen = p.getBool('side_open') ?? true;
      api.token = p.getString('token');
      final cached = p.getString('meta');
      if (cached != null) _applyMeta(jsonDecode(cached) as Json);
    }
    // Ochilish animatsiyasi har safar ilova ochilganda (egasining talabi) / заставка при каждом запуске (просьба владельца)
    introDone = false;
    notifyListeners();
    await loadMeta();
    if (api.token != null) await refreshMe(first: true);
    ready = true;
    notifyListeners();
    checkUpdate();
    runPendingCheckin();
  }

  static ({String eid, String code})? _webCheckin() {
    if (!kIsWeb) return null;
    final q = Uri.base.queryParameters;
    final eid = q['checkin'], code = q['code'];
    if (eid == null || code == null || !RegExp(r'^\d{6}$').hasMatch(code)) return null;
    return (eid: eid, code: code);
  }

  /// Kirgandan keyin QR davomatini yuborish / после входа отправить QR-отметку.
  Future<void> runPendingCheckin() async {
    final p = pendingCheckin;
    if (p == null || !loggedIn || me?['status'] != 'active') return;
    pendingCheckin = null;
    try {
      final r = await api.post('/api/events/${p.eid}/checkin', {'code': p.code});
      toast(r['already'] == true ? t('ci_already') : '${t('ci_done')} ${r['title'] ?? ''}', icon: Icons.check_circle_rounded);
    } on ApiError catch (e) {
      toast(errText(e));
    }
  }

  /// Saytdagi version.json bilan solishtiradi (soatiga ko‘pi bilan 1 marta).
  /// Сверяется с version.json на сайте (не чаще раза в час).
  Future<void> checkUpdate({bool force = false}) async {
    if (!updateCheckOn) return;
    final now = DateTime.now();
    if (!force && _updateCheckedAt != null && now.difference(_updateCheckedAt!) < const Duration(hours: 1)) return;
    _updateCheckedAt = now;
    try {
      final url = Uri.parse('${kSiteUrl}version.json?t=${now.millisecondsSinceEpoch}');
      final String? body;
      if (fetchText != null) {
        body = await fetchText!(url);
      } else {
        final r = await api.client.get(url).timeout(const Duration(seconds: 12));
        body = r.statusCode == 200 ? r.body : null;
      }
      if (body == null) return;
      final j = (jsonDecode(body) as Map).cast<String, dynamic>();
      final b = (j['build'] as num?)?.toInt() ?? 0;
      update = b > appBuild ? j : null;
      notifyListeners();
    } catch (_) {}
  }

  void hideUpdate() {
    updateHidden = true;
    notifyListeners();
  }

  /// Yangi APK’ni yuklab olish (Android o‘zi «Yangilash?» deb so‘raydi).
  /// Скачать новый APK (Android сам спросит «Обновить?»).
  Future<void> installUpdate() async {
    final apk = (update?['apk'] ?? 'Kengash.apk').toString();
    final url = apk.startsWith('https://') ? apk : '$kSiteUrl$apk';
    await openUrl('$url?v=${update?['build'] ?? ''}');
  }

  void _applyMeta(Json m) {
    districts = [for (final d in (m['districts'] as List? ?? [])) (d as Map).cast<String, dynamic>()];
    regions = [for (final d in (m['regions'] as List? ?? [])) (d as Map).cast<String, dynamic>()];
    final dirs = [for (final d in (m['directions'] as List? ?? [])) (d as Map).cast<String, dynamic>()];
    if (dirs.isNotEmpty) directions = dirs;
    bot = (m['bot'] ?? bot).toString();
  }

  Future<void> loadMeta() async {
    try {
      final m = await api.get('/api/meta', timeout: const Duration(seconds: 75));
      _applyMeta(m);
      _prefs?.setString('meta', jsonEncode(m));
      connError = false;
    } on ApiError {
      connError = districts.isEmpty;
    }
  }

  /// Faqat haqiqiy 401 da chiqaramiz (vaqt tugashi emas) / выходим только при настоящем 401 (не при таймауте).
  Future<void> refreshMe({bool first = false}) async {
    try {
      me = await api.get('/api/me', timeout: Duration(seconds: first ? 75 : 15));
      connError = false;
      final cachedMe = jsonEncode(me);
      _prefs?.setString('me', cachedMe);
    } on ApiError catch (e) {
      if (e.status == 401 || e.status == 403) {
        await _clearSession();
      } else if (first) {
        connError = true;
        final cached = _prefs?.getString('me');
        if (cached != null) me = jsonDecode(cached) as Json;
      }
    }
    _syncChat();
    notifyListeners();
  }

  bool _chatOn = false;

  /// Kanallar faqat to‘liq ro‘yxatdan o‘tganda / каналы только после полной регистрации.
  void _syncChat() {
    final ok = loggedIn && !needsRegistration && !isPending && !isLocked;
    if (ok) {
      chat.myId = me!['id'] as String?;
      if (!_chatOn) {
        _chatOn = true;
        chat.start();
        chat.loadChannels();
      }
    } else if (_chatOn) {
      _chatOn = false;
      chat.stop();
    }
  }

  Future<void> setSession(String token, Json user) async {
    api.token = token;
    me = user;
    await _prefs?.setString('token', token);
    await _prefs?.setString('me', jsonEncode(user));
    tab = 'today';
    _syncChat();
    notifyListeners();
    runPendingCheckin();
  }

  void setMe(Json user) {
    me = user;
    _prefs?.setString('me', jsonEncode(user));
    _syncChat();
    notifyListeners();
  }

  Future<void> _clearSession() async {
    api.token = null;
    me = null;
    _syncChat();
    await _prefs?.remove('token');
    await _prefs?.remove('me');
  }

  Future<void> logout({bool everywhere = false}) async {
    try {
      await api.post(everywhere ? '/api/auth/logout-all' : '/api/auth/logout');
    } catch (_) {}
    await _clearSession();
    notifyListeners();
  }

  // ---------------------------------------------------------------- sozlamalar / настройки
  void setLang(String l) {
    lang = l;
    _prefs?.setString('lang', l);
    notifyListeners();
  }

  void toggleLang() => setLang(lang == 'uz' ? 'ru' : 'uz');

  void setTheme(String v) {
    theme = v;
    _prefs?.setString('theme', v);
    notifyListeners();
  }

  void setSounds(bool v) {
    sounds = v;
    Sfx.enabled = v;
    _prefs?.setBool('sounds', v);
    if (v) Sfx.success();
    notifyListeners();
  }

  void setGlassFx(bool v) {
    glassFx = v;
    _prefs?.setBool('glass_fx', v);
    notifyListeners();
  }

  void setBgMotion(bool v) {
    bgMotion = v;
    _prefs?.setBool('bg_on', v);
    notifyListeners();
  }

  void toggleSide() {
    sideOpen = !sideOpen;
    _prefs?.setBool('side_open', sideOpen);
    notifyListeners();
  }

  void setPlatformBrightness(Brightness b) {
    platformBrightness = b;
    notifyListeners();
  }

  void finishIntro() {
    introDone = true;
    notifyListeners();
  }

  void go(String id) {
    tab = id;
    notifyListeners();
  }

  // ---------------------------------------------------------------- yordamchilar / помощники
  /// Kitobda qolgan sahifa / страница, на которой остановились.
  int bookPage(String id) => _prefs?.getInt('book:$id') ?? 1;
  void setBookPage(String id, int page) => _prefs?.setInt('book:$id', page);
  int bookTotal(String id) => _prefs?.getInt('bookpages:$id') ?? 0;
  void setBookTotal(String id, int n) => _prefs?.setInt('bookpages:$id', n);

  String errText(Object e) {
    final code = e is ApiError ? e.code : 'conn';
    final k = 'err_$code';
    final v = t(k);
    return v == k ? t('err_generic') : v;
  }

  void toast(String text, {IconData icon = Icons.info_rounded}) {
    final o = navigatorKey.currentState?.overlay;
    if (o != null) AppToast.show(o, text, icon: icon);
  }

  Future<void> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    toast(t('copied'), icon: Icons.check_circle_rounded);
  }

  /// Faqat xavfsiz havolalar (http, https, tg) ochiladi / открываются только безопасные ссылки.
  Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !const {'http', 'https', 'tg'}.contains(uri.scheme.toLowerCase())) {
      toast(t('err_open'));
      return;
    }
    if (testMode) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      toast(t('err_open'));
    }
  }

  Future<void> openTelegram(String username) => openUrl('https://t.me/${username.replaceFirst('@', '')}');
}

/// Holatni daraxtga beradi / передаёт состояние в дерево виджетов.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
}
