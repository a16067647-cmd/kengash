// Kanaldagi so‘rovnoma: ko‘rinish (ovoz berish, natijalar) va yaratish oynasi.
// Опрос в канале: виджет (голосование, результаты) и окно создания.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Xabar ichidagi so‘rovnoma / опрос внутри сообщения. `poll` — serverdan (o‘zgaruvchan: ovozdan keyin yangilanadi).
class PollView extends StatefulWidget {
  final Json poll;
  final bool mine;
  const PollView({super.key, required this.poll, this.mine = false});

  @override
  State<PollView> createState() => _PollViewState();
}

class _PollViewState extends State<PollView> {
  bool _busy = false;

  Json get p => widget.poll;

  Future<void> _vote(int i) async {
    final s = AppScope.read(context);
    if (_busy || p['closed'] == true) return;
    final my = [for (final x in (p['my'] as List? ?? [])) (x as num).toInt()];
    final multi = p['multi'] == true;
    final next = multi ? (my.contains(i) ? (my..remove(i)) : [...my, i]) : (my.contains(i) ? <int>[] : [i]);
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      final r = await s.api.post('/api/polls/${p['id']}/vote', {'options': next});
      if (mounted) setState(() => p.addAll(r));
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.post('/api/polls/${p['id']}/close');
      if (mounted) setState(() => p.addAll(r));
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final mine = widget.mine;
    final fg = mine ? kWhite : c.text;
    final sub = mine ? Colors.white.withAlpha(0xCC) : c.text2;
    final opts = [for (final o in (p['options'] as List? ?? [])) (o as Map).cast<String, dynamic>()];
    final my = [for (final x in (p['my'] as List? ?? [])) (x as num).toInt()];
    final voted = my.isNotEmpty || p['closed'] == true;
    final total = opts.fold<int>(0, (a, o) => a + ((o['count'] as num?)?.toInt() ?? 0));
    final voters = (p['voters'] as num?)?.toInt() ?? 0;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.poll_rounded, size: 18, color: sub),
          const SizedBox(width: 6),
          Text(s.t(p['closed'] == true ? 'poll_closed' : (p['multi'] == true ? 'poll_multi' : 'poll_label')),
              style: AppType.caption.copyWith(color: sub)),
        ]),
        const SizedBox(height: 4),
        Text((p['question'] ?? '').toString(), style: AppType.headline.copyWith(color: fg)),
        const SizedBox(height: S.x2),
        for (var i = 0; i < opts.length; i++)
          _OptionRow(
            key: ValueKey('poll-${p['id']}-$i'),
            text: (opts[i]['text'] ?? '').toString(),
            count: (opts[i]['count'] as num?)?.toInt() ?? 0,
            total: total,
            chosen: my.contains(i),
            showResult: voted,
            mine: mine,
            onTap: p['closed'] == true ? null : () => _vote(i),
          ),
        const SizedBox(height: 2),
        Row(children: [
          Expanded(
            child: Text('$voters ${s.t('poll_voters')}', style: AppType.caption.copyWith(color: sub)),
          ),
          if (p['closed'] != true && p['created_by'] == s.me?['id'])
            GestureDetector(
              key: ValueKey('poll-close-${p['id']}'),
              onTap: _close,
              child: Text(s.t('poll_close'), style: AppType.caption.copyWith(color: mine ? kWhite : c.accentText, fontWeight: w7)),
            ),
        ]),
      ]),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String text;
  final int count, total;
  final bool chosen, showResult, mine;
  final VoidCallback? onTap;
  const _OptionRow(
      {super.key,
      required this.text,
      required this.count,
      required this.total,
      required this.chosen,
      required this.showResult,
      required this.mine,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final share = total == 0 ? 0.0 : count / total;
    final fg = mine ? kWhite : c.text;
    final track = mine ? Colors.white.withAlpha(0x2E) : c.surfaceAlt;
    final fill = mine ? Colors.white.withAlpha(0x55) : c.accentSoft;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: R.all(R.sm),
          child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: track)),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedFractionallySizedBox(
                  duration: Motion.of(context, const Duration(milliseconds: 420)),
                  curve: Motion.curve,
                  widthFactor: showResult ? share : 0,
                  heightFactor: 1,
                  child: ColoredBox(color: fill),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: 10),
              child: Row(children: [
                Icon(chosen ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 18, color: chosen ? (mine ? kWhite : c.accentText) : fg.withAlpha(0x88)),
                const SizedBox(width: S.x2),
                Expanded(child: Text(text, style: AppType.subhead.copyWith(color: fg))),
                if (showResult)
                  Text('${(share * 100).round()}%', style: AppType.subhead.copyWith(color: fg, fontWeight: w7)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// So‘rovnoma yaratish oynasi / окно создания опроса. Yaratilsa true.
Future<bool> createPoll(BuildContext context, String channelId) async {
  final s = AppScope.read(context);
  final q = TextEditingController();
  final opts = [TextEditingController(), TextEditingController()];
  var multi = false;
  var ok = false;
  await showAppSheet<void>(context, builder: (ctx) {
    final c = AppScope.of(ctx).c;
    return StatefulBuilder(builder: (ctx, set) {
      return SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('poll_new'), style: AppType.title3.copyWith(color: c.text)),
          const SizedBox(height: S.x4),
          AppTextField(
              key: const ValueKey('poll-question'), controller: q, label: s.t('poll_question'), maxLength: 200, maxLines: 2),
          const SizedBox(height: S.x2),
          for (var i = 0; i < opts.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x2),
              child: AppTextField(
                key: ValueKey('poll-opt-$i'),
                controller: opts[i],
                hint: '${s.t('poll_option')} ${i + 1}',
                maxLength: 100,
              ),
            ),
          if (opts.length < 8)
            AppButton(s.t('poll_add'),
                key: const ValueKey('poll-add'),
                kind: BtnKind.ghost,
                icon: Icons.add_rounded,
                onPressed: () => set(() => opts.add(TextEditingController()))),
          Row(children: [
            Expanded(child: Text(s.t('poll_multi'), style: AppType.body.copyWith(color: c.text))),
            Switch.adaptive(value: multi, activeTrackColor: c.accent, onChanged: (v) => set(() => multi = v)),
          ]),
          const SizedBox(height: S.x3),
          AppButton(s.t('poll_create'), key: const ValueKey('poll-create'), expand: true, onPressed: () async {
            final options = [for (final o in opts) o.text.trim()].where((t) => t.isNotEmpty).toList();
            if (q.text.trim().length < 2 || options.length < 2) {
              s.toast(s.t('poll_need'));
              return;
            }
            try {
              await s.api.post('/api/channels/$channelId/polls', {'question': q.text.trim(), 'options': options, 'multi': multi});
              ok = true;
              if (ctx.mounted) Navigator.of(ctx).pop();
            } on ApiError catch (e) {
              s.toast(s.errText(e));
            }
          }),
        ]),
      );
    });
  });
  return ok;
}
