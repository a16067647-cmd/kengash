"""Adminga yozish (shikoyat/taklif/savol) va admin vositalari: e’lon tarqatish, faollik, foydalanuvchini tahrirlash, Excel.
Написать админу (жалоба/предложение/вопрос) и инструменты админа: рассылка, активность, правка пользователя, Excel.
"""
import asyncio
import base64
import io
from typing import Optional

from fastapi import APIRouter, Header, Request

import app as core
import db
import model
import push
import storage
from model import DIRECTION_KEYS, LEVELS, SEAT_DIRECTIONS

router = APIRouter()
err = core.err
clean = core.clean
TOPICS = ("shikoyat", "taklif", "savol")


# ------------------------------------------------------------------ adminga yozish / написать админу
@router.post("/api/feedback")
async def feedback(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    topic = b.get("topic") if b.get("topic") in TOPICS else "shikoyat"
    text = str(b.get("text") or "").strip()[:2000]
    if len(text) < 3:
        err(400, "empty")
    raw = str(b.get("photo") or "")
    with db.tx() as c:
        u = core.current_user(c, authorization, active=False)
        if not core.rate_ok("feedback:" + u["id"], 5, 3600):
            err(429, "too_many")
    photo_path = ""
    if raw:
        import channels
        if "," in raw[:80]:
            raw = raw.split(",", 1)[1]
        try:
            jpg, _, _ = await asyncio.to_thread(channels.process_chat_photo, base64.b64decode(raw, validate=False))
        except Exception:
            err(400, "bad_photo")
        if storage.enabled():
            photo_path = f"feedback/{core.new_id()}.jpg"
            await asyncio.to_thread(storage.put, photo_path, jpg, "image/jpeg")
    with db.tx() as c:
        c.x("INSERT INTO reports (id, message_id, channel_id, reporter_id, reason, note, created_at, kind, photo_path) "
            "VALUES (?, '', '', ?, ?, ?, ?, 'feedback', ?)", (core.new_id(), u["id"], topic, text, db.now(), photo_path))
        admins = [r["id"] for r in c.q("SELECT id FROM users WHERE role='admin' AND status='active'")]
    label = {"shikoyat": "⚠️ Shikoyat", "taklif": "💡 Taklif", "savol": "❓ Savol"}[topic]
    push.send(admins, f"{label} — {u['name'] or 'Kengash'}", text[:200], {"type": "feedback"})
    return {"ok": True}


@router.post("/api/admin/feedback/{rid}/reply")
async def feedback_reply(rid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    """Admin javobi Telegram orqali yuboriladi / ответ админа уходит в Telegram."""
    b = await request.json()
    text = str(b.get("text") or "").strip()[:2000]
    if len(text) < 1:
        err(400, "empty")
    with db.tx() as c:
        core.need_admin(core.current_user(c, authorization))
        r = c.one("SELECT * FROM reports WHERE id=? AND kind='feedback'", (rid,))
        if not r:
            err(404, "not_found")
        c.x("UPDATE reports SET reply=?, status='done' WHERE id=?", (text, rid))
        who = c.one("SELECT tg_id FROM users WHERE id=?", (r["reporter_id"],))
    if who and who["tg_id"]:
        import html

        import telegram
        try:
            telegram.send(who["tg_id"], f"💬 <b>Admin javobi / Ответ админа</b>\n\n<i>{html.escape(r['note'][:300])}</i>\n\n"
                                        f"{html.escape(text)}")
        except Exception:
            pass
    push.SENT.append({"users": [r["reporter_id"]], "title": "reply", "body": text, "data": {"type": "feedback"}})
    return {"ok": True}


# ------------------------------------------------------------------ xodim hududi / территория сотрудника
def need_power(u, power):
    """Admin yoki shu vakolatli xodim / админ или сотрудник с этим полномочием."""
    if not model.has_power(u, power):
        err(403, "forbidden")


def area_sql(u, alias="u"):
    """Xodim hududidagi foydalanuvchilar (SQL bo‘lagi, parametrlar). Admin uchun — cheklovsiz.
    Пользователи территории сотрудника (фрагмент SQL, параметры). Для админа — без ограничений."""
    if u["role"] == "admin":
        return "1=1", []
    a, pid = alias, u["place_id"]
    if u["level"] == "district":
        return (f"(({a}.level='district' AND {a}.place_id=?) OR ({a}.level='school' AND {a}.place_id IN "
                f"(SELECT id FROM schools WHERE district_id=?)))"), [pid, pid]
    return (f"(({a}.level='region' AND {a}.place_id=?) OR ({a}.level='district' AND {a}.place_id IN "
            f"(SELECT id FROM districts WHERE region_id=?)) OR ({a}.level='school' AND {a}.place_id IN "
            f"(SELECT s.id FROM schools s JOIN districts d ON d.id=s.district_id WHERE d.region_id=?)))"), [pid, pid, pid]


def staff_scope(u, alias="u"):
    """Hudud + o‘quvchilarsiz (xodim o‘quvchilarni ko‘rmaydi) / территория, без учеников."""
    sql, params = area_sql(u, alias)
    if u["role"] == "admin":
        return sql, params
    return f"{sql} AND {alias}.kind IN ('coordinator','maslahatchi')", params


# ------------------------------------------------------------------ e’lon tarqatish / рассылка
def _audience(c, f, actor=None):
    where, params = ["u.status='active'", "u.role<>'admin'"], []
    if actor is not None and actor["role"] != "admin":
        sql, p = area_sql(actor)  # e’lon o‘quvchilarga ham boradi / объявление доходит и до учеников
        where.append(sql)
        params += p
        where.append("u.id<>?")
        params.append(actor["id"])
    kind = f.get("kind")
    if kind == "student":
        where.append("u.kind='student'")
    elif kind == "maslahatchi":
        where.append("u.kind='maslahatchi'")
    elif kind == "coordinator":
        where.append("u.kind='coordinator'")
    if f.get("level") in LEVELS:
        where.append("u.level=?")
        params.append(f["level"])
    if f.get("direction") in DIRECTION_KEYS:
        where.append("u.direction=?")
        params.append(f["direction"])
    did = str(f.get("district_id") or "")
    if did:
        where.append("((u.level='district' AND u.place_id=?) OR (u.level='school' AND u.place_id IN "
                     "(SELECT id FROM schools WHERE district_id=?)))")
        params += [did, did]
    return c.q(f"SELECT u.id FROM users u WHERE {' AND '.join(where)}", params)


@router.post("/api/admin/broadcast/count")
async def broadcast_count(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        u = core.current_user(c, authorization)
        need_power(u, "announce")
        return {"count": len(_audience(c, b.get("filter") or {}, u))}


@router.post("/api/admin/broadcast")
async def broadcast(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    text = str(b.get("text") or "").strip()[:3000]
    if len(text) < 2:
        err(400, "empty")
    f = b.get("filter") or {}
    with db.tx() as c:
        u = core.current_user(c, authorization)
        need_power(u, "announce")
        if not core.rate_ok("broadcast:" + u["id"], 10, 3600):
            err(429, "too_many")
        ids = [r["id"] for r in _audience(c, f, u)]
        title = "📣 Kengash" if u["role"] == "admin" else f"📣 {u['title'] or u['name']}"
    push.send(ids, title, text, {"type": "broadcast"})
    return {"ok": True, "count": len(ids)}


# ------------------------------------------------------------------ faollik / активность
@router.get("/api/admin/activity")
def activity(authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        v = core.current_user(c, authorization)
        need_power(v, "view")
        week, month = db.now() - 7 * 86400, db.now() - 30 * 86400
        scope, sp = staff_scope(v)
        inactive = c.q(f"SELECT * FROM users u WHERE status='active' AND role<>'admin' AND last_seen<? AND {scope} "
                       "ORDER BY last_seen LIMIT 50", [week] + sp)
        inactive_n = c.one(f"SELECT COUNT(*) AS n FROM users u WHERE status='active' AND role<>'admin' AND last_seen<? "
                           f"AND {scope}", [week] + sp)["n"]
        districts = []
        if v["role"] == "admin":
            dist_rows = c.q("SELECT * FROM districts ORDER BY sort")
        elif v["level"] == "district":
            dist_rows = c.q("SELECT * FROM districts WHERE id=?", (v["place_id"],))
        else:
            dist_rows = c.q("SELECT * FROM districts WHERE region_id=? ORDER BY sort", (v["place_id"],))
        for d in dist_rows:
            sch = "SELECT id FROM schools WHERE district_id=? AND hidden=0"
            tot = c.one(f"SELECT COUNT(*) AS n FROM task_assignees a JOIN tasks t ON t.id=a.task_id JOIN users u ON u.id=a.user_id "
                        f"WHERE t.created_at>? AND ((u.level='district' AND u.place_id=?) OR (u.level='school' AND u.place_id IN ({sch})))",
                        (month, d["id"], d["id"]))["n"]
            done = c.one(f"SELECT COUNT(*) AS n FROM task_assignees a JOIN tasks t ON t.id=a.task_id JOIN users u ON u.id=a.user_id "
                         f"WHERE t.created_at>? AND a.status IN ('submitted','accepted') AND "
                         f"((u.level='district' AND u.place_id=?) OR (u.level='school' AND u.place_id IN ({sch})))",
                         (month, d["id"], d["id"]))["n"]
            schools = c.one(f"SELECT COUNT(*) AS n FROM ({sch}) s", (d["id"],))["n"]
            empty = c.one(f"SELECT COUNT(*) AS n FROM ({sch}) s WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.level='school' "
                          f"AND u.place_id=s.id AND u.direction IS NOT NULL AND u.status='active')", (d["id"],))["n"]
            districts.append({"id": d["id"], "name_uz": d["name_uz"], "name_ru": d["name_ru"], "tasks": tot,
                              "done_pct": round(done * 100 / tot) if tot else None, "schools": schools,
                              "schools_empty": empty})
        top = c.q("SELECT ch.auto_key, COUNT(m.id) AS n FROM messages m JOIN channels ch ON ch.id=m.channel_id "
                  "WHERE m.created_at>? AND (ch.auto_key LIKE 'chat:%' OR ch.auto_key LIKE 'school:%' OR ch.auto_key LIKE 'news:%') "
                  "GROUP BY ch.auto_key ORDER BY n DESC LIMIT 30", (week,))
        by_school = {}
        allowed = {d["id"] for d in dist_rows}
        for r in top:
            sid = r["auto_key"].split(":", 1)[1]
            if v["role"] != "admin":
                p0 = core.place_info(c, "school", sid)
                if not p0 or p0["district_id"] not in allowed:
                    continue
            by_school[sid] = by_school.get(sid, 0) + r["n"]
        top_schools = []
        for sid, n in sorted(by_school.items(), key=lambda x: -x[1])[:5]:
            p = core.place_info(c, "school", sid)
            if p:
                top_schools.append({"place": p, "messages": n})
        return {"inactive_count": inactive_n,
                "inactive": [core.public_user(c, r, v) | {"last_seen": r["last_seen"]} for r in inactive],
                "districts": districts, "top_schools": top_schools}


# ------------------------------------------------------------------ foydalanuvchini tahrirlash / правка пользователя
@router.post("/api/admin/users/{uid}/edit")
async def user_edit(uid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    """Ism, rol, o‘rin (maktab/sinf/yo‘nalish), holat. Bo‘sh maydon — o‘zgarmaydi.
    Имя, роль, место (школа/класс/направление), статус. Пустое поле — без изменений."""
    import register as reg
    b = await request.json()
    with db.tx() as c:
        v = core.current_user(c, authorization)
        core.need_admin(v)
        u = c.one("SELECT * FROM users WHERE id=?", (uid,))
        if not u:
            err(404, "not_found")
        if b.get("name") is not None:
            try:
                name = reg.clean_name(b.get("name"))
            except reg.RegError:
                err(400, "bad_name")
            c.x("UPDATE users SET name=? WHERE id=?", (name, uid))
        if b.get("kind") in ("coordinator", "maslahatchi", "student"):  # xodim — /api/admin/staff orqali
            kind = b["kind"]
            level = b.get("level") if kind == "coordinator" else "school"
            place_id = str(b.get("place_id") or "")
            direction = None if kind == "student" else (model.MASLAHATCHI if kind == "maslahatchi" else b.get("direction"))
            if level not in LEVELS or (direction is not None and direction not in SEAT_DIRECTIONS):
                err(400, "bad_seat")
            if not model.place_chain(c, level, place_id):
                err(400, "bad_seat")
            if direction is not None:
                holder = c.one("SELECT id FROM users WHERE level=? AND place_id=? AND direction=? AND id<>? "
                               "AND status IN ('active','pending')", (level, place_id, direction, uid))
                if holder:
                    err(409, "seat_taken")
            cls = ""
            if kind == "student":
                import re
                cls = str(b.get("class_name") or u["class_name"] or "")[:6]
                if not re.match(r"^(1[01]?|[1-9])(-[A-ZА-Я])?$", cls):
                    err(400, "bad_class")
            c.x("UPDATE users SET level=NULL, place_id=NULL, direction=NULL WHERE id=?", (uid,))
            c.x("UPDATE users SET kind=?, level=?, place_id=?, direction=?, class_name=? WHERE id=?",
                (kind, level, place_id, direction, cls, uid))
        if b.get("status") in ("active", "rejected") and u["status"] != "blocked":
            c.x("UPDATE users SET status=? WHERE id=?", (b["status"], uid))
        core.seat_changed(c, uid)
        return core.public_user(c, c.one("SELECT * FROM users WHERE id=?", (uid,)), v) | {"status": c.one(
            "SELECT status FROM users WHERE id=?", (uid,))["status"]}


# ------------------------------------------------------------------ Excel
def _place(c, u):
    p = core.place_info(c, u["level"], u["place_id"]) if u["level"] else None
    if not p:
        return "", ""
    if p.get("level") == "school":
        return p.get("district_uz", ""), p.get("name_uz", "")
    return (p.get("name_uz", ""), "") if p.get("level") == "district" else ("", "")


def build_xlsx(c, what, viewer=None):
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill
    import rating
    wb = Workbook()
    ws = wb.active
    dname = {k: uz for k, uz, _ in model.DIRECTIONS} | {model.MASLAHATCHI: "Maslahatchi"}
    if what == "users":
        ws.title = "Foydalanuvchilar"
        ws.append(["Ism", "Rol", "Daraja", "Tuman", "Maktab", "Sinf", "Yo‘nalish", "Telefon", "Telegram", "Holat",
                   "Oxirgi kirish"])
        scope, sp = staff_scope(viewer) if viewer else ("1=1", [])
        for u in c.q(f"SELECT * FROM users u WHERE {scope} ORDER BY name", sp):
            dist, school = _place(c, u)
            ws.append([u["name"], u["kind"] or u["role"], u["level"] or "", dist, school, u["class_name"],
                       dname.get(u["direction"], ""), u["phone"] or "", ("@" + u["tg_username"]) if u["tg_username"] else "",
                       u["status"], _date(u["last_seen"])])
    elif what == "tasks":
        ws.title = "Vazifalar"
        ws.append(["Vazifa", "Kim berdi", "Muddat", "Bajaruvchi", "Holat", "Izoh", "Topshirgan vaqti", "Baho"])
        for t in c.q("SELECT * FROM tasks ORDER BY created_at DESC LIMIT 500"):
            by = c.one("SELECT name FROM users WHERE id=?", (t["created_by"],))
            pts = rating.points_of(c, "task", t["id"])
            scope, sp = staff_scope(viewer) if viewer else ("1=1", [])
            for a in c.q(f"SELECT a.*, u.name AS u_name FROM task_assignees a JOIN users u ON u.id=a.user_id "
                         f"WHERE a.task_id=? AND {scope}", [t["id"]] + sp):
                ws.append([t["title"], by["name"] if by else "", _date(t["deadline"]), a["u_name"], a["status"],
                           a["comment"], _date(a["submitted_at"]), pts.get(a["user_id"], "")])
    elif what == "rating":
        ws.title = "Reyting"
        start, label = rating.quarter()
        ws.append([f"Chorak: {label}", "", "", "", ""])
        ws.append(["Ism", "Daraja", "Yo‘nalish", "Joy", "Ball"])
        scope, sp = staff_scope(viewer) if viewer else ("1=1", [])
        rows = c.q("SELECT u.*, COALESCE((SELECT SUM(p.value) FROM points p WHERE p.user_id=u.id AND p.created_at>=?), 0) AS score "
                   f"FROM users u WHERE u.kind='coordinator' AND u.status='active' AND {scope} ORDER BY score DESC, u.name",
                   [start] + sp)
        for u in rows:
            dist, school = _place(c, u)
            ws.append([u["name"], u["level"], dname.get(u["direction"], ""), school or dist or "Viloyat", int(u["score"])])
    elif what == "books":
        ws.title = "Kitobxonlar"
        ws.append(["Kitob", "Yo‘nalish", "Ism", "Rol", "Maktab", "Sana"])
        for b in c.q("SELECT * FROM books"):
            for r in c.q("SELECT r.at, u.* FROM book_reads r JOIN users u ON u.id=r.user_id WHERE r.book_id=? ORDER BY r.at",
                         (b["id"],)):
                dist, school = _place(c, r)
                ws.append([b["title"], dname.get(b["direction"], ""), r["name"], r["kind"], school or dist, _date(r["at"])])
    else:
        err(400, "bad")
    head = 2 if what == "rating" else 1
    for cell in ws[head]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="5B2DC9")
    for col in ws.columns:
        width = max((len(str(x.value or "")) for x in col), default=8)
        ws.column_dimensions[col[0].column_letter].width = min(48, max(10, width + 2))
    ws.freeze_panes = ws.cell(row=head + 1, column=1)
    out = io.BytesIO()
    wb.save(out)
    return out.getvalue()


def _date(ts):
    import datetime
    if not ts:
        return ""
    return datetime.datetime.fromtimestamp(ts, datetime.timezone(datetime.timedelta(hours=5))).strftime("%Y-%m-%d %H:%M")


@router.post("/api/admin/export")
async def export(request: Request, authorization: Optional[str] = Header(default=None)):
    """Excel faylni yaratib, 10 daqiqalik yuklab olish havolasini beradi / создаёт Excel и даёт ссылку на 10 минут."""
    b = await request.json()
    what = b.get("what")
    if what not in ("users", "tasks", "rating", "books"):
        err(400, "bad")
    with db.tx() as c:
        u = core.current_user(c, authorization)
        need_power(u, "announce")
        if u["role"] != "admin" and what == "books":
            err(403, "forbidden")
        data = build_xlsx(c, what, u)
    if not storage.enabled():
        err(503, "storage_off")
    import time
    path = f"exports/{what}-{time.strftime('%Y%m%d-%H%M')}-{core.new_id()[:6]}.xlsx"
    await asyncio.to_thread(storage.put, path, data,
                            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    url = (await asyncio.to_thread(storage.sign, [path], 600)).get(path, "")
    return {"url": url, "size": len(data)}
