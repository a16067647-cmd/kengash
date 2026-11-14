import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../brand.dart';
import '../motion_lab.dart' show MotionLevel;
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'directory.dart' show UserCard;
import 'legal.dart';
import 'pickers.dart';

/// Kalit kiritish (o‘rinni olish) / ввод ключа (получить место).
class SeatScreen extends StatefulWidget {
  const SeatScreen({super.key});

  @override
  State<SeatScreen> createState() => _SeatScreenState();
}

class _SeatScreenState extends State<SeatScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;
  int _shake = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final s = AppScope.read(context);
    final code = _ctrl.text.trim();
    if (code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length < 8) {
      setState(() {
        _error = s.t('err_bad_key');
        _shake++;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final me = await s.api.post('/api/me/redeem-key', {'code': code});
      s.setMe(me);
      s.toast(s.t('key_ok'), icon: Icons.verified_rounded);
    } on ApiError catch (e) {
      setState(() {
        _error = s.errText(e);
        _shake++;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
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
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: KengashMark(size: 72, directions: true)),
                  const SizedBox(height: S.x5),
                  Text(s.t('seat_title'), textAlign: TextAlign.center, style: AppType.title1.copyWith(color: c.text)),
                  const SizedBox(height: S.x2),
                  Text(s.t('seat_text'), textAlign: TextAlign.center, style: AppType.callout.copyWith(color: c.text2)),
                  const SizedBox(height: S.x6),
                  Shake(
                    trigger: _shake,
                    child: AppCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        AppTextField(
                          key: const ValueKey('key-field'),
                          controller: _ctrl,
                          label: s.t('key_label'),
                          hint: 'KNG-XXXX-XXXX',
                          icon: Icons.key_rounded,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [_KeyFormatter()],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _redeem(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: S.x2),
                          Text(_error!, style: AppType.footnote.copyWith(color: c.danger)),
                        ],
                        const SizedBox(height: S.x4),
                        AppButton(s.t('continue'),
                            key: const ValueKey('key-submit'), expand: true, loading: _busy, onPressed: _busy ? null : _redeem),
                      ]),
                    ),
                  ),
                  const SizedBox(height: S.x4),
                  AppButton(s.t('no_key'),
                      key: const ValueKey('no-key'),
                      kind: BtnKind.secondary,
                      icon: Icons.help_outline_rounded,
                      expand: true,
                      onPressed: () => Navigator.of(context).push(AppRoute(builder: (_) => const KeyHelpScreen()))),
                  const SizedBox(height: S.x2),
                  AppButton(s.t('logout'), kind: BtnKind.ghost, expand: true, height: 44, onPressed: s.logout),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// KNG-ABCD-EFGH ko‘rinishiga keltiradi / приводит к виду KNG-ABCD-EFGH.
class _KeyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var raw = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (raw.startsWith('KNG')) raw = raw.substring(3);
    if (raw.length > 8) raw = raw.substring(0, 8);
    final buf = StringBuffer();
    if (raw.isNotEmpty) buf.write('KNG-');
    buf.write(raw.substring(0, raw.length.clamp(0, 4)));
    if (raw.length > 4) buf.write('-${raw.substring(4)}');
    final text = buf.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// «Kalitim yo‘q»: o‘rinni tanlang → kim kalit berishini ko‘rsatamiz.
/// «Нет ключа»: выберите место → покажем, кто выдаёт ключ.
class KeyHelpScreen extends StatefulWidget {
  const KeyHelpScreen({super.key});

  @override
  State<KeyHelpScreen> createState() => _KeyHelpScreenState();
}

class _KeyHelpScreenState extends State<KeyHelpScreen> {
  String _level = 'school';
  String? _district;
  Json? _school;
  String? _direction;
  Json? _result;
  bool _loading = false;
  String? _error;

  String? get _placeId => switch (_level) {
        'school' => _school?['id'] as String?,
        'district' => _district,
        _ => 'andijon',
      };

  Future<void> _lookup() async {
    final s = AppScope.read(context);
    final pid = _placeId;
    if (pid == null || _direction == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await s.api.get('/api/key-contacts', query: {'level': _level, 'place_id': pid, 'direction': _direction!});
      setState(() => _result = r);
    } on ApiError catch (e) {
      setState(() => _error = s.errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;

    Widget step(String label, String? value, IconData icon, VoidCallback? onTap, {Widget? leading}) => GroupRow(
          key: ValueKey('help-$label'),
          icon: icon,
          color: c.accent,
          title: label,
          value: value ?? s.t('choose'),
          onTap: onTap,
          trailing: leading,
        );

    final rows = <Widget>[
      if (_level != 'region')
        step(s.t('district'), _district == null ? null : s.districtName(_district), Icons.map_rounded, () async {
          final d = await pickDistrict(context);
          if (d != null) {
            setState(() {
              _district = d;
              _school = null;
              _result = null;
            });
            if (_level == 'district') _lookup();
          }
        }),
      if (_level == 'school')
        step(
            s.t('school'),
            _school == null ? null : s.pick(_school, 'name'),
            Icons.school_rounded,
            _district == null
                ? null
                : () async {
                    final x = await pickSchool(context, _district!);
                    if (x != null) {
                      setState(() {
                        _school = x;
                        _result = null;
                      });
                      _lookup();
                    }
                  }),
      step(s.t('direction'), _direction == null ? null : s.dirName(_direction), Icons.category_rounded, () async {
        final d = await pickDirection(context);
        if (d != null) {
          setState(() {
            _direction = d;
            _result = null;
          });
          _lookup();
        }
      }),
    ];

    final contacts = [for (final x in (_result?['contacts'] as List? ?? [])) (x as Map).cast<String, dynamic>()];
    final admin = (_result?['admin'] as Map?)?.cast<String, dynamic>();

    return PageShell(
      child: TabPage(
        title: s.t('key_help_title'),
        subtitle: s.t('key_help_text'),
        children: [
          Segmented<String>(
            values: const ['school', 'district', 'region'],
            labels: [s.t('lvl_school'), s.t('lvl_district'), s.t('lvl_region')],
            value: _level,
            onChanged: (v) => setState(() {
              _level = v;
              _result = null;
            }),
          ),
          GroupList(rows),
          if (_loading) const SkeletonRows(count: 2),
          if (_error != null) EmptyState(icon: Icons.wifi_off_rounded, title: _error!, error: true),
          if (_result != null) ...[
            if (_result!['taken'] == true)
              AppCard(
                kind: CardKind.tinted,
                child: Text(s.t('seat_taken_hint'), style: AppType.subhead.copyWith(color: c.text)),
              ),
            SectionHeader(s.t('who_gives_key')),
            if (contacts.isEmpty && admin == null)
              EmptyState(icon: Icons.person_search_rounded, title: s.t('no_contacts'), message: s.t('no_contacts_text')),
            for (final x in contacts)
              if (x['kind'] == 'user') UserCard(user: (x['user'] as Map).cast<String, dynamic>()) else _ContactCard(x),
            if (admin != null) ...[
              SectionHeader(s.t('or_admin')),
              UserCard(user: admin),
            ],
          ],
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final Json x;
  const _ContactCard(this.x);

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final tg = x['tg_username'] as String;
    return AppCard(
      child: Row(children: [
        DirectionTile(x['direction'] as String, size: 44),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('@$tg', style: AppType.headline.copyWith(color: c.text)),
            Text('${s.dirName(x['direction'] as String)} · ${s.placeLine((x['place'] as Map?)?.cast<String, dynamic>())}',
                style: AppType.footnote.copyWith(color: c.text2)),
          ]),
        ),
        AppButton(s.t('write'), height: 40, icon: Icons.send_rounded, onPressed: () => s.openTelegram(tg)),
      ]),
    );
  }
}

/// Profilni to‘ldirish: ism, surat, rozilik / заполнение профиля: имя, фото, согласие.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController _name;
  bool _agree = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: AppScope.read(context).myName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppScope.read(context);
    if (_name.text.trim().length < 3) {
      setState(() => _error = s.t('err_bad_name'));
      return;
    }
    if (!_agree) {
      setState(() => _error = s.t('err_consent'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      s.setMe(await s.api.post('/api/me/profile', {'name': _name.text.trim(), 'consent': true}));
    } on ApiError catch (e) {
      setState(() => _error = s.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(S.page, S.x8, S.page, S.x6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(s.t('setup_title'), textAlign: TextAlign.center, style: AppType.title1.copyWith(color: c.text)),
                const SizedBox(height: S.x2),
                Text(s.seatLine(s.me), textAlign: TextAlign.center, style: AppType.callout.copyWith(color: c.accentText)),
                const SizedBox(height: S.x6),
                const Center(child: PhotoEditor(size: 110)),
                const SizedBox(height: S.x6),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    AppTextField(
                      key: const ValueKey('name-field'),
                      controller: _name,
                      label: s.t('full_name'),
                      hint: s.t('full_name_hint'),
                      icon: Icons.person_rounded,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: S.x4),
                    ConsentTick(value: _agree, onChanged: (v) => setState(() => _agree = v)),
                    if (_error != null) ...[
                      const SizedBox(height: S.x2),
                      Text(_error!, style: AppType.footnote.copyWith(color: c.danger)),
                    ],
                    const SizedBox(height: S.x4),
                    AppButton(s.t('done'),
                        key: const ValueKey('setup-save'),
                        expand: true,
                        loading: _busy,
                        onPressed: _busy || !_agree ? null : _save),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Qoidalarga roziman» belgisi / галочка «Согласен с правилами».
class ConsentTick extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const ConsentTick({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Pressable(
        key: const ValueKey('consent'),
        onTap: () => onChanged(!value),
        semanticLabel: s.t('agree_rules'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: value ? c.accent : c.surface,
            borderRadius: R.all(7),
            border: Border.all(color: value ? c.accent : c.hairlineStrong, width: 1.6),
          ),
          child: value ? const Icon(Icons.check_rounded, size: 18, color: kWhite) : null,
        ),
      ),
      const SizedBox(width: S.x3),
      Expanded(
        child: Wrap(children: [
          GestureDetector(
            onTap: () => onChanged(!value),
            child: Text('${s.t('agree_rules')} ', style: AppType.subhead.copyWith(color: c.text)),
          ),
          LegalLinks(pages: const ['terms', 'privacy'], inline: true),
        ]),
      ),
    ]);
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
