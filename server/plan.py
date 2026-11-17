"""Vazifalar, tadbirlar, «Bugun» va push ro‘yxatdan o‘tkazish.
Задачи, мероприятия, «Сегодня» и регистрация push.

Kim beradi / кто выдаёт: tuman va viloyat koordinatorlari, admin — faqat o‘zidan pastdagilarga.
Hisobotni ko‘radi / отчёт видят: vazifa bergan, admin va bajaruvchidan yuqoridagilar.
"""
import asyncio
import base64
import json
import logging
import threading
import time
from typing import Optional

from fastapi import APIRouter, Header, Request

import app as core
import channels
import db
import push
import storage
from model import is_above

log = logging.getLogger("kengash.plan")
router = APIRouter()
err = core.err
clean = core.clean
MAX_REPORT_PHOTOS = 6
STATUSES = ("new", "submitted", "accepted", "returned")


def _deadline_ok(v):
    try:
        v = int(v)
    except Exception:
        err(400, "bad_deadline")
    if v < db.now() - 3600 or v > db.now() + 366 * 86400:
        err(400, "bad_deadline")
    return v


def _mini(c, uid):
    u = c.one("SELECT * FROM users WHERE id=?", (uid,))
    return u and {"id": u["id"], "name": u["name"], "photo": core.photo_url(u), "direction": u["direction"],
                  "level": u["level"], "place": core.place_info(c, u["level"], u["place_id"]), "tg_username": u["tg_username"]}


def _sign_photos(paths):
    if not paths or not storage.enabled():
        return {}
    try:
        return storage.sign(paths)
    except Exception:
        return {}


# ------------------------------------------------------------------ vazifalar / задачи
def task_json(c, t, viewer, mine=None):
    counts = {s: 0 for s in STATUSES}
    for r in c.q("SELECT status FROM task_assignees WHERE task_id=?", (t["id"],)):
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    total = sum(counts.values())
    out = {"id": t["id"], "title": t["title"], "description": t["description"], "deadline": t["deadline"],
           "photo_required": bool(t["photo_required"]), "created_at": t["created_at"],
           "by": _mini(c, t["created_by"]), "total": total, "counts": counts,
           "done": counts["accepted"] + counts["submitted"], "is_giver": t["created_by"] == viewer["id"],
           "overdue": t["deadline"] < db.now()}
    if mine:
        out["my"] = {"status": mine["status"], "comment": mine["comment"], "review_note": mine["review_note"],
                     "photos": json.loads(mine["photos"] or "[]"), "submitted_at": mine["submitted_at"]}
    return out


def can_review(c, viewer, task, assignee_user):
    if viewer["role"] == "admin" or task["created_by"] == viewer["id"]:
        return True
    return bool(assignee_user and assignee_user["level"] and
                is_above(c, viewer, assignee_user["level"], assignee_user["place_id"], assignee_user["direction"]))


