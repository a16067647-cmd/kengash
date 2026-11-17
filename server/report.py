"""Oylik hisobot: har oyning 1-kuni (Toshkent, 9:00 dan keyin) bot rahbarlarga (vakolati «view» bo‘lgan xodimlar
va admin) o‘tgan oy bo‘yicha bir sahifalik xulosa yuboradi. Ilovada ham ko‘rish va Telegram’ga yuborish mumkin.

Ежемесячный отчёт: 1-го числа (Ташкент, после 9:00) бот присылает руководителям (сотрудники с полномочием «view»
и админ) одностраничную сводку за прошлый месяц. В приложении можно посмотреть и отправить себе в Telegram.
"""
import datetime
import html
from typing import Optional

from fastapi import APIRouter, Header, Request

import app as core
import db
import model
from admin_tools import area_sql
from rating import TZ

router = APIRouter()
err = core.err

MONTHS_UZ = ["yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avgust", "sentabr", "oktabr", "noyabr", "dekabr"]
MONTHS_RU = ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь",
             "декабрь"]


def month_range(key=None, now=None):
    """'2026-10' → (boshlanish, tugash, '2026-10'); bo‘sh — o‘tgan oy / пусто — прошлый месяц."""
    if key:
        try:
            y, m = (int(x) for x in key.split("-"))
            start = datetime.datetime(y, m, 1, tzinfo=TZ)
        except Exception:
            err(400, "bad_month")
    else:
        d = datetime.datetime.fromtimestamp(now or db.now(), TZ)
        first = datetime.datetime(d.year, d.month, 1, tzinfo=TZ)
        start = (first - datetime.timedelta(days=1)).replace(day=1)
    end = (start + datetime.timedelta(days=32)).replace(day=1)
    return int(start.timestamp()), int(end.timestamp()), f"{start.year}-{start.month:02d}"


def build(c, viewer, start, end):
    """Hudud bo‘yicha raqamlar / цифры по территории (admin — butun viloyat)."""
    area, ap = area_sql(viewer)
    # koordinator va maslahatchilar (admin uchun ham) / координаторы и маслахатчи (и для админа)
    scope, sp = f"{area} AND u.kind IN ('coordinator','maslahatchi')", ap
    people = c.one(f"SELECT COUNT(*) AS n FROM users u WHERE status='active' AND {scope}", sp)["n"]
    students = c.one(f"SELECT COUNT(*) AS n FROM users u WHERE status='active' AND kind='student' AND {area}", ap)["n"]
    joined = c.one(f"SELECT COUNT(*) AS n FROM users u WHERE status='active' AND created_at>=? AND created_at<? "
                   f"AND kind IN ('coordinator','maslahatchi','student') AND {area}", [start, end] + ap)["n"]
    tasks = c.one(f"SELECT COUNT(*) AS n, SUM(CASE WHEN a.status IN ('submitted','accepted') THEN 1 ELSE 0 END) AS done, "
                  f"SUM(CASE WHEN a.status IN ('new','returned') AND t.deadline<? THEN 1 ELSE 0 END) AS late "
                  f"FROM task_assignees a JOIN tasks t ON t.id=a.task_id JOIN users u ON u.id=a.user_id "
                  f"WHERE t.created_at>=? AND t.created_at<? AND {scope}", [min(end, db.now()), start, end] + sp)
    ev = c.one(f"SELECT COUNT(DISTINCT e.id) AS events, COUNT(*) AS invited, "
               f"SUM(CASE WHEN g.checked_at>0 OR EXISTS (SELECT 1 FROM points p WHERE p.kind='event' AND p.ref_id=e.id "
               f"AND p.user_id=g.user_id AND p.value>0) THEN 1 ELSE 0 END) AS came "
               f"FROM events e JOIN event_guests g ON g.event_id=e.id JOIN users u ON u.id=g.user_id "
               f"WHERE e.starts_at>=? AND e.starts_at<? AND {scope}", [start, end] + sp)
    top = c.q(f"SELECT u.*, SUM(p.value) AS score FROM points p JOIN users u ON u.id=p.user_id "
              f"WHERE p.created_at>=? AND p.created_at<? AND {scope} GROUP BY u.id ORDER BY score DESC, u.name LIMIT 5",
              [start, end] + sp)
    quiet = c.q(f"SELECT * FROM users u WHERE status='active' AND last_seen<? AND {scope} ORDER BY last_seen LIMIT 5",
                [db.now() - 14 * 86400] + sp)
    quiet_n = c.one(f"SELECT COUNT(*) AS n FROM users u WHERE status='active' AND last_seen<? AND {scope}",
                    [db.now() - 14 * 86400] + sp)["n"]
    n, done = tasks["n"] or 0, tasks["done"] or 0
    inv, came = ev["invited"] or 0, ev["came"] or 0
    return {
        "people": people, "students": students, "joined": joined,
        "tasks": n, "tasks_done": done, "tasks_pct": round(done * 100 / n) if n else None, "tasks_late": tasks["late"] or 0,
        "events": ev["events"] or 0, "invited": inv, "came": came, "came_pct": round(came * 100 / inv) if inv else None,
        "top": [core.public_user(c, u, viewer) | {"score": int(u["score"])} for u in top if (u["score"] or 0) > 0],
        "quiet": [core.public_user(c, u, viewer) | {"last_seen": u["last_seen"]} for u in quiet], "quiet_count": quiet_n,
    }


