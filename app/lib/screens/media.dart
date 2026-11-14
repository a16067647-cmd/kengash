import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../chat.dart' show fileSize;
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

String clock(num seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

// ============================================================ biriktirma / вложение
class AttachmentView extends StatelessWidget {
  final Json a;
  final bool mine;
  final bool pending;
  const AttachmentView({super.key, required this.a, this.mine = false, this.pending = false});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final kind = a['kind'] as String? ?? 'file';
    final url = (a['url'] ?? '').toString();
    final fg = mine ? kWhite : c.text;
    final sub = mine ? Colors.white.withAlpha(0xCC) : c.text2;
    if (a['pending'] == true || pending && url.isEmpty) {
      return Container(
        width: 220,
        height: kind == 'photo' || kind == 'video' ? 160 : 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: mine ? Colors.white.withAlpha(0x22) : c.surfaceAlt, borderRadius: R.all(R.md)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
          const SizedBox(width: S.x2),
          Text(s.t('uploading'), style: AppType.footnote.copyWith(color: fg)),
        ]),
      );
    }
    switch (kind) {
      case 'photo':
        final w = (a['w'] as num?)?.toDouble() ?? 4;
        final h = (a['h'] as num?)?.toDouble() ?? 3;
        return GestureDetector(
          onTap: url.isEmpty ? null : () => Navigator.of(context).push(_fade(PhotoViewer(url: url))),
          child: ClipRRect(
            borderRadius: R.all(R.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320, maxHeight: 380),
              child: AspectRatio(
                aspectRatio: (w / h).clamp(0.6, 2.0),
                child: url.isEmpty
                    ? Container(color: c.surfaceAlt)
                    : Image.network(url,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) =>
                            Container(color: c.surfaceAlt, child: Icon(Icons.broken_image_rounded, color: c.text3, size: 40))),
              ),
            ),
          ),
        );
      case 'video':
        return GestureDetector(
          onTap: url.isEmpty ? null : () => Navigator.of(context).push(_fade(VideoViewer(url: url))),
          child: Container(
            width: 260,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: R.all(R.md),
              gradient: const LinearGradient(colors: [Color(0xFF2A115E), Color(0xFF0A0714)]),
            ),
            child: Stack(alignment: Alignment.center, children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: Colors.white.withAlpha(0x33), shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: kWhite, size: 38),
              ),
              Positioned(
                left: S.x3,
                bottom: S.x2,
                child: Text('🎬 ${fileSize((a['size'] as num?) ?? 0)}', style: AppType.caption.copyWith(color: kWhite)),
              ),
            ]),
          ),
        );
      case 'voice':
        return VoicePlayer(url: url, seconds: (a['duration'] as num?)?.toDouble() ?? 0, mine: mine);
      default:
        return Pressable(
          onTap: url.isEmpty ? null : () => s.openUrl(url),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.all(S.x2),
            decoration: BoxDecoration(color: mine ? Colors.white.withAlpha(0x22) : c.surfaceAlt, borderRadius: R.all(R.md)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: mine ? Colors.white.withAlpha(0x33) : c.accentSoft, borderRadius: R.all(R.sm)),
                child: Icon(Icons.description_rounded, color: mine ? kWhite : c.accentText),
              ),
              const SizedBox(width: S.x3),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((a['name'] ?? s.t('att_file')).toString(),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.subhead.copyWith(color: fg)),
                  Text('${fileSize((a['size'] as num?) ?? 0)} · ${s.t('open')}', style: AppType.caption.copyWith(color: sub)),
                ]),
              ),
            ]),
          ),
        );
    }
  }
}

Route<T> _fade<T>(Widget child) => PageRouteBuilder<T>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => child,
      transitionsBuilder: (_, a, __, ch) => FadeTransition(opacity: a, child: ch),
    );