@router.get("/api/tasks")
def tasks_list(box: str = "mine", authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        if box == "given":
            rows = c.q("SELECT * FROM tasks WHERE created_by=? ORDER BY deadline DESC LIMIT 200", (u["id"],))
            return {"tasks": [task_json(c, t, u) for t in rows]}
        rows = c.q("SELECT t.*, a.status AS a_status FROM tasks t JOIN task_assignees a ON a.task_id=t.id "
                   "WHERE a.user_id=? ORDER BY CASE WHEN a.status IN ('new','returned') THEN 0 ELSE 1 END, t.deadline "
                   "LIMIT 200", (u["id"],))
        out = []
        for t in rows:
            mine = c.one("SELECT * FROM task_assignees WHERE task_id=? AND user_id=?", (t["id"], u["id"]))
            out.append(task_json(c, t, u, mine))
        return {"tasks": out, "can_give": core.can_give(u)}


@router.post("/api/tasks")
async def tasks_create(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    title = clean(b.get("title"), 120)
    if len(title) < 2:
        err(400, "bad_title")
    deadline = _deadline_ok(b.get("deadline"))
    with db.tx() as c:
        u = core.current_user(c, authorization)
        if not core.can_give(u):
            err(403, "forbidden")
        if not core.rate_ok("task:" + u["id"], 30, 3600):
            err(429, "too_many")
        targets = channels.resolve_audience(c, u, b.get("audience"), b.get("user_ids"), peers=False)
        if not targets:
            err(400, "no_people")
        tid = core.new_id()
        c.x("INSERT INTO tasks (id, created_by, title, description, deadline, photo_required, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (tid, u["id"], title, str(b.get("description") or "").strip()[:2000], deadline,
             1 if b.get("photo_required", True) else 0, db.now()))
        for t in targets:
            c.x("INSERT INTO task_assignees (task_id, user_id) VALUES (?, ?)", (tid, t["id"]))
        out = task_json(c, c.one("SELECT * FROM tasks WHERE id=?", (tid,)), u)
    push.send([t["id"] for t in targets], f"📋 {title}", f"Yangi vazifa · Новая задача — {u['name']}", {"type": "task", "id": tid})
    return out


@router.get("/api/tasks/{tid}")
def task_get(tid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        t = c.one("SELECT * FROM tasks WHERE id=?", (tid,))
        if not t:
            err(404, "not_found")
        mine = c.one("SELECT * FROM task_assignees WHERE task_id=? AND user_id=?", (tid, u["id"]))
        out = task_json(c, t, u, mine)
        rows = c.q("SELECT u.*, a.user_id AS a_user, a.status AS a_status, a.comment AS a_comment, a.photos AS a_photos, "
                   "a.review_note AS a_note, a.submitted_at AS a_sub FROM task_assignees a JOIN users u ON u.id=a.user_id WHERE a.task_id=? "
                   "ORDER BY CASE a.status WHEN 'submitted' THEN 0 WHEN 'returned' THEN 1 WHEN 'new' THEN 2 ELSE 3 END, u.name",
                   (tid,))
        visible = [r for r in rows if can_review(c, u, t, r)]
        if not mine and not visible:
            err(403, "forbidden")
        import rating
        paths = []
        people = []
        giver = t["created_by"] == u["id"] or u["role"] == "admin"
        pts = rating.points_of(c, "task", tid) if giver else {}
        for r in visible:
            photos = json.loads(r["a_photos"] or "[]")
            paths += photos
            people.append({"user": _mini(c, r["a_user"]), "status": r["a_status"], "comment": r["a_comment"],
                           "review_note": r["a_note"], "photos": photos, "submitted_at": r["a_sub"],
                           "can_rate": giver and rating.rated(r), "points": pts.get(r["a_user"], 0)})
        if mine:
            paths += out["my"]["photos"]
        urls = _sign_photos(paths)
        for p in people:
            p["photo_urls"] = [urls.get(x, "") for x in p["photos"]]
        if mine:
            out["my"]["photo_urls"] = [urls.get(x, "") for x in out["my"]["photos"]]
        out["people"] = people
        out["can_review"] = bool(visible)
        return out


@router.post("/api/tasks/{tid}/photo")
async def task_photo(tid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    raw = str(b.get("data") or "")
    if "," in raw[:80]:
        raw = raw.split(",", 1)[1]
    with db.tx() as c:
        u = core.current_user(c, authorization)
        if not c.one("SELECT 1 AS x FROM task_assignees WHERE task_id=? AND user_id=?", (tid, u["id"])):
            err(403, "forbidden")
        if not core.rate_ok("upload:" + u["id"], 30, 3600):
            err(429, "too_many")
    try:
        jpg, w, h = await asyncio.to_thread(channels.process_chat_photo, base64.b64decode(raw, validate=False))
    except Exception:
        err(400, "bad_photo")
    if not storage.enabled():
        err(503, "storage_off")
    path = f"tasks/{tid}/{u['id']}/{core.new_id()}.jpg"
    await asyncio.to_thread(storage.put, path, jpg, "image/jpeg")
    return {"path": path, "w": w, "h": h}


@router.post("/api/tasks/{tid}/submit")
async def task_submit(tid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        u = core.current_user(c, authorization)
        t = c.one("SELECT * FROM tasks WHERE id=?", (tid,))
        a = c.one("SELECT * FROM task_assignees WHERE task_id=? AND user_id=?", (tid, u["id"]))
        if not t or not a:
            err(404, "not_found")
        if a["status"] == "accepted":
            err(400, "already_accepted")
        photos = [str(p) for p in (b.get("photos") or [])][:MAX_REPORT_PHOTOS]
        for p in photos:
            if not p.startswith(f"tasks/{tid}/{u['id']}/") or ".." in p:
                err(400, "bad_attachment")
        if t["photo_required"] and not photos:
            err(400, "photo_required")
        old = json.loads(a["photos"] or "[]")
        c.x("UPDATE task_assignees SET status='submitted', comment=?, photos=?, submitted_at=? WHERE task_id=? AND user_id=?",
            (str(b.get("comment") or "").strip()[:1000], json.dumps(photos), db.now(), tid, u["id"]))
    storage.remove([p for p in old if p not in photos])
    push.send([t["created_by"]], f"✅ {t['title']}", f"{u['name']}: bajarildi · выполнено", {"type": "task", "id": tid})
    return {"ok": True}


@router.post("/api/tasks/{tid}/review")
async def task_review(tid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    action = b.get("action")
    if action not in ("accept", "return"):
        err(400, "bad")
    uid = str(b.get("user_id") or "")
    with db.tx() as c:
        u = core.current_user(c, authorization)
        t = c.one("SELECT * FROM tasks WHERE id=?", (tid,))
        a = c.one("SELECT * FROM task_assignees WHERE task_id=? AND user_id=?", (tid, uid))
        who = c.one("SELECT * FROM users WHERE id=?", (uid,))
        if not t or not a:
            err(404, "not_found")
        if not can_review(c, u, t, who):
            err(403, "forbidden")
        note = clean(b.get("note"), 500)
        if action == "return" and not note:
            err(400, "note_required")
        c.x("UPDATE task_assignees SET status=?, review_note=?, reviewed_at=? WHERE task_id=? AND user_id=?",
            ("accepted" if action == "accept" else "returned", note, db.now(), tid, uid))
    push.send([uid], f"{'👍' if action == 'accept' else '↩️'} {t['title']}",
              "Qabul qilindi · Принято" if action == "accept" else f"Qaytarildi · Возвращено: {note}", {"type": "task", "id": tid})
    return {"ok": True}


@router.post("/api/tasks/{tid}/edit")
async def task_edit(tid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    """Vazifa bergan (yoki admin) nom, tavsif, muddatni tuzatadi / выдавший (или админ) правит название, описание, срок."""
    b = await request.json()
    title = clean(b.get("title"), 120)
    if len(title) < 2:
        err(400, "bad_title")
    deadline = _deadline_ok(b.get("deadline"))
    with db.tx() as c:
        u = core.current_user(c, authorization)
        t = c.one("SELECT * FROM tasks WHERE id=?", (tid,))
        if not t:
            err(404, "not_found")
        if t["created_by"] != u["id"] and u["role"] != "admin":
            err(403, "forbidden")
        c.x("UPDATE tasks SET title=?, description=?, deadline=?, photo_required=? WHERE id=?",
            (title, str(b.get("description") or "").strip()[:2000], deadline,
             1 if b.get("photo_required", bool(t["photo_required"])) else 0, tid))
        return task_json(c, c.one("SELECT * FROM tasks WHERE id=?", (tid,)), u)


@router.post("/api/tasks/{tid}/delete")
def task_delete(tid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        t = c.one("SELECT * FROM tasks WHERE id=?", (tid,))
        if not t:
            err(404, "not_found")
        if t["created_by"] != u["id"] and u["role"] != "admin":
            err(403, "forbidden")
        paths = []
        for r in c.q("SELECT photos FROM task_assignees WHERE task_id=?", (tid,)):
            paths += json.loads(r["photos"] or "[]")
        c.x("DELETE FROM task_assignees WHERE task_id=?", (tid,))
        c.x("DELETE FROM tasks WHERE id=?", (tid,))
    storage.remove(paths)
    return {"ok": True}


# ------------------------------------------------------------------ tadbirlar / мероприятия
def event_json(c, e, viewer):
    rows = c.q("SELECT rsvp, user_id FROM event_guests WHERE event_id=?", (e["id"],))
    mine = next((r["rsvp"] for r in rows if r["user_id"] == viewer["id"]), None)
    return {"id": e["id"], "title": e["title"], "description": e["description"], "place": e["place"],
            "starts_at": e["starts_at"], "ends_at": e["ends_at"], "by": _mini(c, e["created_by"]),
            "is_organizer": e["created_by"] == viewer["id"] or viewer["role"] == "admin",
            "guests": len(rows), "yes": sum(1 for r in rows if r["rsvp"] == "yes"),
            "no": sum(1 for r in rows if r["rsvp"] == "no"), "my_rsvp": mine}


@router.get("/api/events")
def events_list(when: str = "upcoming", authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        cut = db.now() - 6 * 3600
        cond, order = ("e.starts_at>=?", "e.starts_at") if when != "past" else ("e.starts_at<?", "e.starts_at DESC")
        rows = c.q(f"SELECT DISTINCT e.* FROM events e LEFT JOIN event_guests g ON g.event_id=e.id AND g.user_id=? "
                   f"WHERE (g.user_id IS NOT NULL OR e.created_by=?) AND {cond} ORDER BY {order} LIMIT 200",
                   (u["id"], u["id"], cut))
        return {"events": [event_json(c, e, u) for e in rows], "can_create": core.can_give(u)}


@router.post("/api/events")
async def events_create(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    title = clean(b.get("title"), 120)
    if len(title) < 2:
        err(400, "bad_title")
    starts = _deadline_ok(b.get("starts_at"))
    ends = int(b.get("ends_at") or 0)
    if ends and ends < starts:
        ends = 0
    with db.tx() as c:
        u = core.current_user(c, authorization)
        if not core.can_give(u):
            err(403, "forbidden")
        if not core.rate_ok("event:" + u["id"], 30, 3600):
            err(429, "too_many")
        peers = u["role"] == "admin" or (u.get("level") in ("district", "region") and u.get("kind") != "staff")
        targets = channels.resolve_audience(c, u, b.get("audience"), b.get("user_ids"), peers=peers)
        if not targets:
            err(400, "no_people")
        eid = core.new_id()
        c.x("INSERT INTO events (id, created_by, title, description, place, starts_at, ends_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (eid, u["id"], title, str(b.get("description") or "").strip()[:2000], clean(b.get("place"), 200), starts, ends, db.now()))
        for t in targets:
            c.x("INSERT INTO event_guests (event_id, user_id) VALUES (?, ?)", (eid, t["id"]))
        out = event_json(c, c.one("SELECT * FROM events WHERE id=?", (eid,)), u)
    push.send([t["id"] for t in targets], f"📅 {title}", f"Yangi tadbir · Новое мероприятие — {u['name']}", {"type": "event", "id": eid})
    return out


@router.get("/api/events/{eid}")
def event_get(eid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        e = c.one("SELECT * FROM events WHERE id=?", (eid,))
        if not e:
            err(404, "not_found")
        guest = c.one("SELECT 1 AS x FROM event_guests WHERE event_id=? AND user_id=?", (eid, u["id"]))
        if not guest and e["created_by"] != u["id"] and u["role"] != "admin":
            err(403, "forbidden")
        out = event_json(c, e, u)
        if out["is_organizer"]:
            import rating
            rows = c.q("SELECT g.rsvp, g.checked_at AS g_checked, g.user_id AS g_user, u.* FROM event_guests g "
                       "JOIN users u ON u.id=g.user_id "
                       "WHERE g.event_id=? ORDER BY u.name", (eid,))
            pts = rating.points_of(c, "event", eid)
            started = e["starts_at"] <= db.now()
            out["people"] = [{"user": _mini(c, r["g_user"]), "rsvp": r["rsvp"], "can_mark": started and rating.rated(r),
                              "came": None if r["g_user"] not in pts else pts[r["g_user"]] > 0,
                              "checked_in": bool(r["g_checked"])} for r in rows]
        if guest:
            out["my_checkin"] = bool(c.one("SELECT checked_at FROM event_guests WHERE event_id=? AND user_id=?",
                                           (eid, u["id"]))["checked_at"])
        return out


@router.post("/api/events/{eid}/rsvp")
async def event_rsvp(eid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    rsvp = b.get("rsvp") if b.get("rsvp") in ("yes", "no") else ""
    with db.tx() as c:
        u = core.current_user(c, authorization)
        if not c.one("SELECT 1 AS x FROM event_guests WHERE event_id=? AND user_id=?", (eid, u["id"])):
            err(403, "forbidden")
        c.x("UPDATE event_guests SET rsvp=? WHERE event_id=? AND user_id=?", (rsvp, eid, u["id"]))
    return {"ok": True}


@router.post("/api/events/{eid}/edit")
async def event_edit(eid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    title = clean(b.get("title"), 120)
    if len(title) < 2:
        err(400, "bad_title")
    starts = _deadline_ok(b.get("starts_at"))
    with db.tx() as c:
        u = core.current_user(c, authorization)
        e = c.one("SELECT * FROM events WHERE id=?", (eid,))
        if not e:
            err(404, "not_found")
        if e["created_by"] != u["id"] and u["role"] != "admin":
            err(403, "forbidden")
        moved = starts != e["starts_at"]
        c.x("UPDATE events SET title=?, description=?, place=?, starts_at=? WHERE id=?",
            (title, str(b.get("description") or "").strip()[:2000], clean(b.get("place"), 200), starts, eid))
        guests = [r["user_id"] for r in c.q("SELECT user_id FROM event_guests WHERE event_id=?", (eid,))]
        out = event_json(c, c.one("SELECT * FROM events WHERE id=?", (eid,)), u)
    if moved:
        push.send(guests, f"🕒 {title}", "Tadbir vaqti o‘zgardi · Время мероприятия изменено", {"type": "event", "id": eid})
    return out


@router.post("/api/events/{eid}/delete")
def event_delete(eid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        e = c.one("SELECT * FROM events WHERE id=?", (eid,))
        if not e:
            err(404, "not_found")
        if e["created_by"] != u["id"] and u["role"] != "admin":
            err(403, "forbidden")
        guests = [r["user_id"] for r in c.q("SELECT user_id FROM event_guests WHERE event_id=?", (eid,))]
        c.x("DELETE FROM event_guests WHERE event_id=?", (eid,))
        c.x("DELETE FROM events WHERE id=?", (eid,))
    push.send(guests, f"❌ {e['title']}", "Tadbir bekor qilindi · Мероприятие отменено", {"type": "event"})
    return {"ok": True}


# ------------------------------------------------------------------ bugun / сегодня
@router.get("/api/today")
def today(authorization: Optional[str] = Header(default=None)):
    """Bugungi ishlar: muddati yaqin/o‘tgan vazifalar, yaqin tadbirlar, tekshirilishi kerak hisobotlar.
    Дела на сегодня: задачи со сроком скоро/просрочены, ближайшие мероприятия, отчёты на проверку."""
    with db.tx() as c:
        u = core.current_user(c, authorization)
        now = db.now()
        tasks = []
        for t in c.q("SELECT t.* FROM tasks t JOIN task_assignees a ON a.task_id=t.id WHERE a.user_id=? "
                     "AND a.status IN ('new','returned') AND t.deadline<? ORDER BY t.deadline LIMIT 20", (u["id"], now + 7 * 86400)):
            mine = c.one("SELECT * FROM task_assignees WHERE task_id=? AND user_id=?", (t["id"], u["id"]))
            tasks.append(task_json(c, t, u, mine))
        events = [event_json(c, e, u) for e in c.q(
            "SELECT DISTINCT e.* FROM events e LEFT JOIN event_guests g ON g.event_id=e.id AND g.user_id=? "
            "WHERE (g.user_id IS NOT NULL OR e.created_by=?) AND e.starts_at>=? AND e.starts_at<? ORDER BY e.starts_at LIMIT 10",
            (u["id"], u["id"], now - 3 * 3600, now + 7 * 86400))]
        review = c.one("SELECT COUNT(*) AS n FROM task_assignees a JOIN tasks t ON t.id=a.task_id "
                       "WHERE t.created_by=? AND a.status='submitted'", (u["id"],))["n"]
        return {"tasks": tasks, "events": events, "to_review": review}


# ------------------------------------------------------------------ push qurilmalari / push-устройства
@router.post("/api/push/register")
async def push_register(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    token = str(b.get("token") or "").strip()[:500]
    if len(token) < 20:
        err(400, "bad")
    with db.tx() as c:
        u = core.current_user(c, authorization)
        c.x("DELETE FROM push_tokens WHERE token=?", (token,))
        c.x("INSERT INTO push_tokens (token, user_id, platform, created_at) VALUES (?, ?, ?, ?)",
            (token, u["id"], clean(b.get("platform"), 20), db.now()))
    return {"ok": True, "enabled": push.enabled()}


@router.post("/api/push/unregister")
async def push_unregister(request: Request):
    b = await request.json()
    with db.tx() as c:
        c.x("DELETE FROM push_tokens WHERE token=?", (str(b.get("token") or ""),))
    return {"ok": True}


# ------------------------------------------------------------------ eslatmalar / напоминания
def run_reminders():
    """Muddat va tadbir eslatmalari (har biri bir marta) / напоминания о сроках и мероприятиях (по одному разу)."""
    now = db.now()
    out = []
    with db.tx() as c:
        for hours, tag in ((24, "24h"), (2, "2h")):
            for t in c.q("SELECT * FROM tasks WHERE deadline>? AND deadline<=?", (now, now + hours * 3600)):
                if not push.once(c, f"task:{t['id']}:{tag}"):
                    continue
                users = [r["user_id"] for r in c.q(
                    "SELECT user_id FROM task_assignees WHERE task_id=? AND status IN ('new','returned')", (t["id"],))]
                out.append((users, f"⏰ {t['title']}",
                            "Muddat ertaga · Срок завтра" if tag == "24h" else "2 soat qoldi · Осталось 2 часа",
                            {"type": "task", "id": t["id"]}))
        for hours, tag in ((24, "1d"), (1, "1h")):
            for e in c.q("SELECT * FROM events WHERE starts_at>? AND starts_at<=?", (now, now + hours * 3600)):
                if not push.once(c, f"event:{e['id']}:{tag}"):
                    continue
                users = [r["user_id"] for r in c.q("SELECT user_id FROM event_guests WHERE event_id=? AND rsvp<>'no'", (e["id"],))]
                out.append((users, f"📅 {e['title']}", "Ertaga · Завтра" if tag == "1d" else "1 soatdan keyin · Через час",
                            {"type": "event", "id": e["id"]}))
    for args in out:
        push.send(*args)
    return len(out)


def background_tick():
    """Fon ishlarining bitta aylanishi. Xato bo‘lsa — logga yoziladi (Render → Logs), qolganlari davom etadi.
    Один проход фоновых задач. Ошибка пишется в лог (Render → Logs), остальные задачи продолжаются."""
    import certificates
    import digest
    import report
    jobs = [("reminders", run_reminders),
            ("monthly report", report.send_monthly),       # oy boshida rahbarlarga / в начале месяца руководителям
            ("weekly digest", digest.send_weekly),         # dushanba dayjesti / дайджест понедельника
            ("certificates", certificates.notify_winners)]  # chorak boshida g‘oliblarga / в начале квартала
    for name, job in jobs:
        try:
            job()
        except Exception:
            log.exception("background job failed: %s", name)


def start_reminder_loop():
    def loop():
        while True:
            background_tick()
            time.sleep(300)
    threading.Thread(target=loop, daemon=True).start()
