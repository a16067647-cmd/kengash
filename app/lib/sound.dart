// Ilova tovushlari (original, sintez qilingan): shisha qo‘ng‘iroqchalar va yumshoq raqamli ovozlar.
// Звуки приложения (оригинальные, синтезированные): стеклянные колокольчики и мягкие цифровые звуки.
//
// Hammasi past ovozda; Profil → «Ovozlar» o‘chirsa — jim. Brauzer foydalanuvchi bosmaguncha ovozni bloklaydi.
// Всё тихо; Профиль → «Звуки» выключает. Браузер блокирует звук до первого нажатия пользователя.
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class Sfx {
  Sfx._();

  /// Profil sozlamasi / настройка профиля.
  static bool enabled = true;

  /// Testlarda platforma kanali yo‘q / в тестах нет платформенного канала.
  static bool muted = false;

  static const double _volume = 0.32;
  static final Map<String, AudioPlayer> _fixed = {};
  static DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  static bool get _on => enabled && !muted;

  /// Tez-tez chalinadiganlar uchun bitta qayta ishlatiladigan pleyer / один переиспользуемый плеер для частых звуков.
  static Future<void> _playFixed(String name, double volume) async {
    try {
      final p = _fixed.putIfAbsent(name, () => AudioPlayer(playerId: 'sfx-$name')..setReleaseMode(ReleaseMode.stop));
      await p.stop();
      await p.play(AssetSource('sounds/$name.wav'), volume: volume, mode: PlayerMode.lowLatency);
    } catch (e) {
      if (kDebugMode) debugPrint('sfx $name: $e');
    }
  }

  /// Ustma-ust chalinadiganlar (qo‘ng‘iroqchalar) / накладывающиеся звуки (колокольчики).
  static Future<void> _playOnce(String name, double volume) async {
    try {
      final p = AudioPlayer();
      p.onPlayerComplete.first.then((_) => p.dispose());
      await p.play(AssetSource('sounds/$name.wav'), volume: volume);
    } catch (e) {
      if (kDebugMode) debugPrint('sfx $name: $e');
    }
  }

  /// Har bir bosish — juda past «tik» (60 ms ichida takrorlanmaydi) / каждый тап — очень тихий «тик».
  static void tap() {
    if (!_on) return;
    final now = DateTime.now();
    if (now.difference(_lastTap).inMilliseconds < 60) return;
    _lastTap = now;
    _playFixed('tap', _volume * 0.55);
  }

  /// Xabar yuborildi (iPhone kabi «vush») / сообщение отправлено («вжух» как на iPhone).
  static void send() {
    if (_on) _playFixed('send', _volume);
  }

  /// Ochiq chatga yangi xabar / новое сообщение в открытом чате.
  static void receive() {
    if (_on) _playFixed('receive', _volume * 0.85);
  }

  /// Muhim amal bajarildi: tasdiqlash, hisobot, «O‘qidim», +1 / важное действие выполнено.
  static void success() {
    if (_on) _playOnce('success', _volume);
  }

  /// Ochilish: har nuqta qo‘nishida bitta nota (0..7) / интро: нота на приземление каждой точки.
  static void chime(int i) {
    if (_on) _playOnce('chime${i.clamp(0, 7)}', _volume * 0.9);
  }

  /// Ochilish: belgi paydo bo‘lganda akkord / интро: аккорд при появлении знака.
  static void introChord() {
    if (_on) _playOnce('intro_chord', _volume);
  }
}
