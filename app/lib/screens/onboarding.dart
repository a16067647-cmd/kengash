import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../brand.dart';
import '../motion_lab.dart' show MotionLevel;
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'directory.dart' show UserCard;

/// Botda ro‘yxatdan o‘tish: ism yoziladi, qolgani — tugmalar. Tugagach ilova o‘zi ochiladi.
/// Регистрация в боте: пишется только имя, остальное — кнопки. После этого приложение откроется само.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with WidgetsBindingObserver {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Botda tugatgach holat yangilanadi / после завершения в боте статус обновится
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => AppScope.read(context).refreshMe());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppScope.read(context).refreshMe();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final rejected = s.me?['status'] == 'rejected';
    return _Centered(children: [
      const Center(child: KengashMark(size: 72, directions: true)),
      const SizedBox(height: S.x5),
      Text(s.t(rejected ? 'rejected_title' : 'reg_title'), textAlign: TextAlign.center, style: AppType.title1.copyWith(color: c.text)),
      const SizedBox(height: S.x2),
      Text(s.t(rejected ? 'rejected_text' : 'reg_text'), textAlign: TextAlign.center, style: AppType.callout.copyWith(color: c.text2)),
      const SizedBox(height: S.x6),
      AppButton(s.t('reg_open_bot'),
          key: const ValueKey('open-bot'),
          icon: Icons.send_rounded,
          expand: true,
          height: 56,
          onPressed: () => s.openUrl('https://t.me/${s.bot}?start=reg')),
      const SizedBox(height: S.x2),
      AppButton(s.t('logout'), kind: BtnKind.ghost, expand: true, height: 44, onPressed: s.logout),
    ]);
  }
}

/// Tasdiq kutilmoqda: kim tasdiqlaydi (Telegram havolasi bilan) / ожидание подтверждения: кто подтверждает.
class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => AppScope.read(context).refreshMe());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final approvers = [for (final a in (s.me?['approvers'] as List? ?? [])) (a as Map).cast<String, dynamic>()];
    return _Centered(children: [
      Center(child: IconTile(Icons.hourglass_top_rounded, size: 72, circle: true, bg: c.accentSoft, color: c.accentText)),
      const SizedBox(height: S.x5),
      Text(s.t('pending_title'), textAlign: TextAlign.center, style: AppType.title1.copyWith(color: c.text)),
      const SizedBox(height: S.x2),
      Text(s.seatLine(s.me), textAlign: TextAlign.center, style: AppType.callout.copyWith(color: c.accentText)),
      const SizedBox(height: S.x2),
      Text(s.t('pending_text'), textAlign: TextAlign.center, style: AppType.subhead.copyWith(color: c.text2)),
      const SizedBox(height: S.x5),
      for (final a in approvers) ...[UserCard(user: a), const SizedBox(height: S.x3)],
      AppButton(s.t('refresh'), kind: BtnKind.secondary, icon: Icons.refresh_rounded, expand: true, onPressed: s.refreshMe),
      const SizedBox(height: S.x2),
      AppButton(s.t('logout'), kind: BtnKind.ghost, expand: true, height: 44, onPressed: s.logout),
    ]);
  }
}

/// To‘lov kerak (to‘lov yoqilganda) / нужна оплата (когда оплата включена).
class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return _Centered(children: [
      Center(child: IconTile(Icons.lock_rounded, size: 72, circle: true, bg: c.accentSoft, color: c.accentText)),
      const SizedBox(height: S.x5),
      Text(s.t('pay_title'), textAlign: TextAlign.center, style: AppType.title1.copyWith(color: c.text)),
      const SizedBox(height: S.x2),
      Text(s.t('pay_text'), textAlign: TextAlign.center, style: AppType.callout.copyWith(color: c.text2)),
      const SizedBox(height: S.x6),
      AppButton(s.t('refresh'), kind: BtnKind.secondary, icon: Icons.refresh_rounded, expand: true, onPressed: s.refreshMe),
      const SizedBox(height: S.x2),
      AppButton(s.t('logout'), kind: BtnKind.ghost, expand: true, height: 44, onPressed: s.logout),
    ]);
  }
}

