// Oy kitobi: har yo‘nalish uchun bitta kitob; ilova ichida PDF o‘qish.
// Книга месяца: по одной книге на направление; чтение PDF внутри приложения.
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfrx/pdfrx.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../sound.dart';
import 'directory.dart' show confirmSheet;

String bookEmoji(String? d) => kDirectionEmoji[d] ?? '📖';

// ============================================================ Bugun: javon / Сегодня: полка
/// Bugun sahifasidagi «Oy kitobi» javoni. Kitob bo‘lmasa — umuman ko‘rinmaydi.
/// Полка «Книга месяца» на главной. Нет книг — не показывается вовсе.
class BooksShelf extends StatefulWidget {
  const BooksShelf({super.key});

  @override
  State<BooksShelf> createState() => _BooksShelfState();
}

class _BooksShelfState extends State<BooksShelf> {
  List<Json>? _books;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/books');
      if (mounted) setState(() => _books = [for (final x in r['books'] as List) (x as Map).cast<String, dynamic>()]);
    } on ApiError catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final books = _books ?? const [];
    if (books.isEmpty) return const SizedBox.shrink();
    final month = (books.first['month'] ?? '').toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: S.x1, bottom: S.x3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('📚 ${s.t('books_title')}', style: AppType.title3.copyWith(color: c.text)),
          const SizedBox(width: S.x2),
          if (month.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(month, style: AppType.footnote.copyWith(color: c.text3)),
            ),
        ]),
      ),
      SizedBox(
        height: 330,
        child: ListView.separated(
          key: const ValueKey('books-shelf'),
          scrollDirection: Axis.horizontal,
          // kompyuterda qo‘shni ustunga chiqib ketmasin / на компьютере не заходить на соседнюю колонку
          clipBehavior: isWide(context) ? Clip.hardEdge : Clip.none,
          itemCount: books.length,
          separatorBuilder: (_, __) => const SizedBox(width: S.x3),
          itemBuilder: (_, i) => BookCard(
            book: books[i],
            onTap: () async {
              await Navigator.of(context).push(AppRoute(builder: (_) => BookScreen(book: books[i])));
              _load();
            },
            // admin: uzoq bosib tahrirlash / админ: долгое нажатие — правка
            onLongPress: s.isAdmin
                ? () async {
                    final ok = await Navigator.of(context).push<bool>(AppRoute(
                        builder: (_) => BookEditorScreen(direction: books[i]['direction'] as String, current: books[i])));
                    if (ok == true) _load();
                  }
                : null,
          ),
        ),
      ),
    ]);
  }
}

/// Kitob kartasi: muqova, yo‘nalish rangidagi «suyuq shisha», emoji, nom va qisqa tavsif.
/// Карточка книги: обложка, «жидкое стекло» цвета направления, эмодзи, название и описание.
class BookCard extends StatelessWidget {
  final Json book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const BookCard({super.key, required this.book, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final dir = book['direction'] as String?;
    final col = directionColor(dir);
    final mine = dir != null && dir == s.me?['direction'];
    return Pressable(
      key: ValueKey('book-$dir'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 168,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: R.all(R.xl),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [col.withValues(alpha: c.isDark ? 0.45 : 0.30), col.withValues(alpha: c.isDark ? 0.12 : 0.06)],
            ),
            border: Border.all(color: mine ? col : col.withValues(alpha: 0.25), width: mine ? 2 : 1),
            boxShadow: [BoxShadow(color: col.withValues(alpha: 0.22), blurRadius: 22, offset: const Offset(0, 10))],
          ),
          child: Padding(
            padding: const EdgeInsets.all(S.x2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(children: [
                Hero(
                  tag: 'book-cover-${book['id']}',
                  child: BookCover(url: book['cover_url'] as String?, width: 152, height: 210, radius: R.lg),
                ),
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 6,
                  child: Glass(
                    radius: R.md,
                    blur: 18,
                    color: col.withValues(alpha: 0.35),
                    shadow: const [],
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Row(children: [
                      Text(bookEmoji(dir), style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(s.dirName(dir),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.caption.copyWith(color: kWhite, fontWeight: FontWeight.w800)),
                      ),
                      if (book['my_read'] == true) const Icon(Icons.check_circle_rounded, size: 15, color: kWhite),
                    ]),
                  ),
                ),
              ]),
              if (s.bookPage(book['id'] as String) > 1 && s.bookTotal(book['id'] as String) > 0) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: R.all(R.pill),
                  child: LinearProgressIndicator(
                    value: (s.bookPage(book['id'] as String) / s.bookTotal(book['id'] as String)).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: c.hairline,
                    color: col,
                  ),
                ),
              ],
              const SizedBox(height: S.x2),
              Text((book['title'] ?? '').toString(),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong.copyWith(color: c.text, height: 1.2)),
              const SizedBox(height: 2),
              Text((book['description'] ?? '').toString(),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.caption.copyWith(color: c.text2)),
            ]),
          ),
        ),
      ),
    );
  }
}

