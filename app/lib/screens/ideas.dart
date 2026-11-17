// Tashabbuslar: g‘oya yozish, qo‘llab-quvvatlash, rahbar javobi; g‘oyadan tadbir.
// Инициативы: написать идею, поддержать, ответ руководителя; мероприятие из идеи.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../sound.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'calendar.dart' show CreateEventScreen;

const _statusColor = {
  'open': Color(0xFF8E8E93),
  'planned': Color(0xFF0A84D6),
  'done': Color(0xFF1F9D55),
  'declined': Color(0xFFE5484D),
};

class IdeasScreen extends StatefulWidget {
  const IdeasScreen({super.key});

  @override
  State<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends State<IdeasScreen> {
  List<Json>? _list;
  String _sort = 'top';
  String _scope = 'mine';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.get('/api/ideas', query: {'sort': _sort, 'scope': _scope});
      if (mounted) setState(() => _list = [for (final x in r['ideas'] as List) (x as Map).cast<String, dynamic>()]);
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  Future<void> _vote(Json i) async {
    final s = AppScope.read(context);
    if (i['mine'] == true) return;
    HapticFeedback.selectionClick();
    final on = i['my_vote'] != true;
    setState(() {
      i['my_vote'] = on;
      i['votes'] = (i['votes'] as int) + (on ? 1 : -1);
    });
    try {
      final r = await s.api.post('/api/ideas/${i['id']}/vote', {'vote': on});
      if (mounted) setState(() => i.addAll(r));
    } on ApiError catch (e) {
      s.toast(s.errText(e));
      _load();
    }
  }

  Future<void> _new() async {
    final s = AppScope.read(context);
    final title = TextEditingController();
    final body = TextEditingController();
    var ok = false;
    await showAppSheet<void>(context, builder: (ctx) {
      final c = AppScope.of(ctx).c;
      return SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('idea_new'), style: AppType.title3.copyWith(color: c.text)),
          const SizedBox(height: S.x1),
          Text(s.t('idea_new_sub'), style: AppType.footnote.copyWith(color: c.text2)),
          const SizedBox(height: S.x4),
          AppTextField(key: const ValueKey('idea-title'), controller: title, label: s.t('idea_title'), maxLength: 120),
          const SizedBox(height: S.x3),
          AppTextField(
              key: const ValueKey('idea-body'), controller: body, label: s.t('idea_body'), maxLength: 1000, maxLines: 5),
          const SizedBox(height: S.x4),
          AppButton(s.t('idea_send'), key: const ValueKey('idea-send'), expand: true, onPressed: () async {
            if (title.text.trim().length < 4) {
              s.toast(s.t('idea_title_hint'));
              return;
            }
            try {
              await s.api.post('/api/ideas', {'title': title.text.trim(), 'body': body.text.trim()});
              ok = true;
              if (ctx.mounted) Navigator.of(ctx).pop();
            } on ApiError catch (e) {
              s.toast(s.errText(e));
            }
          }),
        ]),
      );
    });
    if (ok) {
      Sfx.success();
      setState(() => _sort = 'new');
      _load();
    }
  }

  Future<void> _open(Json i) async {
    await showAppSheet<void>(context, builder: (ctx) => _IdeaSheet(idea: i, onChanged: _load));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final canWrite = !s.isAdmin && !s.isStaff;
    return PageShell(
      child: TabPage(
        title: s.t('ideas'),
        subtitle: s.t('ideas_sub'),
        onRefresh: _load,
        trailing: canWrite
            ? AppIconButton(Icons.add_rounded, key: const ValueKey('idea-add'), tooltip: s.t('idea_new'), color: c.accentText, onPressed: _new)
            : null,
        children: [
          Row(children: [
            Expanded(
              child: Segmented<String>(
                key: const ValueKey('idea-sort'),
                values: const ['top', 'new'],
                labels: [s.t('idea_top'), s.t('idea_fresh')],
                value: _sort,
                onChanged: (v) {
                  setState(() => _sort = v);
                  _load();
                },
              ),
            ),
            const SizedBox(width: S.x2),
            Expanded(
              child: Segmented<String>(
                key: const ValueKey('idea-scope'),
                values: const ['mine', 'all'],
                labels: [s.t('idea_mine'), s.t('all')],
                value: _scope,
                onChanged: (v) {
                  setState(() => _scope = v);
                  _load();
                },
              ),
            ),
          ]),
          if (_list == null)
            const SkeletonRows(count: 4)
          else if (_list!.isEmpty)
            EmptyState(
                icon: Icons.lightbulb_rounded,
                title: s.t('idea_none'),
                actionLabel: canWrite ? s.t('idea_new') : null,
                onAction: canWrite ? _new : null)
          else
            for (final i in _list!) _IdeaCard(idea: i, onVote: () => _vote(i), onTap: () => _open(i)),
        ],
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  final Json idea;
  final VoidCallback onVote, onTap;
  const _IdeaCard({required this.idea, required this.onVote, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final i = idea;
    final voted = i['my_vote'] == true;
    final status = (i['status'] ?? 'open').toString();
    final author = (i['author'] as Map?)?.cast<String, dynamic>();
    return AppCard(
      key: ValueKey('idea-${i['id']}'),
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ovoz tugmasi / кнопка голоса
        GestureDetector(
          key: ValueKey('idea-vote-${i['id']}'),
          onTap: onVote,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: S.x2),
            decoration: BoxDecoration(
              color: voted ? c.accent : c.surfaceAlt,
              borderRadius: R.all(R.md),
            ),
            child: Column(children: [
              Icon(Icons.arrow_upward_rounded, size: 20, color: voted ? Colors.white : c.text2),
              Text('${i['votes']}', style: AppType.headline.copyWith(color: voted ? Colors.white : c.text)),
            ]),
          ),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((i['title'] ?? '').toString(), style: AppType.headline.copyWith(color: c.text)),
            if ((i['body'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text((i['body'] ?? '').toString(),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.subhead.copyWith(color: c.text2)),
              ),
            const SizedBox(height: S.x2),
            Row(children: [
              if (status != 'open') ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: _statusColor[status]!.withValues(alpha: 0.14), borderRadius: R.all(R.pill)),
                  child: Text(s.t('idea_st_$status'),
                      style: AppType.caption.copyWith(color: _statusColor[status])),
                ),
                const SizedBox(width: S.x2),
              ],
              Expanded(
                child: Text(
                    [(author?['name'] ?? '').toString(), s.placeLine(author?['place'] as Json?)]
                        .where((x) => x.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: c.text3)),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _IdeaSheet extends StatefulWidget {
  final Json idea;
  final VoidCallback onChanged;
  const _IdeaSheet({required this.idea, required this.onChanged});

  @override
  State<_IdeaSheet> createState() => _IdeaSheetState();
}

class _IdeaSheetState extends State<_IdeaSheet> {
  late final _reply = TextEditingController(text: (widget.idea['reply'] ?? '').toString());

  Future<void> _answer(String status) async {
    final s = AppScope.read(context);
    try {
      final r = await s.api.post('/api/ideas/${widget.idea['id']}/answer', {'status': status, 'reply': _reply.text.trim()});
      widget.idea.addAll(r);
      widget.onChanged();
      s.toast(s.t('saved'), icon: Icons.check_circle_rounded);
      if (mounted) Navigator.of(context).pop();
    } on ApiError catch (e) {
      s.toast(s.errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.c;
    final i = widget.idea;
    final by = (i['replied_by'] as Map?)?.cast<String, dynamic>();
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text((i['title'] ?? '').toString(), style: AppType.title3.copyWith(color: c.text)),
        const SizedBox(height: S.x1),
        Text('${(i['author'] as Map?)?['name'] ?? ''} · ${i['votes']} ${s.t('idea_supporters')}',
            style: AppType.footnote.copyWith(color: c.text2)),
        if ((i['body'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: S.x3),
          SelectableText((i['body'] ?? '').toString(), style: AppType.body.copyWith(color: c.text)),
        ],
        if ((i['reply'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: S.x4),
          AppCard(
            kind: CardKind.tinted,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.t('idea_st_${i['status']}')} · ${by?['title']?.toString().isNotEmpty == true ? by!['title'] : by?['name'] ?? ''}',
                  style: AppType.footnote.copyWith(color: c.accentText)),
              const SizedBox(height: S.x1),
              Text((i['reply'] ?? '').toString(), style: AppType.body.copyWith(color: c.text)),
            ]),
          ),
        ],
        if (i['can_answer'] == true) ...[
          const SizedBox(height: S.x4),
          AppTextField(key: const ValueKey('idea-reply'), controller: _reply, label: s.t('idea_reply'), maxLength: 1000, maxLines: 3),
          const SizedBox(height: S.x3),
          Row(children: [
            Expanded(
                child: AppButton(s.t('idea_st_planned'),
                    key: const ValueKey('idea-planned'), height: 46, onPressed: () => _answer('planned'))),
            const SizedBox(width: S.x2),
            Expanded(
                child: AppButton(s.t('idea_st_done'),
                    key: const ValueKey('idea-done'), kind: BtnKind.success, height: 46, onPressed: () => _answer('done'))),
          ]),
          const SizedBox(height: S.x2),
          Row(children: [
            if (s.canGive)
              Expanded(
                child: AppButton(s.t('idea_to_event'),
                    key: const ValueKey('idea-event'),
                    kind: BtnKind.secondary,
                    icon: Icons.event_rounded,
                    height: 46,
                    onPressed: () async {
                      final ok = await Navigator.of(context).push<bool>(AppRoute(
                          builder: (_) => CreateEventScreen(
                              initialTitle: (i['title'] ?? '').toString(), initialDescription: (i['body'] ?? '').toString())));
                      if (ok == true) await _answer('planned');
                    }),
              ),
            if (s.canGive) const SizedBox(width: S.x2),
            Expanded(
                child: AppButton(s.t('idea_st_declined'),
                    key: const ValueKey('idea-declined'), kind: BtnKind.ghost, height: 46, onPressed: () => _answer('declined'))),
          ]),
        ],
        if (i['mine'] == true) ...[
          const SizedBox(height: S.x3),
          AppButton(s.t('delete'), kind: BtnKind.ghost, expand: true, onPressed: () async {
            try {
              await s.api.post('/api/ideas/${i['id']}/delete');
              widget.onChanged();
              if (context.mounted) Navigator.of(context).pop();
            } on ApiError catch (e) {
              s.toast(s.errText(e));
            }
          }),
        ],
      ]),
    );
  }
}