class _Centered extends StatelessWidget {
  final List<Widget> children;
  const _Centered({required this.children});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: AppBackground(
        motion: MotionLevel.low,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(S.page, S.x8, S.page, S.x6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tasdiqlash kutayotgan arizalar / заявки, ожидающие подтверждения.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List<Json>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/approvals');
      if (mounted) setState(() => _list = [for (final x in r['users'] as List) (x as Map).cast<String, dynamic>()]);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  Future<void> _decide(Json u, bool approve) async {
    final s = AppScope.read(context);
    try {
      await s.api.post('/api/approvals/${u['id']}', {'approve': approve});
      s.toast(s.t(approve ? 'approved_toast' : 'rejected_toast'), icon: approve ? Icons.check_circle_rounded : Icons.cancel_rounded);
      s.todayVersion++;
      _load();
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return PageShell(
      child: TabPage(
        title: s.t('approvals'),
        subtitle: s.t('approvals_sub'),
        onRefresh: _load,
        children: [
          if (_list == null)
            const SkeletonRows(count: 3)
          else if (_list!.isEmpty)
            EmptyState(icon: Icons.verified_user_rounded, title: s.t('approvals_none'))
          else
            for (final u in _list!)
              AppCard(
                key: ValueKey('apply-${u['id']}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    AppAvatar(url: s.photoUrl(u['photo']), name: (u['name'] ?? '').toString(), size: 44),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text((u['name'] ?? '').toString(), style: AppType.headline.copyWith(color: c.text)),
                        Text(s.seatLine(u), style: AppType.footnote.copyWith(color: c.text2)),
                        if ((u['phone'] ?? '').toString().isNotEmpty || (u['tg_username'] ?? '').toString().isNotEmpty)
                          Text([if ((u['phone'] ?? '') != '') u['phone'], if ((u['tg_username'] ?? '') != '') '@${u['tg_username']}'].join(' · '),
                              style: AppType.caption.copyWith(color: c.text3)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: S.x3),
                  Row(children: [
                    Expanded(
                        child: AppButton(s.t('approve'),
                            key: ValueKey('approve-${u['id']}'), icon: Icons.check_rounded, height: 46, onPressed: () => _decide(u, true))),
                    const SizedBox(width: S.x2),
                    Expanded(
                        child: AppButton(s.t('reject'),
                            key: ValueKey('reject-${u['id']}'), kind: BtnKind.secondary, height: 46, onPressed: () => _decide(u, false))),
                  ]),
                ]),
              ),
        ],
      ),
    );
  }
}

/// Profil surati: bosilsa galereyadan tanlanadi / фото профиля: при нажатии выбирается из галереи.
class PhotoEditor extends StatefulWidget {
  final double size;
  const PhotoEditor({super.key, this.size = 110});

  @override
  State<PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends State<PhotoEditor> {
  bool _busy = false;

  Future<void> _pick() async {
    final s = AppScope.read(context);
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1400, maxHeight: 1400, imageQuality: 88);
      if (f == null) return;
      setState(() => _busy = true);
      final bytes = await f.readAsBytes();
      s.setMe(await s.api.post('/api/me/photo', {'data': base64Encode(bytes)}, const Duration(seconds: 40)));
      s.toast(s.t('photo_saved'), icon: Icons.check_circle_rounded);
    } on ApiError catch (e) {
      s.toast(s.errText(e), icon: Icons.error_rounded);
    } catch (_) {
      s.toast(s.t('err_photo'), icon: Icons.error_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return Pressable(
      key: const ValueKey('photo'),
      onTap: _busy ? null : _pick,
      semanticLabel: s.t('change_photo'),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(children: [
          AppAvatar(url: s.myPhoto, name: s.myName, size: widget.size, ring: true),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: widget.size * 0.32,
              height: widget.size * 0.32,
              decoration: BoxDecoration(
                gradient: c.accentGradient,
                shape: BoxShape.circle,
                border: Border.all(color: c.bg, width: 3),
              ),
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2, color: kWhite),
                    )
                  : Icon(Icons.photo_camera_rounded, size: widget.size * 0.15, color: kWhite),
            ),
          ),
        ]),
      ),
    );
  }
}