class BookCover extends StatelessWidget {
  final String? url;
  final double width;
  final double height;
  final double radius;
  const BookCover({super.key, required this.url, required this.width, required this.height, this.radius = R.lg});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final ph = Container(
      width: width,
      height: height,
      color: c.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(Icons.menu_book_rounded, color: c.text3, size: 40),
    );
    return ClipRRect(
      borderRadius: R.all(radius),
      child: (url ?? '').isEmpty
          ? ph
          : Image.network(url!,
              width: width,
              height: height,
              fit: BoxFit.cover,
              // tiniq: katta muqova kichraytirilganda ham silliq / чётко: большая обложка уменьшается без «лесенки»
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => ph),
    );
  }
}

// ============================================================ kitob sahifasi / страница книги
Color _hex(Object? h, Color fallback) {
  final v = (h ?? '').toString().replaceFirst('#', '');
  final n = int.tryParse(v, radix: 16);
  return v.length == 6 && n != null ? Color(0xFF000000 | n) : fallback;
}

/// Kitob ranglari (server muqovadan hisoblaydi): asosiy, aksent, to‘q.
/// Цвета книги (сервер вычисляет по обложке): основной, акцент, тёмный.
(Color, Color, Color) bookColors(Json b) {
  final fb = directionColor(b['direction'] as String?);
  final cols = (b['colors'] as List?) ?? const [];
  final base = _hex(cols.isNotEmpty ? cols[0] : null, Color.lerp(fb, kWhite, 0.6)!);
  final accent = _hex(cols.length > 1 ? cols[1] : null, fb);
  final deep = _hex(cols.length > 2 ? cols[2] : null, Color.lerp(fb, Colors.black, 0.5)!);
  return (base, accent, deep);
}

