// Oy kitobi: har yo‘nalish uchun bitta kitob; ilova ichida PDF o‘qish.
// Книга месяца: по одной книге на направление; чтение PDF внутри приложения.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfrx/pdfrx.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
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
          : Image.network(url!, width: width, height: height, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph),
    );
  }
}

// ============================================================ kitob sahifasi / страница книги
class BookScreen extends StatefulWidget {
  final Json book;
  const BookScreen({super.key, required this.book});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  late Json _b = widget.book;
  bool _busy = false;

  Future<void> _toggleRead() async {
    final s = AppScope.read(context);
    final next = _b['my_read'] != true;
    setState(() => _busy = true);
    try {
      final r = await s.api.post('/api/books/${_b['id']}/read', {'read': next});
      setState(() => _b = {..._b, 'my_read': r['my_read'], 'reads': r['reads']});
      if (next) s.toast(s.t('book_read_toast'), icon: Icons.check_circle_rounded);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final dir = _b['direction'] as String?;
    final col = directionColor(dir);
    final page = s.bookPage(_b['id'] as String);
    final read = _b['my_read'] == true;
    final cover = (_b['cover_url'] ?? '').toString();
    return PageShell(
      child: Stack(children: [
        // muqovadan xira rangli fon / размытый цветной фон из обложки
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 420,
          child: IgnorePointer(
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.transparent],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: cover.isEmpty
                    ? Container(color: col.withValues(alpha: 0.4))
                    : Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: col)),
              ),
            ),
          ),
        ),
        TabPage(
          children: [
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: R.all(R.lg),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 16))],
                ),
                child: Hero(tag: 'book-cover-${_b['id']}', child: BookCover(url: cover, width: 200, height: 290)),
              ),
            ),
            Glass(
              color: col.withValues(alpha: c.isDark ? 0.18 : 0.10),
              padding: const EdgeInsets.all(S.x4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: col.withValues(alpha: 0.16), borderRadius: R.all(R.pill)),
                    child: Text('${bookEmoji(dir)} ${s.dirName(dir)}',
                        style: AppType.caption.copyWith(color: c.text, fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  Text('👥 ${s.t('book_reads')}: ${_b['reads']}',
                      key: const ValueKey('book-reads'), style: AppType.footnote.copyWith(color: c.text2)),
                ]),
                const SizedBox(height: S.x3),
                Text((_b['title'] ?? '').toString(), style: AppType.title2.copyWith(color: c.text)),
                if ((_b['author'] ?? '').toString().isNotEmpty)
                  Text(_b['author'] as String, style: AppType.callout.copyWith(color: c.text2)),
                if ((_b['description'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: S.x3),
                  Text(_b['description'] as String, style: AppType.body.copyWith(color: c.text, height: 1.45)),
                ],
              ]),
            ),
            AppButton(
              page > 1 ? '${s.t('book_continue')} · $page-${s.t('book_page')}' : s.t('book_read_btn'),
              key: const ValueKey('book-open'),
              icon: Icons.auto_stories_rounded,
              expand: true,
              onPressed: (_b['pdf_url'] ?? '').toString().isEmpty
                  ? null
                  : () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: _b)));
                      if (mounted) setState(() {});
                    },
            ),
            AppButton(
              read ? s.t('book_done') : s.t('book_mark'),
              key: const ValueKey('book-mark'),
              kind: BtnKind.secondary,
              icon: read ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
              expand: true,
              onPressed: _busy ? null : _toggleRead,
            ),
          ],
        ),
      ]),
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
            onViewerReady: (doc, ctl) => setState(() => _count = doc.pages.length),
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
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: const [Color(0xCC000000), Color(0x66000000)],
            ),
          ),
          child: SafeArea(
            top: top,
            bottom: !top,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1), child: child),
          ),
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
