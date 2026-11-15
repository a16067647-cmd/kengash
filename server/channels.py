"""Kanallar: avtomatik va yaratilgan kanallar, xabarlar, fayllar, shikoyatlar, jonli yangilanish.
Каналы: автоматические и созданные, сообщения, файлы, жалобы, живые обновления.

Shaxsiy xabar YO‘Q — hamma muloqot kanallarda (egasining qarori).
Личных сообщений НЕТ — всё общение в каналах (решение владельца).
"""
import asyncio
import base64
import io
import json
import re
from typing import Optional

from fastapi import APIRouter, Header, Request, WebSocket, WebSocketDisconnect

import app as core
import db
import model
import push
import realtime
import storage
from core_limits import (EDIT_SECONDS, FILE_MAX, MAX_TEXT, MSG_PER_MIN, PHOTO_IN_MAX, UPLOADS_PER_HOUR, VIDEO_MAX,
                         VOICE_MAX, VOICE_SECONDS)
from model import DIRECTION_KEYS, LIDER, is_above

router = APIRouter()
err = core.err
clean = core.clean

BLOCKED_EXT = {"exe", "apk", "bat", "cmd", "com", "msi", "dmg", "jar", "sh", "ps1", "vbs", "scr", "js", "html", "htm",
               "svg", "dll", "app", "ipa", "deb", "rpm", "php", "py"}
KIND_MIME = {
    "file": ("application/pdf", "application/msword", "application/vnd.", "text/plain", "application/zip",
             "image/", "audio/", "video/"),
    "voice": ("audio/",),
    "video": ("video/",),
}
REASONS = ("insult", "inappropriate", "spam", "other")


# ------------------------------------------------------------------ avtomatik kanallar / автоканалы
def _dir_names(d):
    for k, uz, ru in model.DIRECTIONS:
        if k == d:
            return uz, ru
    return d, d


def auto_specs(c, u):
    """Foydalanuvchi a’zo bo‘lishi kerak bo‘lgan avtomatik kanallar / автоканалы пользователя.
    -> {auto_key: (title_uz, title_ru, mode, role)}"""
    out = {}
    is_admin = u["role"] == "admin"
    lvl, pid, d = u.get("level"), u.get("place_id"), u.get("direction")
    poster = is_admin or lvl == "region"
    out["all"] = ("Kengash e’lonlari", "Объявления Kengash", "announce", "admin" if poster else "member")
    if not lvl or u.get("status") != "active":
        return out if is_admin or u.get("status") == "active" else {}
    chain = model.place_chain(c, lvl, pid)
    if not chain:
        return out
    duz, dru = _dir_names(d)
    lead = "admin" if d == LIDER else "member"
    if lvl == "school":
        p = core.place_info(c, "school", pid)
        dist = core.place_info(c, "district", chain["district"])
        out[f"school:{pid}"] = (f"{p['name_uz']} jamoasi", f"Команда: {p['name_ru']}", "group", lead)
        out[f"dd:{chain['district']}:{d}"] = (f"{dist['name_uz']} · {duz}", f"{dist['name_ru']} · {dru}", "group", "member")
    elif lvl == "district":
        dist = core.place_info(c, "district", pid)
        reg = core.place_info(c, "region", chain["region"])
        out[f"dd:{pid}:{d}"] = (f"{dist['name_uz']} · {duz}", f"{dist['name_ru']} · {dru}", "group", "admin")
        out[f"dt:{pid}"] = (f"{dist['name_uz']} jamoasi", f"Команда: {dist['name_ru']}", "group", lead)
        out[f"rd:{chain['region']}:{d}"] = (f"{reg['name_uz']} · {duz}", f"{reg['name_ru']} · {dru}", "group", "member")
    elif lvl == "region":
        reg = core.place_info(c, "region", pid)
        out[f"rd:{pid}:{d}"] = (f"{reg['name_uz']} · {duz}", f"{reg['name_ru']} · {dru}", "group", "admin")
        out[f"rt:{pid}"] = (f"{reg['name_uz']} jamoasi", f"Команда: {reg['name_ru']}", "group", lead)
    return out


def _auto_channel(c, key, spec):
    ch = c.one("SELECT * FROM channels WHERE auto_key=?", (key,))
    if ch:
        return ch["id"]
    cid = core.new_id()
    c.x("INSERT INTO channels (id, kind, auto_key, title_uz, title_ru, mode, created_at) VALUES (?, 'auto', ?, ?, ?, ?, ?)",
        (cid, key, spec[0], spec[1], spec[2], db.now()))
    return cid