/// Kitob sahifasi: muqova ranglaridan butun ekranli gradient, aylantirsa bo‘ladigan 3D muqova,
/// o‘qish jarayoni, o‘qiganlar, tavsif.
/// Страница книги: полноэкранный градиент из цветов обложки, 3D-обложка (можно покрутить),
/// прогресс чтения, кто прочитал, описание.
class BookScreen extends StatefulWidget {
  final Json book;
  const BookScreen({super.key, required this.book});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> with TickerProviderStateMixin {
  late Json _b = widget.book;
  bool _busy = false;
  bool _more = false;
  double _rx = 0, _ry = 0;
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))
    ..addListener(() {
      final t = Curves.elasticOut.transform(_back.value);
      setState(() {
        _rx = _fromX * (1 - t);
        _ry = _fromY * (1 - t);
      });
    });
  double _fromX = 0, _fromY = 0;

  /// Nur juda sekin «nafas oladi» (faqat yorug‘lik qatlami qayta chiziladi)
  /// Свечение медленно «дышит» (перерисовывается только слой света)
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.read(context);
    if (MediaQuery.disableAnimationsOf(context) || s.testMode) {
      _glow.value = 0.6;
    } else if (!_glow.isAnimating) {
      _glow.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    _back.dispose();
    super.dispose();
  }

  Future<void> _toggleRead() async {
    final s = AppScope.read(context);
    final next = _b['my_read'] != true;
    setState(() => _busy = true);
    try {
      final r = await s.api.post('/api/books/${_b['id']}/read', {'read': next});
      setState(() => _b = {..._b, 'my_read': r['my_read'], 'reads': r['reads']});
      if (next) {
        Sfx.success();
        s.toast(s.t('book_read_toast'), icon: Icons.check_circle_rounded);
      }
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: _b)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final id = _b['id'] as String;
    final dir = _b['direction'] as String?;
    final (base, accent, deep) = bookColors(_b);
    final page = s.bookPage(id);
    final total = s.bookTotal(id);
    final started = page > 1;
    final pct = total > 0 ? (page / total).clamp(0.0, 1.0) : 0.0;
    final read = _b['my_read'] == true;
    final cover = (_b['cover_url'] ?? '').toString();
    final desc = (_b['description'] ?? '').toString();
    final readers = [for (final x in (_b['readers'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    final reads = (_b['reads'] as num?)?.toInt() ?? 0;

    return PageShell(
      child: Stack(children: [
        // Muqova ranglaridan butun ekranli gradient (keskin chegara yo‘q) / полноэкранный градиент без резких краёв
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('book-bg'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(base, deep, 0.35)!,
                    Color.lerp(Color.lerp(base, accent, 0.6)!, deep, 0.18)!,
                    Color.lerp(accent, c.bg, 0.55)!,
                    c.bg
                  ],
                  stops: const [0, 0.3, 0.6, 0.92],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.45),
                    radius: 0.75,
                    colors: [accent.withValues(alpha: 0.55), accent.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        ),
        ListView(
          padding: EdgeInsets.fromLTRB(S.page, S.x2, S.page, MediaQuery.paddingOf(context).bottom + S.x8),
          physics: const BouncingScrollPhysics(),
          children: [
            Row(children: [
              Pressable(
                key: const ValueKey('book-back'),
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.surface.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                    border: Border.all(color: c.hairline),
                  ),
                  child: Icon(Icons.arrow_back_rounded, color: c.text, size: 22),
                ),
              ),
            ]),
            const SizedBox(height: S.x4),
            // 3D muqova: barmoq bilan aylantiring; ortida — yorug‘lik (kitob «porlaydi»)
            // 3D-обложка: покрутите пальцем; сзади — свет (книга «светится»)
            Center(
              child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                Positioned(
                  left: -150,
                  right: -150,
                  top: -110,
                  bottom: -110,
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _glow,
                        builder: (_, __) => CustomPaint(
                          key: const ValueKey('book-glow'),
                          painter: _BookGlow(accent: accent, base: base, t: Curves.easeInOut.transform(_glow.value)),
                        ),
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                key: const ValueKey('book-cover-3d'),
                onPanStart: (_) => _back.stop(),
                onPanUpdate: (d) => setState(() {
                  _rx = (_rx - d.delta.dy * 0.008).clamp(-0.35, 0.35);
                  _ry = (_ry + d.delta.dx * 0.008).clamp(-0.5, 0.5);
                }),
                onPanEnd: (_) {
                  _fromX = _rx;
                  _fromY = _ry;
                  _back.forward(from: 0);
                },
                onTap: (_b['pdf_url'] ?? '').toString().isEmpty ? null : _open,
                child: Hero(
                  tag: 'book-cover-$id',
                  child: _Book3D(url: cover, width: 230, height: 316, deep: deep, rx: _rx, ry: _ry),
                ),
              ),
              ]),
            ),
            const SizedBox(height: S.x6),
            Appear(
              index: 1,
              child: Container(
                padding: const EdgeInsets.all(S.x5),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withValues(alpha: c.isDark ? 0.10 : 0.06), c.surface),
                  borderRadius: R.all(R.xl),
                  border: Border.all(color: accent.withValues(alpha: 0.25)),
                  boxShadow: [BoxShadow(color: deep.withValues(alpha: 0.18), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), borderRadius: R.all(R.pill)),
                      child: Text('${bookEmoji(dir)} ${s.dirName(dir)}',
                          style: AppType.caption.copyWith(color: c.text, fontWeight: FontWeight.w700)),
                    ),
                    const Spacer(),
                    if ((_b['month'] ?? '').toString().isNotEmpty)
                      Text((_b['month']).toString(), style: AppType.footnote.copyWith(color: c.text3)),
                  ]),
                  const SizedBox(height: S.x3),
                  Text((_b['title'] ?? '').toString(),
                      style: AppType.title1.copyWith(color: c.text, height: 1.1, letterSpacing: -0.6)),
                  if ((_b['author'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_b['author'] as String, style: AppType.callout.copyWith(color: c.text2)),
                  ],
                  const SizedBox(height: S.x4),
                  // ko‘rsatkichlar / показатели
                  Row(children: [
                    _Stat(value: '$reads', label: s.t('book_reads'), key: const ValueKey('book-reads')),
                    _Stat(value: total > 0 ? '$total' : '—', label: s.t('book_pages')),
                    _Stat(value: started ? '${(pct * 100).round()}%' : '0%', label: s.t('book_progress')),
                  ]),
                  if (started) ...[
                    const SizedBox(height: S.x4),
                    ClipRRect(
                      borderRadius: R.all(R.pill),
                      child: LinearProgressIndicator(
                        key: const ValueKey('book-progress'),
                        value: total > 0 ? pct : null,
                        minHeight: 8,
                        backgroundColor: c.hairline,
                        color: accent.computeLuminance() > 0.75 ? deep : accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(total > 0 ? '$page / $total ${s.t('book_page_short')}' : '$page-${s.t('book_page')}',
                        style: AppType.caption.copyWith(color: c.text2)),
                  ],
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: S.x4),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      alignment: Alignment.topCenter,
                      child: Text(desc,
                          maxLines: _more ? null : 4,
                          overflow: _more ? TextOverflow.visible : TextOverflow.fade,
                          style: AppType.body.copyWith(color: c.text, height: 1.5)),
                    ),
                    if (desc.length > 180)
                      Pressable(
                        onTap: () => setState(() => _more = !_more),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(s.t(_more ? 'book_less' : 'book_more'),
                              style: AppType.subhead.copyWith(color: c.accentText, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                  if (readers.isNotEmpty) ...[
                    const SizedBox(height: S.x4),
                    Row(children: [
                      SizedBox(
                        width: 26.0 * readers.take(5).length + 10,
                        height: 34,
                        child: Stack(children: [
                          for (final (i, u) in readers.take(5).indexed)
                            Positioned(
                              left: i * 26.0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                                child: AppAvatar(url: s.photoUrl(u['photo']), name: (u['name'] ?? '').toString(), size: 30),
                              ),
                            ),
                        ]),
                      ),
                      const SizedBox(width: S.x2),
                      Expanded(
                        child: Text(
                            reads > 1
                                ? '${givenFirst(readers.first['name'])} ${s.t('book_and_more').replaceAll('{n}', '${reads - 1}')}'
                                : '${givenFirst(readers.first['name'])} ${s.t('book_read_one')}',
                            maxLines: 2,
                            style: AppType.footnote.copyWith(color: c.text2)),
                      ),
                    ]),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: S.x5),
            Appear(
              index: 2,
              child: AppButton(
                started ? '${s.t('book_continue')} · $page-${s.t('book_page')}' : s.t('book_read_btn'),
                key: const ValueKey('book-open'),
                icon: Icons.auto_stories_rounded,
                expand: true,
                onPressed: (_b['pdf_url'] ?? '').toString().isEmpty ? null : _open,
              ),
            ),
            const SizedBox(height: S.x3),
            Appear(
              index: 3,
              child: AppButton(
                read ? s.t('book_done') : s.t('book_mark'),
                key: const ValueKey('book-mark'),
                kind: BtnKind.secondary,
                icon: read ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                expand: true,
                onPressed: _busy ? null : _toggleRead,
              ),
            ),
          ],
        ),
      ]),
    );
  }
}

