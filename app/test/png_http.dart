// Testlarda tarmoq rasmlari o‘rniga haqiqiy PNG beradi / в тестах отдаёт настоящий PNG вместо сетевых картинок.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> makePng(WidgetTester tester, {int w = 1600, int h = 1200, Color a = Colors.orange, Color b = Colors.blue}) async {
  late Uint8List png;
  await tester.runAsync(() async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = a);
    canvas.drawCircle(Offset(w / 2, h / 2), w / 4, Paint()..color = b);
    final img = await rec.endRecording().toImage(w, h);
    png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  });
  return png;
}

class PngHttp extends HttpOverrides {
  final Uint8List png;
  PngHttp(this.png);
  @override
  HttpClient createHttpClient(SecurityContext? c) => _C(png);
}

class _C implements HttpClient {
  final Uint8List png;
  _C(this.png);
  @override
  bool autoUncompress = true;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Rq(png);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Rq implements HttpClientRequest {
  final Uint8List png;
  _Rq(this.png);
  @override
  Future<HttpClientResponse> close() async => _Rs(png);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Rs extends Stream<List<int>> implements HttpClientResponse {
  final Uint8List png;
  _Rs(this.png);
  @override
  int get statusCode => 200;
  @override
  int get contentLength => png.length;
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.fromIterable([png]).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