def sync_user(c, uid):
    """O‘rin o‘zgarganda avtomatik kanallarni moslash / синхронизировать автоканалы после смены места."""
    u = c.one("SELECT * FROM users WHERE id=?", (uid,))
    want = {}
    if u:
        for key, spec in auto_specs(c, u).items():
            want[_auto_channel(c, key, spec)] = spec[3]
    have = {r["channel_id"]: r["role"] for r in c.q(
        "SELECT cm.channel_id, cm.role FROM channel_members cm JOIN channels ch ON ch.id=cm.channel_id "
        "WHERE cm.user_id=? AND ch.kind='auto'", (uid,))}
    for cid in have:
        if cid not in want:
            c.x("DELETE FROM channel_members WHERE channel_id=? AND user_id=?", (cid, uid))
    for cid, role in want.items():
        if cid not in have:
            seq = c.one("SELECT msg_seq FROM channels WHERE id=?", (cid,))["msg_seq"]
            c.x("INSERT INTO channel_members (channel_id, user_id, role, joined_at, last_read) VALUES (?, ?, ?, ?, ?)",
                (cid, uid, role, db.now(), seq))
        elif have[cid] != role:
            c.x("UPDATE channel_members SET role=? WHERE channel_id=? AND user_id=?", (role, cid, uid))
    return set(want) != set(have)


def remove_user(c, uid):
    """Hisob o‘chirilganda: xabarlar, fayllar, a’zoliklar / при удалении аккаунта: сообщения, файлы, членства."""
    paths = []
    for m in c.q("SELECT attachments FROM messages WHERE user_id=? AND deleted=0", (uid,)):
        paths += [a.get("path") for a in json.loads(m["attachments"] or "[]") if a.get("path")]
    c.x("DELETE FROM messages WHERE user_id=?", (uid,))
    c.x("DELETE FROM channel_members WHERE user_id=?", (uid,))
    c.x("DELETE FROM reports WHERE reporter_id=?", (uid,))
    for r in c.q("SELECT photos FROM task_assignees WHERE user_id=?", (uid,)):
        paths += json.loads(r["photos"] or "[]")
    c.x("DELETE FROM task_assignees WHERE user_id=?", (uid,))
    c.x("DELETE FROM event_guests WHERE user_id=?", (uid,))
    c.x("DELETE FROM push_tokens WHERE user_id=?", (uid,))
    admin = c.one("SELECT id FROM users WHERE role='admin' AND id<>? ORDER BY created_at LIMIT 1", (uid,))
    if admin:
        c.x("UPDATE tasks SET created_by=? WHERE created_by=?", (admin["id"], uid))
        c.x("UPDATE events SET created_by=? WHERE created_by=?", (admin["id"], uid))
    for ch in c.q("SELECT id FROM channels WHERE kind='custom' AND created_by=?", (uid,)):
        if admin:
            c.x("UPDATE channels SET created_by=? WHERE id=?", (admin["id"], ch["id"]))
            if not c.one("SELECT 1 AS x FROM channel_members WHERE channel_id=? AND user_id=?", (ch["id"], admin["id"])):
                c.x("INSERT INTO channel_members (channel_id, user_id, role, joined_at) VALUES (?, ?, 'owner', ?)",
                    (ch["id"], admin["id"], db.now()))
        else:
            _delete_channel(c, ch["id"])
    return paths


def _delete_channel(c, cid):
    paths = []
    for m in c.q("SELECT attachments FROM messages WHERE channel_id=?", (cid,)):
        paths += [a.get("path") for a in json.loads(m["attachments"] or "[]") if a.get("path")]
    c.x("DELETE FROM messages WHERE channel_id=?", (cid,))
    c.x("DELETE FROM channel_members WHERE channel_id=?", (cid,))
    c.x("DELETE FROM reports WHERE channel_id=?", (cid,))
    c.x("DELETE FROM channels WHERE id=?", (cid,))
    return paths


# ------------------------------------------------------------------ auditoriya / аудитория
def can_create(u):
    return u["role"] == "admin" or (u["status"] == "active" and u.get("level") in ("district", "region"))


def can_add(c, actor, target, peers=True):
    """Kanalga qo‘sha oladimi (peers=False — faqat pastdagilar: vazifa, tadbir).
    Может ли добавить (peers=False — только нижестоящих: задачи, мероприятия)."""
    if actor["role"] == "admin":
        return True
    if not target.get("level"):
        return False
    if is_above(c, actor, target["level"], target["place_id"], target["direction"]):
        return True
    if peers and target["level"] == actor["level"]:
        a = model.place_chain(c, actor["level"], actor["place_id"]) or {}
        b = model.place_chain(c, target["level"], target["place_id"]) or {}
        return a.get("region") == b.get("region")
    return False