String givenFirst(Object? name) => (name ?? '').toString().trim().split(RegExp(r'\s+')).last;

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: AppType.title3.copyWith(color: c.text, fontWeight: FontWeight.w800)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.caption.copyWith(color: c.text3)),
      ]),
    );
  }
}

/// Kitob ortidagi nur: oq-iliq yadro, kitob rangidagi halo va tarqaluvchi yumshoq nurlar.
/// Свет за книгой: тёплое белое ядро, ореол цвета книги и мягкие расходящиеся лучи.
class _BookGlow extends CustomPainter {
  final Color accent;
  final Color base;
  final double t; // 0..1 nafas / «дыхание»
  _BookGlow({required this.accent, required this.base, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide * 0.62;
    final light = Color.lerp(accent, kWhite, 0.3)!;

    // tarqaluvchi nurlar / расходящиеся лучи
    final rays = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        transform: GradientRotation(t * 0.25),
        colors: [
          for (var i = 0; i < 16; i++) ...[
            light.withValues(alpha: 0.0),
            light.withValues(alpha: 0.42 + 0.18 * t),
          ],
          light.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: r * 1.4));
    canvas.save();
    // nurlar chetga qarab so‘nadi / лучи гаснут к краям
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawCircle(center, r * 1.4, rays);
    canvas.drawCircle(
      center,
      r * 1.4,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = RadialGradient(colors: [
          Colors.white,
          Colors.white.withValues(alpha: 0.5),
          Colors.white.withValues(alpha: 0.0),
        ], stops: const [0.2, 0.62, 1]).createShader(Rect.fromCircle(center: center, radius: r * 1.4)),
    );
    canvas.restore();
    canvas.restore();

    // kitob rangidagi halo / ореол цвета книги
    canvas.drawCircle(
      center,
      r * (0.95 + 0.06 * t),
      Paint()
        ..shader = RadialGradient(colors: [
          Color.lerp(accent, kWhite, 0.2)!.withValues(alpha: 0.85 + 0.15 * t),
          accent.withValues(alpha: 0.35),
          accent.withValues(alpha: 0.0),
        ], stops: const [0.0, 0.55, 1]).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    // oq-iliq yadro (kitob ortida porlash) / тёплое белое ядро
    canvas.drawOval(
      Rect.fromCenter(center: center, width: r * 1.15, height: r * 1.45),
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.95),
          const Color(0xFFFFF6DC).withValues(alpha: 0.55 + 0.25 * t),
          Colors.white.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCenter(center: center, width: r * 1.15, height: r * 1.45)),
    );
  }

  @override
  bool shouldRepaint(_BookGlow old) => old.t != t || old.accent != accent || old.base != base;
}

