// QR davomat: tashkilotchi QR ko‘rsatadi (har daqiqada yangilanadi), mehmon skanerlaydi yoki 6 xonali kodni yozadi.
// QR-посещаемость: организатор показывает QR (обновляется каждую минуту), гость сканирует или вводит 6-значный код.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api.dart';
import '../sound.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// QR matnidan (havola) tadbir va kod / событие и код из текста QR (ссылки).
({String eid, String code})? parseCheckin(String raw) {
  final uri = Uri.tryParse(raw.trim());
  final eid = uri?.queryParameters['checkin'];
  final code = uri?.queryParameters['code'];
  if (eid == null || code == null || eid.isEmpty || !RegExp(r'^\d{6}$').hasMatch(code)) return null;
  return (eid: eid, code: code);
}

/// Serverga yuborish va natijani aytish / отправить на сервер и сообщить результат.
Future<bool> sendCheckin(AppState s, String eid, String code) async {
  try {
    final r = await s.api.post('/api/events/$eid/checkin', {'code': code});
    Sfx.success();
    s.toast(r['already'] == true ? s.t('ci_already') : '${s.t('ci_done')} ${r['title'] ?? ''}',
        icon: Icons.check_circle_rounded);
    return true;
  } on ApiError catch (e) {
    s.toast(s.errText(e));
    return false;
  }
}

/// Tashkilotchi: katta QR, kod va «keldi» hisoblagichi / организатор: большой QR, код и счётчик.
class QrScreen extends StatefulWidget {
  final String eventId;
  final String title;
  const QrScreen({super.key, required this.eventId, required this.title});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  Json? _d;
  Timer? _timer;
  int _left = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = (_left - 1).clamp(0, 999));
      if (_left == 0 || DateTime.now().second % 10 == 0) _load(); // yangi kod va hisob / новый код и счёт
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final d = await s.api.get('/api/events/${widget.eventId}/qr');
      if (mounted) {
        setState(() {
          _d = d;
          _left = (d['expires_in'] as num).toInt();
        });
      }
    } on ApiError catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final d = _d;
    final code = (d?['code'] ?? '').toString();
    return PageShell(
      child: TabPage(
        title: s.t('ci_qr_title'),
        subtitle: widget.title,
        children: [
          if (d == null)
            const SkeletonRows(count: 3)
          else ...[
            if (d['open'] == false)
              AppCard(
                kind: CardKind.tinted,
                tint: c.warningSoft,
                child: Text(s.t('ci_not_open'), style: AppType.subhead.copyWith(color: c.text)),
              ),
            Center(
              child: Container(
                key: const ValueKey('qr-code'),
                padding: const EdgeInsets.all(S.x5),
                decoration: BoxDecoration(color: Colors.white, borderRadius: R.all(R.xl), boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 30, offset: const Offset(0, 10)),
                ]),
                child: QrImageView(
                  data: d['qr'] as String,
                  size: 260,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF3A1B78)),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1B1530)),
                ),
              ),
            ),
            Center(
              child: Text(
                '${code.substring(0, 3)} ${code.substring(3)}',
                key: const ValueKey('qr-digits'),
                style: AppType.largeTitle.copyWith(color: c.text, fontSize: 44, letterSpacing: 6),
              ),
            ),
            Center(
              child: Text('${s.t('ci_refresh')} $_left s', style: AppType.footnote.copyWith(color: c.text3)),
            ),
            AppCard(
              child: Row(children: [
                Icon(Icons.how_to_reg_rounded, color: c.accentText, size: 30),
                const SizedBox(width: S.x3),
                Expanded(child: Text(s.t('ci_came'), style: AppType.headline.copyWith(color: c.text))),
                Text('${d['came']} / ${d['total']}',
                    key: const ValueKey('qr-came'), style: AppType.number.copyWith(color: c.accentText)),
              ]),
            ),
            Text(s.t('ci_how_org'), textAlign: TextAlign.center, style: AppType.footnote.copyWith(color: c.text2)),
          ],
        ],
      ),
    );
  }
}

/// Mehmon: kamera bilan skanerlash yoki kodni yozish / гость: сканировать камерой или ввести код.
class CheckinScreen extends StatefulWidget {
  final String eventId;
  const CheckinScreen({super.key, required this.eventId});

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _done = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _send(String code) async {
    if (_busy || _done) return;
    final s = AppScope.read(context);
    setState(() => _busy = true);
    final ok = await sendCheckin(s, widget.eventId, code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = ok;
    });
    if (ok) Navigator.of(context).pop(true);
  }

  void _onScan(BarcodeCapture cap) {
    for (final b in cap.barcodes) {
      final p = parseCheckin(b.rawValue ?? '');
      if (p != null && p.eid == widget.eventId) {
        _send(p.code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return PageShell(
      child: TabPage(
        title: s.t('ci_title'),
        subtitle: s.t('ci_sub'),
        children: [
          if (!s.testMode)
            ClipRRect(
              borderRadius: R.all(R.xl),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(fit: StackFit.expand, children: [
                  MobileScanner(
                    onDetect: _onScan,
                    errorBuilder: (ctx, err) => Container(
                      color: c.surfaceAlt,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(S.x6),
                      child: Text(s.t('ci_no_camera'), textAlign: TextAlign.center, style: AppType.subhead.copyWith(color: c.text2)),
                    ),
                  ),
                  // nishon ramkasi / рамка прицела
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 210,
                        height: 210,
                        decoration: BoxDecoration(
                          borderRadius: R.all(R.lg),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          Text(s.t('ci_or_code'), style: AppType.footnote.copyWith(color: c.text2)),
          AppTextField(
            key: const ValueKey('ci-code'),
            controller: _code,
            hint: '123 456',
            icon: Icons.pin_rounded,
            keyboardType: TextInputType.number,
            maxLength: 7,
            onSubmitted: (v) => _send(v),
          ),
          AppButton(s.t('ci_send'),
              key: const ValueKey('ci-send'),
              expand: true,
              loading: _busy,
              icon: Icons.how_to_reg_rounded,
              onPressed: () => _send(_code.text)),
        ],
      ),
    );
  }
}