def resolve_audience(c, actor, items, user_ids=(), peers=True):
    """Guruh tanlovi → foydalanuvchilar (faqat ruxsat etilganlar) / выбор групп → пользователи (только разрешённые).
    item: {level, district_ids?: [..], school_ids?: [..], directions?: [..]}"""
    found = {}
    for it in items or []:
        level = it.get("level")
        if level not in model.LEVELS:
            err(400, "bad_audience")
        where, params = ["u.level=?", "u.status='active'"], [level]
        dirs = [d for d in (it.get("directions") or []) if d in DIRECTION_KEYS]
        if dirs:
            where.append("u.direction IN (%s)" % ",".join("?" * len(dirs)))
            params += dirs
        sids = [str(x) for x in (it.get("school_ids") or [])][:500]
        dids = [str(x) for x in (it.get("district_ids") or [])][:50]
        if level == "school" and sids:
            where.append("u.place_id IN (%s)" % ",".join("?" * len(sids)))
            params += sids
        elif level == "school" and dids:
            where.append("u.place_id IN (SELECT id FROM schools WHERE district_id IN (%s))" % ",".join("?" * len(dids)))
            params += dids
        elif level == "district" and dids:
            where.append("u.place_id IN (%s)" % ",".join("?" * len(dids)))
            params += dids
        for u in c.q(f"SELECT u.* FROM users u WHERE {' AND '.join(where)} LIMIT 5000", params):
            if can_add(c, actor, u, peers):
                found[u["id"]] = u
    for uid in list(user_ids or [])[:200]:
        u = c.one("SELECT * FROM users WHERE id=? AND status='active'", (str(uid),))
        if u and can_add(c, actor, u, peers):
            found[u["id"]] = u
    found.pop(actor["id"], None)
    return list(found.values())


# ------------------------------------------------------------------ yordamchilar / помощники
def member(c, cid, uid):
    return c.one("SELECT * FROM channel_members WHERE channel_id=? AND user_id=?", (cid, uid))


def access(c, cid, u, write=False):
    """Kanal + a’zolik (admin hamma kanalni ko‘ra oladi) / канал + членство (админ видит все каналы)."""
    ch = c.one("SELECT * FROM channels WHERE id=?", (cid,))
    if not ch:
        err(404, "not_found")
    m = member(c, cid, u["id"])
    if not m and u["role"] != "admin":
        err(403, "forbidden")
    return ch, m


def is_mod(ch, m, u):
    return u["role"] == "admin" or (m is not None and m["role"] in ("owner", "admin"))


def can_post(ch, m, u):
    if u["role"] == "admin":
        return True
    if m is None:
        return False
    return ch["mode"] == "group" or m["role"] in ("owner", "admin") or u["role"] == "admin"


def member_ids(c, cid):
    return [r["user_id"] for r in c.q("SELECT user_id FROM channel_members WHERE channel_id=?", (cid,))]


def channel_json(c, ch, u, m):
    last = c.one("SELECT * FROM messages WHERE channel_id=? AND seq=?", (ch["id"], ch["msg_seq"])) if ch["msg_seq"] else None
    preview = None
    if last:
        author = c.one("SELECT name FROM users WHERE id=?", (last["user_id"],)) if last["user_id"] else None
        atts = json.loads(last["attachments"] or "[]")
        preview = {"text": "" if last["deleted"] else last["text"][:120], "deleted": bool(last["deleted"]),
                   "kind": atts[0]["kind"] if atts and not last["deleted"] else "", "user_name": author["name"] if author else "",
                   "user_id": last["user_id"], "created_at": last["created_at"]}
    count = c.one("SELECT COUNT(*) AS n FROM channel_members WHERE channel_id=?", (ch["id"],))["n"]
    return {
        "id": ch["id"], "kind": ch["kind"], "auto_key": ch["auto_key"], "title_uz": ch["title_uz"], "title_ru": ch["title_ru"],
        "description": ch["description"], "icon": ch["icon"], "mode": ch["mode"], "members": count,
        "created_by": ch["created_by"], "last_msg_at": ch["last_msg_at"], "seq": ch["msg_seq"],
        "unread": max(0, ch["msg_seq"] - (m["last_read"] if m else ch["msg_seq"])),
        "muted": bool(m and m["muted"]), "role": m["role"] if m else None, "member": m is not None,
        "can_post": can_post(ch, m, u), "can_manage": is_mod(ch, m, u) and ch["kind"] == "custom" or u["role"] == "admin",
        "is_mod": is_mod(ch, m, u), "pinned": ch["pinned_msg"], "last": preview,
    }