// ============================================================ surat / фото
class PhotoViewer extends StatelessWidget {
  final String url;
  const PhotoViewer({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: InteractiveViewer(
            maxScale: 5,
            child: Center(child: Image.network(url, fit: BoxFit.contain)),
          ),
        ),
        SafeArea(
          child: Row(children: [
            IconButton(
                tooltip: s.t('back'),
                icon: const Icon(Icons.close_rounded, color: kWhite, size: 28),
                onPressed: () => Navigator.of(context).pop()),
            const Spacer(),
            IconButton(
                tooltip: s.t('download'),
                icon: const Icon(Icons.download_rounded, color: kWhite, size: 26),
                onPressed: () => s.openUrl(url)),
          ]),
        ),
      ]),
    );
  }
}

// ============================================================ video
class VideoViewer extends StatefulWidget {
  final String url;
  const VideoViewer({super.key, required this.url});

  @override
  State<VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<VideoViewer> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) {
        setState(() {});
        _c.play();
      }
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
    _c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final v = _c.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: _error
              ? Text(s.t('err_video'), style: AppType.body.copyWith(color: kWhite))
              : v.isInitialized
                  ? AspectRatio(
                      aspectRatio: v.aspectRatio,
                      child: GestureDetector(onTap: () => v.isPlaying ? _c.pause() : _c.play(), child: VideoPlayer(_c)))
                  : const CircularProgressIndicator(color: kWhite),
        ),
        SafeArea(
          child: Row(children: [
            IconButton(
                tooltip: s.t('back'),
                icon: const Icon(Icons.close_rounded, color: kWhite, size: 28),
                onPressed: () => Navigator.of(context).pop()),
          ]),
        ),
        if (v.isInitialized)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.x2, 0, S.x4, S.x3),
                child: Row(children: [
                  IconButton(
                    icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: kWhite, size: 32),
                    onPressed: () => v.isPlaying ? _c.pause() : _c.play(),
                  ),
                  Expanded(
                    child: VideoProgressIndicator(_c,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                            playedColor: Color(0xFF8B66FF),
                            bufferedColor: Color(0x55FFFFFF),
                            backgroundColor: Color(0x22FFFFFF))),
                  ),
                  const SizedBox(width: S.x3),
                  Text('${clock(v.position.inSeconds)} / ${clock(v.duration.inSeconds)}',
                      style: AppType.caption.copyWith(color: kWhite)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

// ============================================================ ovozli xabar / голосовое
class VoicePlayer extends StatefulWidget {
  final String url;
  final double seconds;
  final bool mine;
  const VoicePlayer({super.key, required this.url, required this.seconds, this.mine = false});

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  AudioPlayer? _p;
  Duration _pos = Duration.zero;
  bool _playing = false;
  final List<StreamSubscription> _subs = [];

  @override
  void dispose() {
    for (final x in _subs) {
      x.cancel();
    }
    _p?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (widget.url.isEmpty) return;
    var p = _p;
    if (p == null) {
      p = _p = AudioPlayer();
      _subs.add(p.onPositionChanged.listen((d) => mounted ? setState(() => _pos = d) : null));
      _subs.add(p.onPlayerStateChanged.listen((st) => mounted ? setState(() => _playing = st == PlayerState.playing) : null));
      _subs.add(p.onPlayerComplete.listen((_) => mounted ? setState(() => _pos = Duration.zero) : null));
    }
    if (_playing) {
      await p.pause();
    } else {
      await p.play(UrlSource(widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final fg = widget.mine ? kWhite : c.accentText;
    final total = widget.seconds <= 0 ? 1.0 : widget.seconds;
    final prog = (_pos.inMilliseconds / 1000 / total).clamp(0.0, 1.0);
    return SizedBox(
      width: 230,
      child: Row(children: [
        Pressable(
          onTap: _toggle,
          semanticLabel: s.t('play'),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: widget.mine ? Colors.white.withAlpha(0x33) : c.accentSoft, shape: BoxShape.circle),
            child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: fg, size: 26),
          ),
        ),
        const SizedBox(width: S.x2),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(size: const Size(double.infinity, 22), painter: _WavePainter(prog, fg, fg.withAlpha(0x55))),
            Text(clock(_playing || _pos > Duration.zero ? _pos.inSeconds : widget.seconds),
                style: AppType.caption.copyWith(color: widget.mine ? Colors.white.withAlpha(0xCC) : c.text2)),
          ]),
        ),
      ]),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final Color on, off;
  _WavePainter(this.progress, this.on, this.off);

  @override
  void paint(Canvas canvas, Size size) {
    const n = 28;
    final w = size.width / n;
    for (var i = 0; i < n; i++) {
      final h = size.height * (0.25 + 0.75 * ((i * 37 % 11) / 10));
      final p = Paint()
        ..color = i / n <= progress ? on : off
        ..strokeWidth = w * 0.55
        ..strokeCap = StrokeCap.round;
      final x = i * w + w / 2;
      canvas.drawLine(Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2), p);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress || old.on != on;
}

/// Yozib olingan ovoz / записанный голос.
class VoiceClip {
  final Uint8List bytes;
  final String name;
  final String mime;
  final double seconds;
  const VoiceClip(this.bytes, this.name, this.mime, this.seconds);
}

/// Ovoz yozish paneli: mikrofon → yozilmoqda (taymer, bekor, yuborish). Eng ko‘pi 5 daqiqa.
/// Панель записи: микрофон → запись (таймер, отмена, отправка). Максимум 5 минут.
class VoiceRecorderBar extends StatefulWidget {
  final Widget Function(VoidCallback startRecording) idle;
  final Future<void> Function(VoiceClip) onDone;
  const VoiceRecorderBar({super.key, required this.idle, required this.onDone});

  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> {
  static const maxSeconds = 300;
  AudioRecorder? _rec;
  bool _recording = false;
  int _secs = 0;
  Timer? _timer;
  String _mime = 'audio/mp4';
  String _ext = 'm4a';

  @override
  void dispose() {
    _timer?.cancel();
    _rec?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final s = AppScope.read(context);
    final rec = _rec ??= AudioRecorder();
    try {
      if (!await rec.hasPermission()) {
        s.toast(s.t('err_mic'));
        return;
      }
      var encoder = AudioEncoder.aacLc;
      if (kIsWeb && !await rec.isEncoderSupported(AudioEncoder.aacLc)) {
        encoder = AudioEncoder.opus;
        _mime = 'audio/webm';
        _ext = 'webm';
      }
      var path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.$_ext';
      }
      await rec.start(RecordConfig(encoder: encoder, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: path);
      setState(() {
        _recording = true;
        _secs = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _secs++);
        if (_secs >= maxSeconds) _stop(send: true);
      });
    } catch (_) {
      s.toast(s.t('err_mic'));
    }
  }

  Future<void> _stop({required bool send}) async {
    _timer?.cancel();
    final secs = _secs;
    setState(() => _recording = false);
    final path = await _rec?.stop();
    if (!send || path == null || secs < 1) return;
    try {
      final bytes = await XFile(path).readAsBytes();
      await widget.onDone(VoiceClip(bytes, 'voice.$_ext', _mime, secs.toDouble()));
    } catch (_) {
      if (mounted) AppScope.read(context).toast(AppScope.read(context).t('err_mic'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_recording) return widget.idle(_start);
    final s = AppScope.of(context);
    final c = s.c;
    return Row(children: [
      IconButton(
          key: const ValueKey('rec-cancel'),
          tooltip: s.t('cancel'),
          icon: Icon(Icons.delete_rounded, color: c.danger, size: 28),
          onPressed: () => _stop(send: false)),
      const SizedBox(width: S.x2),
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle)),
      const SizedBox(width: S.x2),
      Text('${clock(_secs)} / ${clock(maxSeconds)}', style: AppType.monoStrong.copyWith(color: c.text)),
      const Spacer(),
      Text(s.t('recording'), style: AppType.footnote.copyWith(color: c.text2)),
      const SizedBox(width: S.x3),
      Pressable(
        key: const ValueKey('rec-send'),
        onTap: () => _stop(send: true),
        semanticLabel: s.t('send'),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(gradient: c.accentGradient, shape: BoxShape.circle),
          child: const Icon(Icons.arrow_upward_rounded, color: kWhite, size: 24),
        ),
      ),
    ]);
  }
}