/// Haqiqiy kitobga o‘xshash muqova: umurtqa, varaq qirrasi, yaltiroq, rangli soya; 3D burilish.
/// Обложка как у настоящей книги: корешок, край страниц, блик, цветная тень; 3D-поворот.
class _Book3D extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final Color deep;
  final double rx;
  final double ry;
  const _Book3D(
      {required this.url, required this.width, required this.height, required this.deep, this.rx = 0, this.ry = 0});

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.only(
        topLeft: Radius.circular(4), bottomLeft: Radius.circular(4), topRight: Radius.circular(12), bottomRight: Radius.circular(12));
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0014)
        ..rotateX(rx)
        ..rotateY(ry),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
                color: deep.withValues(alpha: 0.55), blurRadius: 40, spreadRadius: -6, offset: Offset(-ry * 40, 26 + rx * 30)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(fit: StackFit.expand, children: [
            BookCover(url: url, width: width, height: height, radius: 0),
            // umurtqa / корешок
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.black.withValues(alpha: 0.38),
                    Colors.black.withValues(alpha: 0.06),
                    Colors.white.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.0),
                  ], stops: const [0, 0.45, 0.6, 1]),
                ),
              ),
            ),
            // yaltiroq (burilishga qarab siljiydi) / блик (смещается при повороте)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1 + ry * 2, -1),
                    end: Alignment(1 + ry * 2, 1),
                    colors: [Colors.white.withValues(alpha: 0.0), Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0.0)],
                    stops: const [0.3, 0.5, 0.7],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ============================================================ o‘qish / чтение
/// PDF o‘qish: varaqlash, chimchilab kattalashtirish, sahifaga o‘tish, tungi rejim, qolgan joyni eslab qoladi.
/// Чтение PDF: листание, зум, переход к странице, ночной режим, запоминает место.
class ReaderScreen extends StatefulWidget {
  final Json book;
  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _ctl = PdfViewerController();
  bool _chrome = true;
  bool _night = false;
  int _page = 1;
  int _count = 0;
  double? _drag;

  String get _id => widget.book['id'] as String;

  @override
  void initState() {
    super.initState();
    _page = AppScope.read(context).bookPage(_id);
  }

  static const _invert = ColorFilter.matrix([
    -0.9, 0, 0, 0, 235, //
    0, -0.9, 0, 0, 230,
    0, 0, -0.9, 0, 220,
    0, 0, 0, 1, 0,
  ]);

