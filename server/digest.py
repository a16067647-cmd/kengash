"""Dushanba dayjesti: har dushanba ertalab (Toshkent, 8:00 dan keyin) bot har bir koordinator, maslahatchi va
o‘quvchiga bitta xabar yuboradi: shu haftadagi vazifalar, tadbirlar va reytingdagi o‘rni (o‘tgan haftaga nisbatan).
Hech narsa bo‘lmasa (vazifa, tadbir, reyting yo‘q) — yuborilmaydi. Telegram xabarnomasi o‘chirilganlarga — yo‘q.

Дайджест по понедельникам: каждое утро понедельника (Ташкент, после 8:00) бот присылает одно сообщение:
задачи и мероприятия на неделю и место в рейтинге (по сравнению с прошлой неделей). Если нечего сказать — не шлём.
"""
import datetime
import html

import db
from rating import TZ, rank_of

WEEKDAYS = ["Dush", "Sesh", "Chor", "Pay", "Jum", "Shan", "Yak"]


def _when(ts):
    d = datetime.datetime.fromtimestamp(ts, TZ)
    return f"{WEEKDAYS[d.weekday()]} {d.strftime('%H:%M')}"


def build(c, u, now, cache=None):
    """Bitta odam uchun matn (yoki None) / текст для одного человека (или None)."""
    week_end = now + 7 * 86400
    tasks = c.q("SELECT t.* FROM task_assignees a JOIN tasks t ON t.id=a.task_id WHERE a.user_id=? "
                "AND a.status IN ('new','returned') AND t.deadline<? ORDER BY t.deadline LIMIT 20", (u["id"], week_end))
    events = c.q("SELECT e.* FROM event_guests g JOIN events e ON e.id=g.event_id WHERE g.user_id=? AND g.rsvp<>'no' "
                 "AND e.starts_at>=? AND e.starts_at<? ORDER BY e.starts_at LIMIT 10", (u["id"], now, week_end))
    rank, score, total = rank_of(c, u, cache)
    if not tasks and not events and not rank:
        return None, rank
    first = u["name"].split(" ")[-1] if u["name"] else ""
    lines = [f"☀️ <b>Xayrli tong, {html.escape(first)}!</b> Bu hafta:", ""]
    if tasks:
        late = [t for t in tasks if t["deadline"] < now]
        lines.append(f"📋 <b>Vazifalar: {len(tasks)}</b>" + (f" (muddati o‘tgan: {len(late)})" if late else ""))
        lines += [f"   • {html.escape(t['title'][:60])} — {_when(t['deadline'])}" for t in tasks[:3]]
    if events:
        lines.append(f"📅 <b>Tadbirlar: {len(events)}</b>")
        lines += [f"   • {html.escape(e['title'][:60])} — {_when(e['starts_at'])}" for e in events[:3]]
    if rank:
        prev = u.get("last_rank") or 0
        move = ""
        if prev and prev != rank:
            move = f" ({'↑' if rank < prev else '↓'}{abs(prev - rank)})"
        lines.append(f"🏆 <b>Reyting: {rank}-o‘rin</b> / {total}{move} · {score} ball")
    lines += ["", "Ilovani ochib, haftani boshlang! 💪 / Откройте приложение и начните неделю!"]
    return "\n".join(lines), rank


def send_weekly(now=None):
    """Dushanba 8:00 dan keyin, har odamga haftada bir marta / по понедельникам после 8:00, раз в неделю."""
    import push
    import telegram
    now = now or db.now()
    d = datetime.datetime.fromtimestamp(now, TZ)
    if d.weekday() != 0 or d.hour < 8:
        return 0
    week = d.strftime("%G-W%V")
    out, cache = [], {}
    with db.tx() as c:
        rows = c.q("SELECT * FROM users WHERE status='active' AND tg_id IS NOT NULL AND notify_tg=1 "
                   "AND kind IN ('coordinator','maslahatchi','student')")
        for u in rows:
            if c.one("SELECT k FROM sent_once WHERE k=?", (f"digest:{week}:{u['id']}",)):
                continue
            text, rank = build(c, u, now, cache)
            push.once(c, f"digest:{week}:{u['id']}")
            if rank:
                c.x("UPDATE users SET last_rank=? WHERE id=?", (rank, u["id"]))
            if text:
                out.append((u["tg_id"], text))
    import time
    for chat, t in out:
        telegram.send(chat, t, telegram.back_button())
        time.sleep(0.05)  # Telegram chegarasi (~30/s) / лимит Telegram
    return len(out)
