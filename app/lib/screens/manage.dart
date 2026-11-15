// Uzoq bosish menyusi va tahrirlash oynalari (kanal, vazifa, tadbir).
// Меню долгого нажатия и окна правки (канал, задача, мероприятие).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'channels.dart' show ModePicker;
import 'directory.dart' show confirmSheet;
import 'tasks.dart' show WhenPicker, fromTs, toTs;

/// Bitta amal / одно действие.
class SheetAction {
  final String id;
  final IconData icon;
  final String label;
  final bool danger;
  final Future<void> Function() run;
  const SheetAction(this.id, this.icon, this.label, this.run, {this.danger = false});
}

/// Uzoq bosilganda chiqadigan menyu: sarlavha va 2–4 ta katta qator.
/// Меню по долгому нажатию: заголовок и 2–4 крупные строки.
Future<void> showActions(BuildContext context, String title, List<SheetAction> actions) {
  return showAppSheet<void>(context, builder: (ctx) {
    final c = AppScope.of(ctx).c;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.title3.copyWith(color: c.text)),
      const SizedBox(height: S.x3),
      GroupList([
        for (final a in actions)
          GroupRow(
            key: ValueKey('act-${a.id}'),
            icon: a.icon,
            color: a.danger ? c.danger : c.accent,
            title: a.label,
            onTap: () async {
              Navigator.of(ctx).pop();
              await a.run();
            },
          ),
      ]),
    ]);
  });
}

// ============================================================ kanal / канал
/// Kanal uchun uzoq bosish menyusi (faqat yaratilgan kanallar; avtomatiklarni o‘chirib bo‘lmaydi).
/// Меню канала (только созданные каналы; автоматические удалить нельзя).
Future<void> channelActions(BuildContext context, Json ch) async {
  final s = AppScope.read(context);
  if (ch['kind'] != 'custom') {
    s.toast(s.t('ch_auto_locked'));
    return;
  }
  final mod = ch['can_manage'] == true || ch['is_mod'] == true || s.isAdmin;
  final canDelete = s.isAdmin || ch['role'] == 'owner';
  if (!mod && !canDelete) return;
  final cid = ch['id'] as String;
  await showActions(context, s.pick(ch, 'title'), [
    if (mod) SheetAction('edit', Icons.edit_rounded, s.t('ch_edit'), () => editChannel(context, ch)),
    if (mod) SheetAction('photo', Icons.add_a_photo_rounded, s.t('ch_photo'), () => pickChannelPhoto(context, cid)),
    if (mod && (ch['photo'] ?? '').toString().isNotEmpty)
      SheetAction('photo-remove', Icons.hide_image_rounded, s.t('ch_photo_remove'), () async {
        try {
          await s.api.post('/api/channels/$cid/avatar', {'remove': true});
          await s.chat.loadChannels();
        } on ApiError catch (e) {
          s.toast(s.errText(e));
        }
      }),
    if (canDelete)
      SheetAction('delete', Icons.delete_forever_rounded, s.t('ch_delete'), () async {
        if (!await confirmSheet(context, s.t('ch_delete_q'), s.t('ch_delete'))) return;
        try {
          await s.api.post('/api/channels/$cid/delete');
          await s.chat.loadChannels();
          s.toast(s.t('deleted'), icon: Icons.check_circle_rounded);
        } on ApiError catch (e) {
          s.toast(s.errText(e));
        }
      }, danger: true),
  ]);
}

Future<void> pickChannelPhoto(BuildContext context, String cid) async {
  final s = AppScope.read(context);
  final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200, imageQuality: 88);
  if (f == null) return;
  try {
    await s.api.post('/api/channels/$cid/avatar', {'data': base64Encode(await f.readAsBytes())}, const Duration(seconds: 60));
    await s.chat.loadChannels();
    s.toast(s.t('saved'), icon: Icons.check_circle_rounded);
  } on ApiError catch (e) {
    s.toast(s.errText(e));
  }
}