  void _go(int p) {
    if (_count == 0) return;
    _ctl.goToPage(pageNumber: p.clamp(1, _count));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final bg = _night ? const Color(0xFF111015) : const Color(0xFF2B2A33);
    final url = (widget.book['pdf_url'] ?? '').toString();
    final shown = _drag?.round() ?? _page;
    return Scaffold(
      backgroundColor: bg,
      body: Stack(fit: StackFit.expand, children: [
        PdfViewer.uri(
          Uri.parse(url),
          key: const ValueKey('pdf-viewer'),
          controller: _ctl,
          initialPageNumber: _page,
          params: PdfViewerParams(
            backgroundColor: bg,
            margin: 10,
            maxScale: 8,
            pageDropShadow: const BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4)),
            pageImageColorFilter: _night ? _invert : null,
            textSelectionParams: const PdfTextSelectionParams(enabled: false),
            onViewerReady: (doc, ctl) {
              s.setBookTotal(_id, doc.pages.length);
              setState(() => _count = doc.pages.length);
            },
            onPageChanged: (p) {
              if (p == null) return;
              s.setBookPage(_id, p);
              setState(() => _page = p);
            },
            onGeneralTap: (ctx, ctl, d) {
              if (d.type == PdfViewerGeneralTapType.tap) {
                setState(() => _chrome = !_chrome);
                return true;
              }
              return false;
            },
            loadingBannerBuilder: (ctx, got, total) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: total == null || total == 0 ? null : got / total,
                    color: kWhite,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: S.x3),
                Text(
                  total == null || total == 0
                      ? s.t('book_loading')
                      : '${s.t('book_loading')} ${(got * 100 / total).round()}%',
                  style: AppType.subhead.copyWith(color: Colors.white70),
                ),
              ]),
            ),
            errorBannerBuilder: (ctx, e, st, ref) => Center(
              child: Padding(
                padding: const EdgeInsets.all(S.x6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wifi_off_rounded, color: Colors.white70, size: 44),
                  const SizedBox(height: S.x3),
                  Text(s.t('book_error'), textAlign: TextAlign.center, style: AppType.body.copyWith(color: kWhite)),
                ]),
              ),
            ),
          ),
        ),
        // yuqori panel / верхняя панель
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          top: _chrome ? 0 : -120,
          left: 0,
          right: 0,
          child: _Bar(
            top: true,
            child: Row(children: [
              IconButton(
                  key: const ValueKey('reader-close'),
                  tooltip: s.t('back'),
                  icon: const Icon(Icons.arrow_back_rounded, color: kWhite),
                  onPressed: () => Navigator.of(context).pop()),
              Expanded(
                child: Text((widget.book['title'] ?? '').toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.headline.copyWith(color: kWhite)),
              ),
              IconButton(
                  key: const ValueKey('reader-night'),
                  tooltip: s.t('book_night'),
                  icon: Icon(_night ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: kWhite),
                  onPressed: () => setState(() => _night = !_night)),
            ]),
          ),
        ),
        // pastki panel: sahifa va surgich / нижняя панель: страница и ползунок
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          bottom: _chrome ? 0 : -140,
          left: 0,
          right: 0,
          child: _Bar(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_count > 1)
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: kWhite,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: kWhite,
                    overlayColor: Colors.white24,
                    trackHeight: 3,
                  ),
                  child: Slider(
                    key: const ValueKey('reader-slider'),
                    min: 1,
                    max: _count.toDouble(),
                    value: (_drag ?? _page.toDouble()).clamp(1, _count.toDouble()),
                    onChanged: (v) => setState(() => _drag = v),
                    onChangeEnd: (v) {
                      setState(() => _drag = null);
                      _go(v.round());
                    },
                  ),
                ),
              Row(children: [
                IconButton(
                    key: const ValueKey('reader-prev'),
                    tooltip: s.t('book_prev'),
                    icon: const Icon(Icons.chevron_left_rounded, color: kWhite, size: 30),
                    onPressed: _page > 1 ? () => _go(_page - 1) : null),
                Expanded(
                  child: Text(_count == 0 ? '' : '$shown / $_count',
                      key: const ValueKey('reader-page'),
                      textAlign: TextAlign.center,
                      style: AppType.bodyStrong.copyWith(color: kWhite)),
                ),
                IconButton(
                    key: const ValueKey('reader-next'),
                    tooltip: s.t('book_next'),
                    icon: const Icon(Icons.chevron_right_rounded, color: kWhite, size: 30),
                    onPressed: _count > 0 && _page < _count ? () => _go(_page + 1) : null),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  final bool top;
  final Widget child;
  const _Bar({required this.top, required this.child});

  @override
  Widget build(BuildContext context) {
    // xiralashtirishsiz: PDF varaqlanayotganda har kadrda qayta hisoblanmasin / без размытия ради плавной прокрутки PDF
    return ClipRect(
      child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: const [Color(0xE6000000), Color(0x99000000)],
            ),
          ),
          child: SafeArea(
            top: top,
            bottom: !top,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1), child: child),
          ),
      ),
    );
  }
}

// ============================================================ admin
/// Admin: 8 yo‘nalish — har biriga kitob qo‘shish yoki almashtirish.
/// Админ: 8 направлений — добавить или заменить книгу.
class AdminBooksScreen extends StatefulWidget {
  const AdminBooksScreen({super.key});

  @override
  State<AdminBooksScreen> createState() => _AdminBooksScreenState();
}

