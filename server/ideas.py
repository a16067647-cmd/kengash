"""Tashabbuslar: har kim (o‘quvchilar ham) g‘oya yoki muammo yozadi, boshqalar qo‘llab-quvvatlaydi (ovoz),
eng ko‘p ovoz olganlar tepaga chiqadi. Javob beradi va holatini o‘zgartiradi: admin, hududi bo‘yicha xodim
(«view») va tuman Lideri. Muallifga javob haqida xabar boradi.

Инициативы: любой (и ученики) пишет идею или проблему, другие поддерживают (голос), популярные поднимаются вверх.
Отвечают и меняют статус: админ, сотрудник территории («view») и Лидер района. Автор получает уведомление.
"""
from typing import Optional

from fastapi import APIRouter, Header, Request

import app as core
import db
import model
import push

router = APIRouter()
err = core.err
clean = core.clean
STATUSES = ("open", "planned", "done", "declined")


def district_of(c, u):
    """Odamning tumani (viloyat darajasi — '') / район человека (уровень области — '')."""
    if u.get("level") == "district":
        return u["place_id"]
    if u.get("level") == "school":
        s = c.one("SELECT district_id FROM schools WHERE id=?", (u["place_id"],))
        return s["district_id"] if s else ""
    return ""


def can_answer(c, u, idea):
    if u["role"] == "admin":
        return True
    if model.has_power(u, "view"):
        return u["level"] == "region" or (idea["district_id"] and u["place_id"] == idea["district_id"])
    return u.get("status") == "active" and u.get("direction") == model.LIDER and (
        u.get("level") == "region" or (u.get("level") == "district" and u["place_id"] == idea["district_id"]))


def idea_json(c, i, viewer):
    votes = c.one("SELECT COUNT(*) AS n FROM idea_votes WHERE idea_id=?", (i["id"],))["n"]
    mine = c.one("SELECT 1 AS x FROM idea_votes WHERE idea_id=? AND user_id=?", (i["id"], viewer["id"]))
    a = c.one("SELECT * FROM users WHERE id=?", (i["user_id"],))
    r = c.one("SELECT name, title FROM users WHERE id=?", (i["replied_by"],)) if i["replied_by"] else None
    dist = core.place_info(c, "district", i["district_id"]) if i["district_id"] else None
    return {"id": i["id"], "title": i["title"], "body": i["body"], "status": i["status"], "reply": i["reply"],
            "replied_by": ({"name": r["name"], "title": r["title"]} if r else None),
            "author": {"id": a["id"], "name": a["name"], "photo": core.photo_url(a), "kind": a.get("kind") or "",
                       "place": core.place_info(c, a["level"], a["place_id"]) if a.get("level") else None} if a else None,
            "district": dist, "votes": votes, "my_vote": bool(mine), "mine": i["user_id"] == viewer["id"],
            "can_answer": can_answer(c, viewer, i), "created_at": i["created_at"]}


@router.get("/api/ideas")
def ideas_list(scope: str = "mine", sort: str = "top", authorization: Optional[str] = Header(default=None)):
    """scope=mine — o‘z tumanim (viloyat darajasi uchun — hammasi) | all; sort=top | new."""
    with db.tx() as c:
        u = core.current_user(c, authorization)
        did = district_of(c, u)
        where, params = "1=1", []
        if scope == "mine" and did:
            where, params = "i.district_id=?", [did]
        order = ("votes DESC, i.created_at DESC" if sort == "top" else "i.created_at DESC")
        rows = c.q(f"SELECT i.*, (SELECT COUNT(*) FROM idea_votes v WHERE v.idea_id=i.id) AS votes FROM ideas i "
                   f"WHERE {where} AND i.status<>'declined' ORDER BY {order} LIMIT 100", params)
        if sort == "top":  # yopilganlar (done) pastda / выполненные ниже
            rows.sort(key=lambda r: r["status"] == "done")
        return {"ideas": [idea_json(c, r, u) for r in rows], "district": did}


@router.post("/api/ideas")
async def idea_create(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    title = clean(b.get("title"), 120)
    body = str(b.get("body") or "").strip()[:1000]
    if len(title) < 4:
        err(400, "bad_title")
    with db.tx() as c:
        u = core.current_user(c, authorization)
        if u.get("kind") == "staff" or u["role"] == "admin":
            err(403, "forbidden")
        if not core.rate_ok("idea:" + u["id"], 3, 86400):
            err(429, "too_many")
        iid = core.new_id()
        c.x("INSERT INTO ideas (id, user_id, district_id, title, body, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (iid, u["id"], district_of(c, u), title, body, db.now(), db.now()))
        return idea_json(c, c.one("SELECT * FROM ideas WHERE id=?", (iid,)), u)


@router.post("/api/ideas/{iid}/vote")
async def idea_vote(iid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        u = core.current_user(c, authorization)
        i = c.one("SELECT * FROM ideas WHERE id=?", (iid,))
        if not i:
            err(404, "not_found")
        if i["user_id"] == u["id"]:
            err(400, "own_idea")
        c.x("DELETE FROM idea_votes WHERE idea_id=? AND user_id=?", (iid, u["id"]))
        if b.get("vote", True):
            c.x("INSERT INTO idea_votes (idea_id, user_id) VALUES (?, ?)", (iid, u["id"]))
        return idea_json(c, i, u)


@router.post("/api/ideas/{iid}/answer")
async def idea_answer(iid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    """Holat va javob / статус и ответ: planned | done | declined | open."""
    b = await request.json()
    status = b.get("status")
    if status not in STATUSES:
        err(400, "bad_status")
    reply = str(b.get("reply") or "").strip()[:1000]
    with db.tx() as c:
        u = core.current_user(c, authorization)
        i = c.one("SELECT * FROM ideas WHERE id=?", (iid,))
        if not i:
            err(404, "not_found")
        if not can_answer(c, u, i):
            err(403, "forbidden")
        c.x("UPDATE ideas SET status=?, reply=?, replied_by=?, updated_at=? WHERE id=?",
            (status, reply, u["id"], db.now(), iid))
        out = idea_json(c, c.one("SELECT * FROM ideas WHERE id=?", (iid,)), u)
        author = i["user_id"]
    label = {"planned": "Rejalashtirildi ✅", "done": "Amalga oshirildi 🎉", "declined": "Hozircha rad etildi",
             "open": "Ko‘rib chiqilmoqda"}[status]
    push.send([author], f"💡 {i['title'][:60]}", f"{label}{' — ' + reply[:150] if reply else ''}",
              {"type": "idea", "id": iid})
    return out


@router.post("/api/ideas/{iid}/delete")
def idea_delete(iid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        i = c.one("SELECT * FROM ideas WHERE id=?", (iid,))
        if not i:
            err(404, "not_found")
        if i["user_id"] != u["id"] and u["role"] != "admin":
            err(403, "forbidden")
        c.x("DELETE FROM idea_votes WHERE idea_id=?", (iid,))
        c.x("DELETE FROM ideas WHERE id=?", (iid,))
    return {"ok": True}