def _mini_user(c, uid, cache):
    if not uid:
        return None
    if uid not in cache:
        u = c.one("SELECT * FROM users WHERE id=?", (uid,))
        cache[uid] = u and {"id": u["id"], "name": u["name"], "photo": core.photo_url(u), "direction": u["direction"],
                            "level": u["level"], "role": u["role"], "tg_username": u["tg_username"]}
    return cache[uid]


def messages_json(c, rows, sign=True):
    cache, out, paths = {}, [], []
    for r in rows:
        atts = [] if r["deleted"] else json.loads(r["attachments"] or "[]")
        paths += [a["path"] for a in atts if a.get("path")]
        reply = None
        if r["reply_to"]:
            p = c.one("SELECT id, user_id, text, attachments, deleted FROM messages WHERE id=?", (r["reply_to"],))
            if p:
                pa = json.loads(p["attachments"] or "[]")
                reply = {"id": p["id"], "text": "" if p["deleted"] else p["text"][:140], "deleted": bool(p["deleted"]),
                         "kind": pa[0]["kind"] if pa and not p["deleted"] else "",
                         "user": _mini_user(c, p["user_id"], cache)}
        out.append({"id": r["id"], "channel_id": r["channel_id"], "seq": r["seq"], "created_at": r["created_at"],
                    "user": _mini_user(c, r["user_id"], cache), "text": "" if r["deleted"] else r["text"],
                    "attachments": atts, "reply": reply, "edited": bool(r["edited_at"]), "deleted": bool(r["deleted"])})
    if sign and paths and storage.enabled():
        try:
            urls = storage.sign(paths)
        except Exception:
            urls = {}
        for m in out:
            for a in m["attachments"]:
                a["url"] = urls.get(a.get("path"), "")
    return out


def _msg_event(c, kind, row):
    return {"type": kind, "channel_id": row["channel_id"], "message": messages_json(c, [row], sign=False)[0]}