/// Nom, tavsif, rejim / название, описание, режим.
Future<void> editChannel(BuildContext context, Json ch, {VoidCallback? onDone}) async {
  final s = AppScope.read(context);
  final title = TextEditingController(text: s.pick(ch, 'title'));
  final desc = TextEditingController(text: (ch['description'] ?? '').toString());
  var mode = ch['mode'] as String? ?? 'group';
  await showAppSheet<void>(context, builder: (ctx) {
    final c = AppScope.of(ctx).c;
    return StatefulBuilder(builder: (ctx, set) {
      return SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('ch_edit'), style: AppType.title3.copyWith(color: c.text)),
          const SizedBox(height: S.x4),
          AppTextField(
              key: const ValueKey('edit-title'),
              controller: title,
              label: s.t('ch_name'),
              icon: Icons.title_rounded,
              maxLength: 60),
          const SizedBox(height: S.x3),
          AppTextField(controller: desc, label: s.t('ch_desc'), icon: Icons.notes_rounded, maxLength: 300, maxLines: 3),
          const SizedBox(height: S.x4),
          ModePicker(value: mode, onChanged: (v) => set(() => mode = v)),
          const SizedBox(height: S.x4),
          AppButton(s.t('save'), key: const ValueKey('edit-save'), expand: true, onPressed: () async {
            try {
              await s.api.post('/api/channels/${ch['id']}', {'title': title.text.trim(), 'description': desc.text.trim(), 'mode': mode});
              if (ctx.mounted) Navigator.of(ctx).pop();
              await s.chat.loadChannels();
              onDone?.call();
            } on ApiError catch (e) {
              s.toast(s.errText(e));
            }
          }),
        ]),
      );
    });
  });
}

// ============================================================ vazifa va tadbir / задача и мероприятие
/// Vazifa yoki tadbir: nom, tavsif, vaqt (va joy). Xatolarni tuzatish uchun.
/// Задача или мероприятие: название, описание, время (и место). Для исправления ошибок.
Future<bool> editPlanItem(BuildContext context, Json item, {required bool event}) async {
  final s = AppScope.read(context);
  final title = TextEditingController(text: (item['title'] ?? '').toString());
  final desc = TextEditingController(text: (item['description'] ?? '').toString());
  final place = TextEditingController(text: (item['place'] ?? '').toString());
  DateTime when = fromTs((event ? item['starts_at'] : item['deadline']) as num);
  var saved = false;
  await showAppSheet<void>(context, builder: (ctx) {
    final c = AppScope.of(ctx).c;
    return StatefulBuilder(builder: (ctx, set) {
      return SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t(event ? 'event_edit' : 'task_edit'), style: AppType.title3.copyWith(color: c.text)),
          const SizedBox(height: S.x4),
          AppTextField(key: const ValueKey('edit-title'), controller: title, label: s.t('task_what'), maxLength: 120),
          const SizedBox(height: S.x3),
          AppTextField(controller: desc, label: s.t('task_details'), maxLength: 2000, maxLines: 4),
          if (event) ...[
            const SizedBox(height: S.x3),
            AppTextField(controller: place, label: s.t('event_place'), icon: Icons.place_rounded, maxLength: 200),
          ],
          const SizedBox(height: S.x3),
          Text(s.t(event ? 'event_when' : 'deadline'), style: AppType.footnote.copyWith(color: c.text2)),
          const SizedBox(height: S.x2),
          WhenPicker(value: when, onChanged: (v) => set(() => when = v)),
          const SizedBox(height: S.x4),
          AppButton(s.t('save'), key: const ValueKey('edit-save'), expand: true, onPressed: () async {
            try {
              final id = item['id'];
              await s.api.post(
                  event ? '/api/events/$id/edit' : '/api/tasks/$id/edit',
                  {
                    'title': title.text.trim(),
                    'description': desc.text.trim(),
                    if (event) 'place': place.text.trim(),
                    if (event) 'starts_at': toTs(when) else 'deadline': toTs(when),
                    if (!event) 'photo_required': item['photo_required'] == true,
                  });
              saved = true;
              if (ctx.mounted) Navigator.of(ctx).pop();
              s.toast(s.t('saved'), icon: Icons.check_circle_rounded);
            } on ApiError catch (e) {
              s.toast(s.errText(e));
            }
          }),
        ]),
      );
    });
  });
  return saved;
}

/// Vazifa/tadbir menyusi: tahrirlash yoki o‘chirish / меню задачи/мероприятия.
Future<void> planActions(BuildContext context, Json item, {required bool event, VoidCallback? onChanged}) async {
  final s = AppScope.read(context);
  final mine = event ? item['is_organizer'] == true : (item['is_giver'] == true || s.isAdmin);
  if (!mine) return;
  final id = item['id'];
  await showActions(context, (item['title'] ?? '').toString(), [
    SheetAction('edit', Icons.edit_rounded, s.t(event ? 'event_edit' : 'task_edit'), () async {
      if (await editPlanItem(context, item, event: event)) onChanged?.call();
    }),
    SheetAction('delete', Icons.delete_rounded, s.t(event ? 'event_cancel' : 'task_delete'), () async {
      if (!await confirmSheet(context, s.t(event ? 'event_cancel_q' : 'task_delete_q'), s.t('delete'))) return;
      try {
        await s.api.post(event ? '/api/events/$id/delete' : '/api/tasks/$id/delete');
        onChanged?.call();
      } on ApiError catch (e) {
        s.toast(s.errText(e));
      }
    }, danger: true),
  ]);
}
