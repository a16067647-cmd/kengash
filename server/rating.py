"""Reyting: vazifa bergan +1/−1 qo‘yadi (yoki qo‘ymaydi), tadbir tashkilotchisi kelgan/kelmaganini belgilaydi.
Har chorakda noldan boshlanadi; tarix saqlanadi. Faqat koordinatorlar baholanadi.
Рейтинг: выдавший задачу ставит +1/−1 (или не ставит), организатор отмечает пришёл/не пришёл.
Каждый квартал с нуля; история хранится. Оцениваются только координаторы.
"""
import datetime
from typing import Optional

from fastapi import APIRouter, Header, Request

import app as core
import db
import push
from model import DIRECTION_KEYS

router = APIRouter()
err = core.err
TZ = datetime.timezone(datetime.timedelta(hours=5))  # Toshkent / Ташкент


def quarter(ts=None):
    """(boshlanish vaqti, yorliq) / (начало, метка), masalan (…, '2026 · IV')."""
    d = datetime.datetime.fromtimestamp(ts or db.now(), TZ)
    q = (d.month - 1) // 3
    start = datetime.datetime(d.year, q * 3 + 1, 1, tzinfo=TZ)
    return int(start.timestamp()), f"{d.year} · {'I II III IV'.split()[q]}"


def rated(u):
    return bool(u) and u.get("direction") in DIRECTION_KEYS and u.get("status") == "active"


def set_point(c, kind, ref_id, user_id, by_id, value):
    c.x("DELETE FROM points WHERE kind=? AND ref_id=? AND user_id=?", (kind, ref_id, user_id))
    if value:
        c.x("INSERT INTO points (kind, ref_id, user_id, by_id, value, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            (kind, ref_id, user_id, by_id, value, db.now()))


def points_of(c, kind, ref_id):
    return {r["user_id"]: r["value"] for r in c.q("SELECT user_id, value FROM points WHERE kind=? AND ref_id=?", (kind, ref_id))}


def score(c, uid):
    start, _ = quarter()
    r = c.one("SELECT COALESCE(SUM(value), 0) AS s FROM points WHERE user_id=? AND created_at>=?", (uid, start))
    return int(r["s"])


def _value(b):
    v = b.get("value")
    if v not in (1, -1, 0, None):
        err(400, "bad")
    return v or 0


@router.post("/api/tasks/{tid}/rate")
async def task_rate(tid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    """Faqat vazifa bergan (yoki admin) / только выдавший (или админ). value: 1, -1 yoki 0 (olib tashlash)."""
    b = await request.json()
    value = _value(b)
    uid = str(b.get("user_id") or "")
    with db.tx() as c:
        u = core.current_user(c, authorization)
        t = c.one("SELECT * FROM tasks WHERE id=?", (tid,))
        a = c.one("SELECT * FROM task_assignees WHERE task_id=? AND user_id=?", (tid, uid))
        if not t or not a:
            err(404, "not_found")
        if t["created_by"] != u["id"] and u["role"] != "admin":
            err(403, "forbidden")
        who = c.one("SELECT * FROM users WHERE id=?", (uid,))
        if not rated(who):
            err(400, "not_rated")
        if a["status"] == "new" and t["deadline"] > db.now():
            err(400, "too_early")
        set_point(c, "task", tid, uid, u["id"], value)
    if value:
        push.send([uid], f"{'⭐ +1' if value > 0 else '🔻 −1'} · {t['title']}", f"Reyting · Рейтинг — {u['name']}",
                  {"type": "task", "id": tid})
    return {"ok": True, "value": value}


@router.post("/api/events/{eid}/attendance")
async def event_attendance(eid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    """Tashkilotchi: keldi (+1), kelmadi (−1) yoki belgisiz / организатор: пришёл, не пришёл или без отметки."""
    b = await request.json()
    came = b.get("came")
    if came not in (True, False, None):
        err(400, "bad")
    uid = str(b.get("user_id") or "")
    with db.tx() as c:
        u = core.current_user(c, authorization)
        e = c.one("SELECT * FROM events WHERE id=?", (eid,))
        if not e:
            err(404, "not_found")
        if e["created_by"] != u["id"] and u["role"] != "admin":
            err(403, "forbidden")
        if e["starts_at"] > db.now():
            err(400, "too_early")
        if not c.one("SELECT 1 AS x FROM event_guests WHERE event_id=? AND user_id=?", (eid, uid)):
            err(404, "not_found")
        who = c.one("SELECT * FROM users WHERE id=?", (uid,))
        if not rated(who):
            err(400, "not_rated")
        set_point(c, "event", eid, uid, u["id"], 0 if came is None else (1 if came else -1))
    return {"ok": True}


def _group(c, viewer, level, place_id):
    """Standart guruh: o‘z darajasi, bir pog‘ona yuqori joy / группа по умолчанию: свой уровень, место на ступень выше."""
    if level in ("school", "district", "region") and place_id:
        return level, place_id
    lv, pid = viewer.get("level"), viewer.get("place_id")
    if lv == "school":
        s = c.one("SELECT district_id FROM schools WHERE id=?", (pid,))
        return "school", s["district_id"] if s else ""
    if lv == "district":
        d = c.one("SELECT region_id FROM districts WHERE id=?", (pid,))
        return "district", d["region_id"] if d else "andijon"
    return "region", "andijon"


@router.get("/api/rating")
def leaderboard(level: str = "", place_id: str = "", direction: str = "",
                authorization: Optional[str] = Header(default=None)):
    """Ochiq reyting (koordinatorlar uchun) / открытый рейтинг (для координаторов).
    level=school → place_id=tuman; level=district → place_id=viloyat; level=region → place_id=viloyat."""
    with db.tx() as c:
        u = core.current_user(c, authorization)
        if u.get("kind") == "student":
            err(403, "forbidden")
        level, place_id = _group(c, u, level, place_id)
        if level == "school":
            where = "u.place_id IN (SELECT id FROM schools WHERE district_id=?)"
        elif level == "district":
            where = "u.place_id IN (SELECT id FROM districts WHERE region_id=?)"
        else:
            where = "u.place_id=?"
        params = [level, place_id]
        dirs = [direction] if direction in DIRECTION_KEYS else DIRECTION_KEYS
        start, label = quarter()
        rows = c.q(
            "SELECT u.*, COALESCE((SELECT SUM(p.value) FROM points p WHERE p.user_id=u.id AND p.created_at>=?), 0) AS score "
            f"FROM users u WHERE u.level=? AND {where} AND u.status='active' "
            f"AND u.direction IN ({','.join('?' * len(dirs))}) ORDER BY score DESC, u.name LIMIT 300",
            [start] + params + dirs)
        people, rank, prev = [], 0, None
        for i, r in enumerate(rows):
            if r["score"] != prev:
                rank, prev = i + 1, r["score"]
            people.append({"rank": rank, "score": int(r["score"]), "user": core.public_user(c, r, u)})
        mine = next((p for p in people if p["user"]["id"] == u["id"]), None)
        return {"quarter": label, "level": level, "place_id": place_id, "direction": direction or None,
                "place": core.place_info(c, "district" if level == "school" else "region", place_id),
                "people": people[:100], "total": len(people),
                "me": {"score": score(c, u["id"]), "rank": mine["rank"] if mine else None, "rated": rated(u)}}