# ------------------------------------------------------------------ kanallar / каналы
@router.get("/api/channels")
def channels_list(authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        sync_user(c, u["id"])
        rows = c.q("SELECT ch.*, cm.role AS m_role FROM channels ch JOIN channel_members cm ON cm.channel_id=ch.id "
                   "WHERE cm.user_id=? ORDER BY ch.last_msg_at DESC, ch.created_at DESC", (u["id"],))
        out = []
        for ch in rows:
            out.append(channel_json(c, ch, u, member(c, ch["id"], u["id"])))
        return {"channels": out, "can_create": can_create(u)}


@router.post("/api/channels")
async def channels_create(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    title = clean(b.get("title"), 60)
    if len(title) < 2:
        err(400, "bad_title")
    mode = b.get("mode") if b.get("mode") in ("group", "announce") else None
    if not mode:
        err(400, "bad_mode")
    with db.tx() as c:
        u = core.current_user(c, authorization)
        if not can_create(u):
            err(403, "forbidden")
        if not core.rate_ok("chcreate:" + u["id"], 20, 3600):
            err(429, "too_many")
        targets = resolve_audience(c, u, b.get("audience"), b.get("user_ids"))
        cid = core.new_id()
        c.x("INSERT INTO channels (id, kind, title_uz, title_ru, description, icon, mode, created_by, created_at) "
            "VALUES (?, 'custom', ?, ?, ?, ?, ?, ?, ?)",
            (cid, title, title, clean(b.get("description"), 300), clean(b.get("icon"), 8), mode, u["id"], db.now()))
        c.x("INSERT INTO channel_members (channel_id, user_id, role, joined_at) VALUES (?, ?, 'owner', ?)",
            (cid, u["id"], db.now()))
        for t in targets:
            c.x("INSERT INTO channel_members (channel_id, user_id, role, joined_at) VALUES (?, ?, 'member', ?)",
                (cid, t["id"], db.now()))
        ch = c.one("SELECT * FROM channels WHERE id=?", (cid,))
        result = channel_json(c, ch, u, member(c, cid, u["id"]))
        ids = [t["id"] for t in targets]
    realtime.send(ids, {"type": "channels.changed"})
    return result


@router.get("/api/channels/{cid}")
def channel_get(cid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        ch, m = access(c, cid, u)
        out = channel_json(c, ch, u, m)
        if ch["pinned_msg"]:
            p = c.one("SELECT * FROM messages WHERE id=? AND deleted=0", (ch["pinned_msg"],))
            out["pinned_message"] = messages_json(c, [p])[0] if p else None
        return out


@router.get("/api/channels/{cid}/members")
def channel_members(cid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        access(c, cid, u)
        rows = c.q("SELECT u.*, cm.role AS m_role FROM channel_members cm JOIN users u ON u.id=cm.user_id "
                   "WHERE cm.channel_id=? ORDER BY CASE cm.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END, u.name "
                   "LIMIT 3000", (cid,))
        return {"members": [core.public_user(c, r, u) | {"channel_role": r["m_role"]} for r in rows]}


@router.post("/api/channels/{cid}")
async def channel_update(cid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        u = core.current_user(c, authorization)
        ch, m = access(c, cid, u)
        if ch["kind"] != "custom" or not is_mod(ch, m, u):
            err(403, "forbidden")
        title = clean(b.get("title", ch["title_uz"]), 60) or ch["title_uz"]
        mode = b.get("mode") if b.get("mode") in ("group", "announce") else ch["mode"]
        c.x("UPDATE channels SET title_uz=?, title_ru=?, description=?, icon=?, mode=? WHERE id=?",
            (title, title, clean(b.get("description", ch["description"]), 300), clean(b.get("icon", ch["icon"]), 8), mode, cid))
        ids = member_ids(c, cid)
    realtime.send(ids, {"type": "channel.update", "channel_id": cid})
    return {"ok": True}


@router.post("/api/channels/{cid}/members/add")
async def channel_add(cid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        u = core.current_user(c, authorization)
        ch, m = access(c, cid, u)
        if ch["kind"] != "custom" or not is_mod(ch, m, u):
            err(403, "forbidden")
        added = []
        for t in resolve_audience(c, u, b.get("audience"), b.get("user_ids")):
            if not member(c, cid, t["id"]):
                c.x("INSERT INTO channel_members (channel_id, user_id, role, joined_at, last_read) VALUES (?, ?, 'member', ?, ?)",
                    (cid, t["id"], db.now(), ch["msg_seq"]))
                added.append(t["id"])
    realtime.send(added, {"type": "channels.changed"})
    return {"added": len(added)}


@router.post("/api/channels/{cid}/members/remove")
async def channel_remove(cid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    uid = str(b.get("user_id") or "")
    with db.tx() as c:
        u = core.current_user(c, authorization)
        ch, m = access(c, cid, u)
        if ch["kind"] != "custom" or not is_mod(ch, m, u):
            err(403, "forbidden")
        t = member(c, cid, uid)
        if not t or t["role"] == "owner":
            err(400, "bad")
        c.x("DELETE FROM channel_members WHERE channel_id=? AND user_id=?", (cid, uid))
    realtime.send([uid], {"type": "channels.changed"})
    return {"ok": True}


@router.post("/api/channels/{cid}/leave")
def channel_leave(cid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        ch, m = access(c, cid, u)
        if ch["kind"] != "custom" or not m or m["role"] == "owner":
            err(400, "cant_leave")
        c.x("DELETE FROM channel_members WHERE channel_id=? AND user_id=?", (cid, u["id"]))
    return {"ok": True}


@router.post("/api/channels/{cid}/delete")
def channel_delete(cid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        ch, m = access(c, cid, u)
        if ch["kind"] != "custom" or not (u["role"] == "admin" or (m and m["role"] == "owner")):
            err(403, "forbidden")
        ids = member_ids(c, cid)
        paths = _delete_channel(c, cid)
    storage.remove(paths)
    realtime.send(ids, {"type": "channels.changed"})
    return {"ok": True}


@router.post("/api/channels/{cid}/mute")
async def channel_mute(cid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        u = core.current_user(c, authorization)
        ch, m = access(c, cid, u)
        if not m:
            err(400, "bad")
        c.x("UPDATE channel_members SET muted=? WHERE channel_id=? AND user_id=?", (1 if b.get("muted") else 0, cid, u["id"]))
    return {"ok": True}


@router.post("/api/channels/{cid}/read")
async def channel_read(cid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        u = core.current_user(c, authorization)
        ch, m = access(c, cid, u)
        if m:
            seq = min(int(b.get("seq") or ch["msg_seq"]), ch["msg_seq"])
            if seq > m["last_read"]:
                c.x("UPDATE channel_members SET last_read=? WHERE channel_id=? AND user_id=?", (seq, cid, u["id"]))
    return {"ok": True}


# ------------------------------------------------------------------ xabarlar / сообщения
@router.get("/api/channels/{cid}/messages")
def messages_list(cid: str, before: int = 0, limit: int = 50, authorization: Optional[str] = Header(default=None)):
    limit = max(1, min(limit, 100))
    with db.tx() as c:
        u = core.current_user(c, authorization)
        ch, m = access(c, cid, u)
        if before > 0:
            rows = c.q("SELECT * FROM messages WHERE channel_id=? AND seq<? ORDER BY seq DESC LIMIT ?", (cid, before, limit))
        else:
            rows = c.q("SELECT * FROM messages WHERE channel_id=? ORDER BY seq DESC LIMIT ?", (cid, limit))
        out = messages_json(c, rows)
        if ch["mode"] == "announce" and out:
            reads = [r["last_read"] for r in c.q("SELECT last_read FROM channel_members WHERE channel_id=?", (cid,))]
            for x in out:
                x["seen"] = sum(1 for r in reads if r >= x["seq"])
        return {"messages": out, "has_more": len(rows) == limit, "my_read": m["last_read"] if m else ch["msg_seq"]}


def _valid_attachments(c, cid, atts):
    out = []
    for a in (atts or [])[:10]:
        kind, path = a.get("kind"), str(a.get("path") or "")
        if kind not in ("photo", "file", "voice", "video") or not path.startswith(f"{cid}/") or ".." in path:
            err(400, "bad_attachment")
        size = storage.info(path) if storage.enabled() else int(a.get("size") or 0)
        if size is None:
            err(400, "bad_attachment")
        limit = {"photo": PHOTO_IN_MAX, "file": FILE_MAX, "voice": VOICE_MAX, "video": VIDEO_MAX}[kind]
        if size > limit:
            err(413, "too_large")
        item = {"kind": kind, "path": path, "name": clean(a.get("name"), 120), "size": size,
                "mime": clean(a.get("mime"), 80)}
        for k in ("duration", "w", "h"):
            if isinstance(a.get(k), (int, float)):
                item[k] = a[k]
        if kind == "voice" and item.get("duration", 0) > VOICE_SECONDS + 2:
            err(400, "too_long")
        out.append(item)
    return out


@router.post("/api/channels/{cid}/messages")
async def message_send(cid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    text = str(b.get("text") or "").strip()[:MAX_TEXT]
    with db.tx() as c:
        u = core.current_user(c, authorization)
        ch, m = access(c, cid, u)
        if not can_post(ch, m, u):
            err(403, "read_only")
        if not core.rate_ok("msg:" + u["id"], MSG_PER_MIN, 60):
            err(429, "too_many")
        atts = _valid_attachments(c, cid, b.get("attachments"))
        if not text and not atts:
            err(400, "empty")
        reply = b.get("reply_to")
        if reply and not c.one("SELECT id FROM messages WHERE id=? AND channel_id=?", (str(reply), cid)):
            reply = None
        seq = ch["msg_seq"] + 1
        c.x("UPDATE channels SET msg_seq=?, last_msg_at=? WHERE id=?", (seq, db.now(), cid))
        mid = core.new_id()
        c.x("INSERT INTO messages (id, channel_id, seq, user_id, created_at, text, reply_to, attachments) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", (mid, cid, seq, u["id"], db.now(), text, reply, json.dumps(atts)))
        c.x("UPDATE channel_members SET last_read=? WHERE channel_id=? AND user_id=?", (seq, cid, u["id"]))
        row = c.one("SELECT * FROM messages WHERE id=?", (mid,))
        result = messages_json(c, [row])[0]
        event = _msg_event(c, "message.new", row)
        ids = member_ids(c, cid)
        quiet = {r["user_id"] for r in c.q("SELECT user_id FROM channel_members WHERE channel_id=? AND muted=1", (cid,))}
    realtime.send(ids, event)
    # Push: ilova ochiq bo‘lmaganlarga / тем, у кого приложение не открыто
    targets = [x for x in ids if x != u["id"] and x not in quiet and not realtime.online(x)]
    if targets:
        kind = {"photo": "📷", "video": "🎬", "voice": "🎤", "file": "📎"}.get(atts[0]["kind"], "") if atts else ""
        push.send(targets, ch["title_uz"], f"{u['name']}: {kind} {text}".strip()[:200],
                  {"type": "message", "channel_id": cid})
    return result


def _own_message(c, mid, u, mod_ok=True):
    r = c.one("SELECT * FROM messages WHERE id=?", (mid,))
    if not r or r["deleted"]:
        err(404, "not_found")
    ch, m = access(c, r["channel_id"], u)
    mine = r["user_id"] == u["id"]
    if not mine and not (mod_ok and is_mod(ch, m, u)):
        err(403, "forbidden")
    return r, ch, m


@router.post("/api/messages/{mid}/edit")
async def message_edit(mid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    text = str(b.get("text") or "").strip()[:MAX_TEXT]
    with db.tx() as c:
        u = core.current_user(c, authorization)
        r, ch, m = _own_message(c, mid, u, mod_ok=False)
        if db.now() - r["created_at"] > EDIT_SECONDS:
            err(400, "edit_expired")
        if not text and r["attachments"] == "[]":
            err(400, "empty")
        c.x("UPDATE messages SET text=?, edited_at=? WHERE id=?", (text, db.now(), mid))
        row = c.one("SELECT * FROM messages WHERE id=?", (mid,))
        event = _msg_event(c, "message.update", row)
        ids = member_ids(c, r["channel_id"])
    realtime.send(ids, event)
    return {"ok": True}


def delete_message(c, r):
    paths = [a["path"] for a in json.loads(r["attachments"] or "[]") if a.get("path")]
    c.x("UPDATE messages SET deleted=1, text='', attachments='[]' WHERE id=?", (r["id"],))
    c.x("UPDATE channels SET pinned_msg=NULL WHERE pinned_msg=?", (r["id"],))
    row = c.one("SELECT * FROM messages WHERE id=?", (r["id"],))
    return paths, _msg_event(c, "message.update", row), member_ids(c, r["channel_id"])


@router.post("/api/messages/{mid}/delete")
def message_delete(mid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        r, ch, m = _own_message(c, mid, u)
        paths, event, ids = delete_message(c, r)
    storage.remove(paths)
    realtime.send(ids, event)
    return {"ok": True}


@router.post("/api/messages/{mid}/pin")
async def message_pin(mid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        u = core.current_user(c, authorization)
        r = c.one("SELECT * FROM messages WHERE id=? AND deleted=0", (mid,))
        if not r:
            err(404, "not_found")
        ch, m = access(c, r["channel_id"], u)
        if not is_mod(ch, m, u):
            err(403, "forbidden")
        c.x("UPDATE channels SET pinned_msg=? WHERE id=?", (mid if b.get("pin", True) else None, ch["id"]))
        ids = member_ids(c, ch["id"])
    realtime.send(ids, {"type": "channel.update", "channel_id": ch["id"]})
    return {"ok": True}


@router.post("/api/messages/{mid}/report")
async def message_report(mid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    reason = b.get("reason") if b.get("reason") in REASONS else "other"
    with db.tx() as c:
        u = core.current_user(c, authorization)
        r = c.one("SELECT * FROM messages WHERE id=? AND deleted=0", (mid,))
        if not r:
            err(404, "not_found")
        access(c, r["channel_id"], u)
        if not core.rate_ok("report:" + u["id"], 20, 3600):
            err(429, "too_many")
        if c.one("SELECT id FROM reports WHERE message_id=? AND reporter_id=?", (mid, u["id"])):
            return {"ok": True}
        c.x("INSERT INTO reports (id, message_id, channel_id, reporter_id, reason, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (core.new_id(), mid, r["channel_id"], u["id"], reason, clean(b.get("note"), 300), db.now()))
    return {"ok": True}


# ------------------------------------------------------------------ fayllar / файлы
SAFE_NAME = re.compile(r"[^A-Za-z0-9._-]+")


def _media_path(cid, name):
    import time
    base = SAFE_NAME.sub("_", name)[-60:] or "file"
    return f"{cid}/{time.strftime('%Y-%m')}/{core.new_id()}-{base}"


@router.post("/api/channels/{cid}/upload")
async def upload_url(cid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    """Fayl, ovoz, video uchun imzolangan yuklash havolasi / подписанная ссылка загрузки."""
    b = await request.json()
    kind = b.get("kind")
    name = clean(b.get("name"), 120) or "file"
    size = int(b.get("size") or 0)
    mime = clean(b.get("mime"), 80).lower()
    if kind not in KIND_MIME:
        err(400, "bad_kind")
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    if ext in BLOCKED_EXT:
        err(400, "bad_type")
    if mime and not mime.startswith(KIND_MIME[kind]):
        err(400, "bad_type")
    limit = {"file": FILE_MAX, "voice": VOICE_MAX, "video": VIDEO_MAX}[kind]
    if size <= 0 or size > limit:
        err(413, "too_large")
    if kind == "voice" and float(b.get("duration") or 0) > VOICE_SECONDS + 2:
        err(400, "too_long")
    with db.tx() as c:
        u = core.current_user(c, authorization)
        ch, m = access(c, cid, u)
        if not can_post(ch, m, u):
            err(403, "read_only")
        if not core.rate_ok("upload:" + u["id"], UPLOADS_PER_HOUR, 3600):
            err(429, "too_many")
    if not storage.enabled():
        err(503, "storage_off")
    path = _media_path(cid, name)
    return {"path": path, "upload_url": await asyncio.to_thread(storage.upload_url, path)}


def process_chat_photo(data: bytes):
    """Uzun tomoni 1600 px, JPEG, EXIF (joylashuv) yo‘q / длинная сторона 1600 px, JPEG, без EXIF."""
    from PIL import Image, ImageOps
    im = Image.open(io.BytesIO(data))
    im = ImageOps.exif_transpose(im).convert("RGB")
    im.thumbnail((1600, 1600), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, "JPEG", quality=84, optimize=True)
    return out.getvalue(), im.width, im.height


@router.post("/api/channels/{cid}/photo")
async def upload_photo(cid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    raw = str(b.get("data") or "")
    if "," in raw[:80]:
        raw = raw.split(",", 1)[1]
    with db.tx() as c:
        u = core.current_user(c, authorization)
        ch, m = access(c, cid, u)
        if not can_post(ch, m, u):
            err(403, "read_only")
        if not core.rate_ok("upload:" + u["id"], UPLOADS_PER_HOUR, 3600):
            err(429, "too_many")
    try:
        jpg, w, h = await asyncio.to_thread(process_chat_photo, base64.b64decode(raw, validate=False))
    except Exception:
        err(400, "bad_photo")
    if not storage.enabled():
        err(503, "storage_off")
    path = _media_path(cid, "photo.jpg")
    await asyncio.to_thread(storage.put, path, jpg, "image/jpeg")
    return {"kind": "photo", "path": path, "name": "photo.jpg", "size": len(jpg), "mime": "image/jpeg", "w": w, "h": h}


# ------------------------------------------------------------------ shikoyatlar (admin) / жалобы (админ)
@router.get("/api/admin/reports")
def admin_reports(status: str = "open", authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        core.need_admin(u)
        rows = c.q("SELECT * FROM reports WHERE status=? ORDER BY created_at DESC LIMIT 200",
                   ("open" if status == "open" else "done",))
        out = []
        for r in rows:
            msg = c.one("SELECT * FROM messages WHERE id=?", (r["message_id"],))
            ch = c.one("SELECT title_uz, title_ru FROM channels WHERE id=?", (r["channel_id"],))
            rep = c.one("SELECT * FROM users WHERE id=?", (r["reporter_id"],))
            out.append({"id": r["id"], "reason": r["reason"], "note": r["note"], "created_at": r["created_at"],
                        "channel_id": r["channel_id"], "channel": ch or {}, "status": r["status"],
                        "message": messages_json(c, [msg])[0] if msg else None,
                        "reporter": core.public_user(c, rep, u) if rep else None})
        return {"reports": out}


@router.post("/api/admin/reports/{rid}")
async def admin_report_action(rid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    action = b.get("action")
    if action not in ("delete", "dismiss", "block"):
        err(400, "bad")
    paths, events = [], []
    with db.tx() as c:
        u = core.current_user(c, authorization)
        core.need_admin(u)
        r = c.one("SELECT * FROM reports WHERE id=?", (rid,))
        if not r:
            err(404, "not_found")
        msg = c.one("SELECT * FROM messages WHERE id=?", (r["message_id"],))
        if action in ("delete", "block") and msg and not msg["deleted"]:
            p, ev, ids = delete_message(c, msg)
            paths += p
            events.append((ids, ev))
        if action == "block" and msg and msg["user_id"] and msg["user_id"] != u["id"]:
            c.x("UPDATE users SET status='blocked' WHERE id=?", (msg["user_id"],))
            c.x("DELETE FROM tokens WHERE user_id=?", (msg["user_id"],))
        c.x("UPDATE reports SET status='done' WHERE message_id=?", (r["message_id"],))
    storage.remove(paths)
    for ids, ev in events:
        realtime.send(ids, ev)
    return {"ok": True}


# ------------------------------------------------------------------ WebSocket
@router.websocket("/api/ws")
async def ws_endpoint(ws: WebSocket, token: str = ""):
    with db.tx() as c:
        try:
            u = core.current_user(c, "Bearer " + token)
        except Exception:
            u = None
    if not u:
        await ws.close(code=4401)
        return
    await ws.accept()
    loop = asyncio.get_running_loop()
    realtime.add(u["id"], ws, loop)
    try:
        await ws.send_text(json.dumps({"type": "hello"}))
        while True:
            msg = await ws.receive_text()
            if msg == "ping":
                await ws.send_text('{"type":"pong"}')
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        realtime.remove(u["id"], ws, loop)