def area_label(c, u):
    if u["role"] == "admin":
        return "Andijon viloyati"
    p = core.place_info(c, u["level"], u["place_id"])
    return p["name_uz"] if p else ""


def text(c, u, r, key):
    """Telegram uchun bir sahifa (HTML) / одна страница для Telegram (HTML)."""
    y, m = (int(x) for x in key.split("-"))
    pct = lambda v: "—" if v is None else f"{v}%"  # noqa: E731
    lines = [f"📊 <b>Oylik hisobot · {MONTHS_UZ[m - 1].capitalize()} {y}</b>",
             f"<i>Отчёт за {MONTHS_RU[m - 1]} {y}</i> — {html.escape(area_label(c, u))}", "",
             f"👥 Koordinator va maslahatchilar: <b>{r['people']}</b> · o‘quvchilar: <b>{r['students']}</b>"
             + (f" · yangi: +{r['joined']}" if r["joined"] else ""),
             f"📋 Vazifalar: <b>{r['tasks']}</b> · bajarildi <b>{pct(r['tasks_pct'])}</b>"
             + (f" · muddati o‘tgan: {r['tasks_late']}" if r["tasks_late"] else ""),
             f"📅 Tadbirlar: <b>{r['events']}</b> · keldi <b>{pct(r['came_pct'])}</b> ({r['came']}/{r['invited']})"]
    if r["top"]:
        lines += ["", "🏆 <b>Eng faol / Самые активные</b>"]
        medals = ["🥇", "🥈", "🥉", "4.", "5."]
        lines += [f"{medals[i]} {html.escape(p['name'])} — +{p['score']}" for i, p in enumerate(r["top"])]
    if r["quiet_count"]:
        lines += ["", f"😴 <b>2 haftadan beri kirmagan: {r['quiet_count']}</b>"]
        lines += [f"• {html.escape(p['name'])}" for p in r["quiet"]]
    return "\n".join(lines)


def recipients(c):
    rows = c.q("SELECT * FROM users WHERE status='active' AND tg_id IS NOT NULL AND (role='admin' OR kind='staff')")
    return [u for u in rows if model.has_power(u, "view")]


def send_monthly(now=None):
    """Oy boshida bir marta (har odamga) / раз в начале месяца (каждому)."""
    import push
    import telegram
    now = now or db.now()
    d = datetime.datetime.fromtimestamp(now, TZ)
    if d.day != 1 or d.hour < 9:
        return 0
    start, end, key = month_range(None, now)
    out = []
    with db.tx() as c:
        for u in recipients(c):
            if not push.once(c, f"report:{key}:{u['id']}"):
                continue
            out.append((u["tg_id"], text(c, u, build(c, u, start, end), key)))
    for chat, t in out:
        telegram.send(chat, t, telegram.back_button())
    return len(out)


# ------------------------------------------------------------------ API
def _viewer(c, authorization):
    u = core.current_user(c, authorization)
    if not model.has_power(u, "view"):
        err(403, "forbidden")
    return u


@router.get("/api/report")
def report(month: str = "", authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = _viewer(c, authorization)
        start, end, key = month_range(month or None)
        return {"month": key, "area": area_label(c, u), **build(c, u, start, end)}


@router.post("/api/report/send")
async def report_send(request: Request, authorization: Optional[str] = Header(default=None)):
    """Hisobotni o‘zimning Telegram’imga yuborish / отправить отчёт себе в Telegram."""
    import telegram
    b = await request.json()
    with db.tx() as c:
        u = _viewer(c, authorization)
        if not u.get("tg_id"):
            err(400, "no_telegram")
        if not core.rate_ok("report:" + u["id"], 5, 3600):
            err(429, "too_many")
        start, end, key = month_range(str(b.get("month") or "") or None)
        t = text(c, u, build(c, u, start, end), key)
        chat = u["tg_id"]
    telegram.send(chat, t, telegram.back_button())
    return {"ok": True}
