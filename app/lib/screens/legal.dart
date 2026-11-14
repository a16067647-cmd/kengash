import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../brand.dart';
import '../config.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Huquqiy matnlar (assets/legal.json — sayt bilan bir manba).
/// Правовые тексты (assets/legal.json — общий источник с сайтом).
class Legal {
  static Json? _data;

  static Future<Json> load() async {
    return _data ??= jsonDecode(await rootBundle.loadString('assets/legal.json')) as Json;
  }

  static String webPath(String page, String lang) => '$kWebUrl$page${lang == 'ru' ? '-ru' : ''}.html';
}

class LegalScreen extends StatelessWidget {
  final String page;
  const LegalScreen({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    return PageShell(
      child: FutureBuilder<Json>(
        future: Legal.load(),
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) return const Center(child: SkeletonRows(count: 6));
          final title = ((d['titles'] as Map)[page] as Map)[s.lang] as String;
          final sections = ((d['pages'] as Map)[page] as Map)[s.lang] as List;
          final contact = d['contact'] as String;
          final updated = '${s.t('legal_updated')}: ${(d['updated'] as Map)[s.lang]}';
          return TabPage(
            title: title,
            subtitle: updated,
            children: [
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, sec) in sections.indexed) ...[
                    if (i > 0) const SizedBox(height: S.x5),
                    Text(sec[0] as String, style: AppType.title3.copyWith(color: c.text)),
                    const SizedBox(height: S.x2),
                    for (final p in (sec[1] as List).cast<String>()) _para(context, p.replaceAll('{CONTACT}', contact), d),
                  ],
                ]),
              ),
              Pressable(
                onTap: () => s.copy(Legal.webPath(page, s.lang)),
                child: Text('${s.t('public_link')}: ${Legal.webPath(page, s.lang)}',
                    textAlign: TextAlign.center, style: AppType.footnote.copyWith(color: c.accentText)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _para(BuildContext context, String p, Json d) {
    final s = AppScope.of(context);
    final c = s.c;
    switch (p) {
      case '[ok_logo]':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: S.x3),
          child: Align(alignment: Alignment.centerLeft, child: KengashLockup(height: 48)),
        );
      case '[kelajak]':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: R.all(18),
              child: Image.asset('assets/team/kelajak.jpg', width: 180, height: 180, fit: BoxFit.cover),
            ),
          ),
        );
      case '[team]':
        final team = (d['team'] as List).cast<List>();
        return LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth > 520 ? 3 : 2;
          return gridOf([
            for (final m in team)
              Column(children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: R.all(18),
                    child: Image.asset('assets/team/${m[0]}.jpg', fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: S.x2),
                Text(m[1] as String, textAlign: TextAlign.center, style: AppType.headline.copyWith(color: c.text)),
                Text((s.lang == 'ru' ? m[3] : m[2]) as String, style: AppType.footnote.copyWith(color: c.text2)),
              ]),
          ], cols);
        });
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x2),
      child: SelectableText(p, style: AppType.body.copyWith(color: c.text)),
    );
  }
}

/// Pastdagi kichik havolalar / маленькие ссылки внизу.
class LegalLinks extends StatelessWidget {
  final List<String> pages;
  final bool inline;
  const LegalLinks({super.key, required this.pages, this.inline = false});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final names = {'about': s.t('about'), 'privacy': s.t('privacy'), 'terms': s.t('terms'), 'cookies': s.t('cookies')};
    final items = <Widget>[];
    for (final (i, p) in pages.indexed) {
      if (i > 0) items.add(Text(inline ? ', ' : '  ·  ', style: AppType.footnote.copyWith(color: c.text3)));
      items.add(GestureDetector(
        key: ValueKey('legal-$p'),
        onTap: () => Navigator.of(context).push(AppRoute(builder: (_) => LegalScreen(page: p))),
        child: Text(names[p]!, style: (inline ? AppType.subhead : AppType.footnote).copyWith(color: c.accentText)),
      ));
    }
    return Wrap(alignment: inline ? WrapAlignment.start : WrapAlignment.center, children: items);
  }
}
