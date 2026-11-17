"""Ro‘yxatdan o‘tish va tasdiqlash (bot ham, ilova ham shu funksiyalardan foydalanadi).
Регистрация и подтверждение (и бот, и приложение используют эти функции).
"""
import re

import db
import model
from model import DIRECTION_KEYS, MASLAHATCHI

NAME_RE = re.compile(r"^[A-Za-zА-Яа-яЁёЎўҚқҒғҲҳ‘’ʻʼ'`\-\s.]{5,60}$")


class RegError(Exception):
    def __init__(self, code, extra=None):
        super().__init__(code)
        self.code = code
        self.extra = extra or {}


def clean_name(name):
    name = re.sub(r"\s+", " ", str(name or "")).strip()
    if not NAME_RE.match(name) or len(name.split(" ")) < 2:
        raise RegError("bad_name")
    return " ".join(w[:1].upper() + w[1:] for w in name.split(" "))


def seat_for(data):
    """Ma’lumotdan o‘rin: (level, place_id, direction) / место из данных."""
    kind = data.get("kind")
    if kind == "student":
        return "school", data.get("school_id"), None
    if kind == "maslahatchi":
        return "school", data.get("school_id"), MASLAHATCHI
    if kind == "coordinator":
        lvl = data.get("level")
        d = data.get("direction")
        if d not in DIRECTION_KEYS:
            raise RegError("bad_direction")
        if lvl == "school":
            return "school", data.get("school_id"), d
        if lvl == "district":
            return "district", data.get("district_id"), d
        if lvl == "region":
            return "region", data.get("region_id") or "andijon", d
    raise RegError("bad_kind")


def seat_holder(c, level, place_id, direction, exclude=None):
    if direction is None:
        return None
    u = c.one("SELECT * FROM users WHERE level=? AND place_id=? AND direction=? AND status IN ('active','pending')",
              (level, place_id, direction))
    return u if u and u["id"] != exclude else None


def register(c, uid, data, consent_version):
    """Arizani saqlaydi. O‘quvchi darhol faol, qolganlar — tasdiq kutadi.
    Сохраняет заявку. Ученик активен сразу, остальные ждут подтверждения."""
    u = c.one("SELECT * FROM users WHERE id=?", (uid,))
    if not u:
        raise RegError("not_found")
    if u["status"] == "blocked":
        raise RegError("blocked")
    name = clean_name(data.get("name"))
    if data.get("kind") == "staff":
        # «Boshqa»: lavozim, hudud va vakolatlarni admin beradi / должность, территорию и полномочия задаёт админ
        if u["role"] == "admin":
            raise RegError("bad_kind")
        c.x("UPDATE users SET name=?, kind='staff', level=NULL, place_id=NULL, direction=NULL, class_name='', "
            "title='', powers='', status='pending', consent_version=?, consent_at=? WHERE id=?",
            (name, consent_version, db.now(), uid))
        return c.one("SELECT * FROM users WHERE id=?", (uid,))
    level, place_id, direction = seat_for(data)
    if not place_id or not model.place_chain(c, level, place_id):
        raise RegError("bad_place")
    holder = seat_holder(c, level, place_id, direction, exclude=uid)
    if holder:
        raise RegError("seat_taken", {"holder": holder})
    kind = data["kind"]
    class_name = ""
    if kind == "student":
        class_name = re.sub(r"[^0-9A-Za-zА-Яа-я\-]", "", str(data.get("class_name") or ""))[:6]
        if not re.match(r"^(1[01]?|[1-9])(-[A-ZА-Я])?$", class_name):
            raise RegError("bad_class")
    status = "active" if kind == "student" or u["role"] == "admin" else "pending"
    c.x("UPDATE users SET level=NULL, place_id=NULL, direction=NULL WHERE id=?", (uid,))
    c.x("UPDATE users SET name=?, kind=?, level=?, place_id=?, direction=?, class_name=?, status=?, "
        "consent_version=?, consent_at=? WHERE id=?",
        (name, kind, level, place_id, direction, class_name, status, consent_version, db.now(), uid))
    return c.one("SELECT * FROM users WHERE id=?", (uid,))


def decide(c, actor, uid, approve):
    """Tasdiqlash yoki rad etish / подтвердить или отклонить."""
    u = c.one("SELECT * FROM users WHERE id=?", (uid,))
    if not u or u["status"] != "pending":
        raise RegError("not_pending")
    if not model.can_approve(c, actor, u):
        raise RegError("forbidden")
    if approve and u.get("kind") == "staff":
        raise RegError("needs_setup")  # avval lavozim/hudud/vakolat / сначала должность, территория, полномочия
    if approve:
        c.x("UPDATE users SET status='active' WHERE id=?", (uid,))
    else:
        c.x("UPDATE users SET status='rejected', level=NULL, place_id=NULL, direction=NULL WHERE id=?", (uid,))
    return c.one("SELECT * FROM users WHERE id=?", (uid,))


def pending_for(c, actor):
    """Shu odam tasdiqlashi kerak bo‘lgan arizalar / заявки, которые должен подтвердить этот человек."""
    rows = c.q("SELECT * FROM users WHERE status='pending' ORDER BY created_at LIMIT 500")
    return [u for u in rows if model.can_approve(c, actor, u)]