class _AdminBooksScreenState extends State<AdminBooksScreen> {
  Map<String, Json>? _byDir;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/books');
      if (mounted) {
        setState(() => _byDir = {
              for (final x in r['books'] as List) ((x as Map)['direction'] as String): x.cast<String, dynamic>()
            });
      }
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
        title: '📚 ${s.t('books_title')}',
        subtitle: s.t('books_admin_sub'),
        onRefresh: _load,
        children: [
          if (_byDir == null)
            const SkeletonRows(count: 8)
          else
            GroupList([
              for (final d in s.directions)
                Builder(builder: (_) {
                  final dir = d['id'] as String;
                  final b = _byDir![dir];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: ValueKey('admin-book-$dir'),
                      onTap: () async {
                        final ok = await Navigator.of(context)
                            .push<bool>(AppRoute(builder: (_) => BookEditorScreen(direction: dir, current: b)));
                        if (ok == true) _load();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
                        child: Row(children: [
                          b == null
                              ? Container(
                                  width: 40,
                                  height: 56,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: directionColor(dir).withValues(alpha: 0.15), borderRadius: R.all(R.sm)),
                                  child: Text(bookEmoji(dir), style: const TextStyle(fontSize: 20)),
                                )
                              : BookCover(url: b['cover_url'] as String?, width: 40, height: 56, radius: R.xs),
                          const SizedBox(width: S.x3),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${bookEmoji(dir)} ${s.dirName(dir)}',
                                  style: AppType.footnote.copyWith(color: c.text2, fontWeight: FontWeight.w700)),
                              Text(b == null ? s.t('book_add') : (b['title'] ?? '').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.bodyStrong.copyWith(color: b == null ? c.accentText : c.text)),
                              if (b != null)
                                Text('${b['month']} · 👥 ${b['reads']}', style: AppType.caption.copyWith(color: c.text3)),
                            ]),
                          ),
                          Icon(b == null ? Icons.add_circle_rounded : Icons.chevron_right_rounded,
                              color: b == null ? c.accent : c.text3),
                        ]),
                      ),
                    ),
                  );
                }),
            ]),
        ],
      ),
    );
  }
}

/// Kitob qo‘shish/almashtirish: muqova, PDF, nom, muallif, oy, qisqa tavsif. Bitta asosiy tugma — «Saqlash».
/// Добавить/заменить книгу: обложка, PDF, название, автор, месяц, описание. Одна главная кнопка — «Сохранить».
class BookEditorScreen extends StatefulWidget {
  final String direction;
  final Json? current;
  const BookEditorScreen({super.key, required this.direction, this.current});

  @override
  State<BookEditorScreen> createState() => _BookEditorScreenState();
}

class _BookEditorScreenState extends State<BookEditorScreen> {
  late final _title = TextEditingController(text: (widget.current?['title'] ?? '').toString());
  late final _author = TextEditingController(text: (widget.current?['author'] ?? '').toString());
  late final _desc = TextEditingController(text: (widget.current?['description'] ?? '').toString());
  late final _month = TextEditingController(
      text: (widget.current?['month'] ?? '').toString().isNotEmpty
          ? widget.current!['month'] as String
          : _monthName(AppScope.read(context)));
  Uint8List? _cover;
  PlatformFile? _pdf;
  int _pdfSize = 0;
  bool _busy = false;
  String _status = '';

  /// Bor kitobni tuzatish (o‘qiganlar saqlanadi) yoki yangi kitob bilan almashtirish.
  /// Исправить текущую книгу (отметки сохраняются) или заменить новой.
  late bool _editing = widget.current != null;

  void _startNew() {
    final s = AppScope.read(context);
    setState(() {
      _editing = false;
      _title.clear();
      _author.clear();
      _desc.clear();
      _month.text = _monthName(s);
      _cover = null;
      _pdf = null;
    });
  }

