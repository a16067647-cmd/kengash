// Ilova tovushlari (original, sintez qilingan): marimba, selesta, yumshoq «tok», havoli «vush».
// Звуки приложения (оригинальные, синтезированные): маримба, челеста, мягкий «ток», воздушный «вжух».
// Generator: tools/make_sounds.py
//
// Kechikmasligi uchun: ilova ochilishi bilan hamma tovush oldindan yuklanadi (preload); ochilish musiqasi —
// bitta fayl, animatsiya boshlangan vaqtdan hisoblab sinxron chalinadi.
// Без задержек: всё загружается заранее при запуске; музыка интро — один файл, синхронно с анимацией.
//
// Hammasi past ovozda; Profil → «Ovozlar» o‘chirsa — jim. Brauzer foydalanuvchi bosmaguncha ovozni bloklaydi.
// Всё тихо; Профиль → «Звуки» выключает. Браузер блокирует звук до первого нажатия пользователя.
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class Sfx {
  Sfx._();

  /// Profil sozlamasi / настройка профиля.
  static bool enabled = true;

  /// Testlarda platforma kanali yo‘q / в тестах нет платформенного канала.
  static bool muted = false;

  static const double _volume = 0.35;
  static const _short = ['tap', 'send', 'receive', 'success'];
  static final Map<String, AudioPlayer> _players = {};
  static final Map<String, Future<void>> _ready = {};
  static AudioPlayer? _intro;
  static Future<void>? _introReady;
  static DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  static bool get _on => enabled && !muted;

  /// Ilova ochilishi bilan (runApp’dan oldin) — fayllarni oldindan tayyorlash.
  /// При запуске (до runApp) — заранее подготовить файлы.
  static void preload() {
    if (muted) return;
    _introReady = () async {
      final p = AudioPlayer(playerId: 'sfx-intro');
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setSource(AssetSource('sounds/intro.m4a'));
      await p.setVolume(_volume * 1.1);
      _intro = p;
    }()
        .catchError((Object e) {
      if (kDebugMode) debugPrint('sfx intro: $e');
    });
    for (final name in _short) {
      _ready[name] = () async {
        final p = AudioPlayer(playerId: 'sfx-$name');
        await p.setReleaseMode(ReleaseMode.stop);
        if (!kIsWeb) await p.setPlayerMode(PlayerMode.lowLatency); // Android: SoundPool — darhol / мгновенно
        await p.setSource(AssetSource('sounds/$name.wav'));
        _players[name] = p;
      }()
          .catchError((Object e) {
        if (kDebugMode) debugPrint('sfx $name: $e');
      });
    }
  }

  static Future<void> _play(String name, double volume) async {
    try {
      await (_ready[name] ?? Future<void>.value());
      final p = _players[name];
      if (p == null) return;
      await p.stop();
      await p.setVolume(volume);
      await p.resume();
    } catch (e) {
      if (kDebugMode) debugPrint('sfx $name: $e');
    }
  }

  /// Har bir bosish — juda past, yumshoq «tok» (60 ms ichida takrorlanmaydi) / мягкий тихий «ток».
  static void tap() {
    if (!_on) return;
    final now = DateTime.now();
    if (now.difference(_lastTap).inMilliseconds < 60) return;
    _lastTap = now;
    _play('tap', _volume * 0.5);
  }

  /// Xabar yuborildi — havoli «vush» / сообщение отправлено — воздушный «вжух».
  static void send() {
    if (_on) _play('send', _volume * 0.9);
  }

  /// Ochiq chatga yangi xabar — ikki nozik nota / новое сообщение — две тонкие ноты.
  static void receive() {
    if (_on) _play('receive', _volume * 0.8);
  }

  /// Muhim amal bajarildi — marimba arpedjiosi / важное действие — арпеджио маримбы.
  static void success() {
    if (_on) _play('success', _volume);
  }

  /// Ochilish musiqasini boshlash: fayl tayyor bo‘lishini kutadi va haqiqatan chala boshlagach `true` qaytaradi —
  /// shundan keyin animatsiya boshlanadi (animatsiya musiqaga ergashadi, aksincha emas). Ovoz bo‘lmasa — `false`.
  /// Запуск музыки интро: ждём готовности и реального начала воспроизведения → `true`; анимация стартует после
  /// (анимация следует за музыкой, а не наоборот). Без звука — `false`.
  static Future<bool> introStart() async {
    if (!_on) return false;
    try {
      await (_introReady ?? Future<void>.value()).timeout(const Duration(milliseconds: 900));
      final p = _intro;
      if (p == null || !_on) return false;
      final playing = p.onPlayerStateChanged
          .firstWhere((st) => st == PlayerState.playing)
          .timeout(const Duration(milliseconds: 700));
      await p.resume();
      await playing;
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('sfx intro: $e');
      return false;
    }
  }

  /// Ochilish musiqasi chalinishi mumkinmi (yoqilgan va tayyorlanmoqda) / может ли играть музыка интро.
  static bool get introPlayable => _on && _introReady != null;

  /// Musiqaning haqiqiy joyi (animatsiyani tuzatish uchun) / реальная позиция музыки (для подстройки анимации).
  static Stream<Duration>? get introPosition => _intro?.onPositionChanged;
}
