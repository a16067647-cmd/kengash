// «Mening yo‘lim» — portfolio: bajarilgan ishlar, tadbirlar, sertifikatlar, kitoblar; ochiq havola (rezyume uchun).
// «Мой путь» — портфолио: работы, мероприятия, сертификаты, книги; открытая ссылка (для резюме).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'media.dart' show PhotoViewer;

class PortfolioScreen extends StatefulWidget {
  /// null — o‘zimniki / null — мой.
  final String? userId;
  const PortfolioScreen({super.key, this.userId});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  Json? _p;
  String? _error;

  bool get _mine => widget.userId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final p = await s.api.get('/api/portfolio/${widget.userId ?? 'me'}');
      if (mounted) setState(() => _p = p);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = s.errText(e));
    }
  }

  Future<void> _share(bool on) async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.post('/api/portfolio/share?on=$on');
      setState(() {
        _p!['shared'] = r['shared'];
        _p!['share_url'] = r['share_url'];
      });
      if (on) {
        await Clipboard.setData(ClipboardData(text: r['share_url'] as String));
        s.toast(s.t('pf_link_copied'), icon: Icons.link_rounded);
      }
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  String _date(Object? ts) {
    if (ts is! num || ts == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000);
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final p = _p;
    if (p == null) {
      return PageShell(
        child: TabPage(title: s.t('pf_title'), children: [
          if (_error != null)
            EmptyState(icon: Icons.wifi_off_rounded, title: _error!, error: true, actionLabel: s.t('retry'), onAction: _load)
          else
            const SkeletonRows(count: 5),
        ]),
      );
    }
    final u = (p['user'] as Map).cast<String, dynamic>();
    final st = (p['stats'] as Map).cast<String, dynamic>();
    final tasks = [for (final x in p['tasks'] as List) (x as Map).cast<String, dynamic>()];
    final events = [for (final x in p['events'] as List) (x as Map).cast<String, dynamic>()];
    final books = [for (final x in p['books'] as List) (x as Map).cast<String, dynamic>()];
    final certs = [for (final x in p['certificates'] as List) (x as Map).cast<String, dynamic>()];
    final empty = tasks.isEmpty && events.isEmpty && books.isEmpty && certs.isEmpty;
    return PageShell(
      child: TabPage(
        title: _mine ? s.t('pf_title') : (u['name'] ?? '').toString(),
        subtitle: _mine ? s.t('pf_sub') : s.seatLine(u),
        onRefresh: _load,
        children: [
          AppCard(
            child: Row(children: [
              AppAvatar(url: s.photoUrl(u['photo']), name: (u['name'] ?? '').toString(), size: 56),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((u['name'] ?? '').toString(), style: AppType.title3.copyWith(color: c.text)),
                  Text(s.seatLine(u), maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: AppType.footnote.copyWith(color: c.text2)),
                  Text('${s.t('pf_since')} ${_date(u['since'])}', style: AppType.caption.copyWith(color: c.text3)),
                ]),
              ),
            ]),
          ),
          gridOf([
            StatTile(icon: Icons.task_alt_rounded, value: '${st['tasks']}', label: s.t('pf_tasks')),
            StatTile(icon: Icons.event_available_rounded, value: '${st['events']}', label: s.t('pf_events')),
            StatTile(icon: Icons.menu_book_rounded, value: '${st['books']}', label: s.t('pf_books')),
            StatTile(
                icon: Icons.emoji_events_rounded,
                value: st['rank'] == null ? '—' : '${st['rank']}/${st['rank_total']}',
                label: s.t('pf_rank')),
          ], 2),
          if (_mine)
            AppCard(
              key: const ValueKey('pf-share'),
              kind: CardKind.tinted,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(Icons.public_rounded, color: c.accentText),
                  const SizedBox(width: S.x2),
                  Expanded(child: Text(s.t('pf_public'), style: AppType.headline.copyWith(color: c.text))),
                  Switch.adaptive(
                      key: const ValueKey('pf-share-switch'),
                      value: p['shared'] == true,
                      activeTrackColor: c.accent,
                      onChanged: _share),
                ]),
                Text(s.t('pf_public_sub'), style: AppType.footnote.copyWith(color: c.text2)),
                if (p['shared'] == true && (p['share_url'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: S.x3),
                  Row(children: [
                    Expanded(
                      child: AppButton(s.t('copy'),
                          key: const ValueKey('pf-copy'),
                          kind: BtnKind.secondary,
                          icon: Icons.copy_rounded,
                          height: 44,
                          onPressed: () => s.copy(p['share_url'] as String)),
                    ),
                    const SizedBox(width: S.x2),
                    Expanded(
                      child: AppButton(s.t('pf_open'),
                          key: const ValueKey('pf-open'),
                          icon: Icons.open_in_new_rounded,
                          height: 44,
                          onPressed: () => s.openUrl(p['share_url'] as String)),
                    ),
                  ]),
                ],
              ]),
            ),
          if (empty) EmptyState(icon: Icons.route_rounded, title: s.t('pf_empty')),
          if (certs.isNotEmpty) ...[
            SectionHeader('🏅 ${s.t('cert_title')}'),
            for (final x in certs)
              AppCard(
                kind: CardKind.tinted,
                tint: const Color(0x22E8B628),
                child: Row(children: [
                  const Icon(Icons.workspace_premium_rounded, color: Color(0xFFE8B628), size: 32),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text('${x['quarter']} · ${x['rank']}-${s.t('rating_place')} · ${x['group']}',
                        style: AppType.bodyStrong.copyWith(color: c.text)),
                  ),
                ]),
              ),
          ],
          if (tasks.isNotEmpty) ...[
            SectionHeader('📋 ${s.t('pf_done')}'),
            for (final t in tasks)
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text((t['title'] ?? '').toString(), style: AppType.bodyStrong.copyWith(color: c.text))),
                    if (t['accepted'] == true) const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF1F9D55)),
                  ]),
                  Text('${t['by']} · ${_date(t['at'])}', style: AppType.footnote.copyWith(color: c.text2)),
                  if ((t['photo_urls'] as List).isNotEmpty) ...[
                    const SizedBox(height: S.x2),
                    SizedBox(
                      height: 72,
                      child: ListView(scrollDirection: Axis.horizontal, children: [
                        for (final url in (t['photo_urls'] as List).cast<String>())
                          Padding(
                            padding: const EdgeInsets.only(right: S.x2),
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewer(url: url))),
                              child: ClipRRect(
                                borderRadius: R.all(R.sm),
                                child: Image.network(url, width: 96, height: 72, fit: BoxFit.cover, cacheWidth: 288),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ],
                ]),
              ),
          ],
          if (events.isNotEmpty) ...[
            SectionHeader('📅 ${s.t('pf_events')}'),
            GroupList([
              for (final e in events)
                GroupRow(
                  icon: Icons.event_available_rounded,
                  color: const Color(0xFF0A84D6),
                  title: (e['title'] ?? '').toString(),
                  value: _date(e['starts_at']),
                ),
            ]),
          ],
          if (books.isNotEmpty) ...[
            SectionHeader('📚 ${s.t('pf_books')}'),
            GroupList([
              for (final b in books)
                GroupRow(
                  icon: Icons.menu_book_rounded,
                  color: const Color(0xFFD6409F),
                  title: (b['title'] ?? '').toString(),
                  value: (b['author'] ?? '').toString(),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}