  static String _monthName(AppState s) {
    final m = DateTime.now().month;
    const uz = ['Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun', 'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr'];
    const ru = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
    return '${(s.lang == 'ru' ? ru : uz)[m - 1]} ${DateTime.now().year}';
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _desc.dispose();
    _month.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1800, imageQuality: 90);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() => _cover = bytes);
  }

  Future<void> _pickPdf() async {
    final s = AppScope.read(context);
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    if (files.isEmpty) return;
    final f = files.first;
    final size = await f.xFile.length();
    if (size > 50 * 1024 * 1024) {
      s.toast(s.t('err_too_large'));
      return;
    }
    setState(() {
      _pdf = f;
      _pdfSize = size;
    });
  }

  Future<void> _save() async {
    final s = AppScope.read(context);
    if (_title.text.trim().length < 2 || (!_editing && (_cover == null || _pdf == null))) {
      s.toast(s.t('book_fill'));
      return;
    }
    setState(() {
      _busy = true;
      _status = s.t(_pdf != null ? 'book_uploading' : 'saving');
    });
    try {
      String? pdfPath;
      if (_pdf != null) {
        final bytes = await _pdf!.xFile.readAsBytes();
        final up = await s.api.post('/api/admin/books/upload', {'size': bytes.length});
        final res = await s.api.client
            .put(Uri.parse(up['upload_url'] as String),
                headers: {'Content-Type': 'application/pdf', 'x-upsert': 'false'}, body: bytes)
            .timeout(const Duration(minutes: 10));
        if (res.statusCode >= 300) throw ApiError(res.statusCode, 'upload_failed');
        pdfPath = up['path'] as String;
      }
      if (mounted) setState(() => _status = s.t('saving'));
      await s.api.post(
          '/api/admin/books',
          {
            'direction': widget.direction,
            'title': _title.text.trim(),
            'author': _author.text.trim(),
            'description': _desc.text.trim(),
            'month': _month.text.trim(),
            if (_cover != null) 'cover': base64Encode(_cover!),
            if (pdfPath != null) 'pdf_path': pdfPath,
            if (_editing) 'edit': true,
          },
          const Duration(seconds: 90));
      s.toast(s.t('saved'), icon: Icons.check_circle_rounded);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final cur = widget.current;
    return PageShell(
      child: TabPage(
        title: '${bookEmoji(widget.direction)} ${s.dirName(widget.direction)}',
        subtitle: cur == null ? s.t('book_add') : '${s.t('book_now')}: ${cur['title']}',
        children: [
          if (cur != null)
            AppCard(
              kind: CardKind.inset,
              child: Text(s.t(_editing ? 'book_edit_hint' : 'book_replace_hint'),
                  style: AppType.footnote.copyWith(color: c.text2)),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Pressable(
              key: const ValueKey('book-cover-pick'),
              onTap: _busy ? null : _pickCover,
              child: Container(
                width: 110,
                height: 160,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: R.all(R.md),
                  border: Border.all(color: c.hairlineStrong),
                ),
                child: _cover == null && _editing && (cur?['cover_url'] ?? '').toString().isNotEmpty
                    ? Image.network(cur!['cover_url'] as String, fit: BoxFit.cover)
                    : _cover == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_photo_alternate_rounded, color: c.accent, size: 32),
                        const SizedBox(height: 6),
                        Text(s.t('book_cover'), textAlign: TextAlign.center, style: AppType.caption.copyWith(color: c.text2)),
                      ])
                    : Image.memory(_cover!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(children: [
                AppTextField(key: const ValueKey('book-title'), controller: _title, hint: s.t('book_name'), maxLength: 120),
                const SizedBox(height: S.x2),
                AppTextField(controller: _author, hint: s.t('book_author'), maxLength: 120),
              ]),
            ),
          ]),
          GroupList([
            GroupRow(
              key: const ValueKey('book-pdf-pick'),
              icon: Icons.picture_as_pdf_rounded,
              color: const Color(0xFFE5484D),
              title: _pdf != null ? _pdf!.name : s.t(_editing ? 'book_change_pdf' : 'book_pick_pdf'),
              value: _pdf == null ? '≤ 50 MB' : '${(_pdfSize / 1024 / 1024).toStringAsFixed(1)} MB',
              onTap: _busy ? null : _pickPdf,
            ),
          ]),
          AppTextField(controller: _month, hint: s.t('book_month'), icon: Icons.calendar_month_rounded, maxLength: 30),
          AppTextField(controller: _desc, hint: s.t('book_desc'), maxLength: 600, maxLines: 4),
          if (_status.isNotEmpty) Text(_status, textAlign: TextAlign.center, style: AppType.footnote.copyWith(color: c.text2)),
          AppButton(s.t('save'),
              key: const ValueKey('book-save'), icon: Icons.check_rounded, expand: true, onPressed: _busy ? null : _save),
          if (cur != null && _editing)
            AppButton(s.t('book_new_month'),
                key: const ValueKey('book-new'),
                kind: BtnKind.secondary,
                icon: Icons.autorenew_rounded,
                expand: true,
                onPressed: _busy ? null : _startNew),
          if (cur != null)
            AppButton(s.t('book_remove'), kind: BtnKind.danger, icon: Icons.delete_rounded, expand: true, onPressed: () async {
              if (!await confirmSheet(context, s.t('book_remove_q'), s.t('book_remove'))) return;
              try {
                await s.api.post('/api/admin/books/${widget.direction}/delete');
                if (context.mounted) Navigator.of(context).pop(true);
              } on ApiError catch (e) {
                s.toast(s.errText(e));
              }
            }),
        ],
      ),
    );
  }
}
