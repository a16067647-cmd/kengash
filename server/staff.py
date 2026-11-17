"""Xodimlar («Boshqa»): masalan, Asaka Kelajak Markazi direktori.
Odam botda «Boshqa» ni tanlaydi → admin Telegram’da xabar oladi → lavozimni yozadi, hudud va vakolatlarni tanlaydi.
Yoki admin ilovada raqam bo‘yicha o‘zi yaratadi: odam botga kirganda hisob tayyor bo‘ladi.

Сотрудники («Другое»): например, директор Асакинского Kelajak Markazi.
Человек выбирает «Другое» в боте → админ получает сообщение в Telegram → пишет должность, выбирает территорию
и полномочия. Или админ сам создаёт аккаунт в приложении по номеру: при входе в бот аккаунт уже готов.
"""
import re
from typing import Optional

from fastapi import APIRouter, Header, Request

import app as core
import db
import model

router = APIRouter()
err = core.err


class StaffError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


def norm_phone(p):
    digits = re.sub(r"\D", "", str(p or ""))
    if len(digits) == 9:  # 90 123 45 67 → +998...
        digits = "998" + digits
    if not 11 <= len(digits) <= 15:
        raise StaffError("bad_phone")
    return "+" + digits


def clean_powers(items):
    return ",".join(p for p in model.POWERS if p in set(items or []))


def check_area(c, level, place_id):
    if level not in model.STAFF_LEVELS or not model.place_chain(c, level, str(place_id or "")):
        raise StaffError("bad_place")


def setup(c, uid, title, level, place_id, powers):
    """Xodimni sozlash va faollashtirish / настроить и активировать сотрудника. -> (user, newly_active)"""
    u = c.one("SELECT * FROM users WHERE id=?", (uid,))
    if not u or u["role"] == "admin":
        raise StaffError("not_found")
    if u["status"] == "blocked":
        raise StaffError("blocked")
    title = core.clean(title, 80)
    if len(title) < 2:
        raise StaffError("bad_title")
    check_area(c, level, place_id)
    was = u["status"] == "active" and u.get("kind") == "staff"
    c.x("UPDATE users SET kind='staff', level=?, place_id=?, direction=NULL, class_name='', title=?, powers=?, "
        "status='active' WHERE id=?", (level, str(place_id), title, clean_powers(powers), uid))
    core.seat_changed(c, uid)
    return c.one("SELECT * FROM users WHERE id=?", (uid,)), not was


def area_name(c, u):
    p = core.place_info(c, u.get("level"), u.get("place_id")) if u.get("level") else None
    return p["name_uz"] if p else ""


POWER_LABELS = {"view": "👁 Hammasini ko‘rish / Видеть всё", "plan": "📋 Vazifa va tadbirlar / Задачи и мероприятия",
                "announce": "📣 E’lon va hisobotlar / Объявления и отчёты"}


def notify_ready(c, u):
    """Odamga Telegram’da: tasdiqlandi + lavozimi / сообщить в Telegram: подтверждено + должность."""
    import html

    import telegram
    if not u.get("tg_id"):
        return
    lines = [f"✅ <b>{html.escape(u['title'])}</b> · {html.escape(area_name(c, u))}"] + \
        [f"• {POWER_LABELS[p]}" for p in model.POWERS if p in model.powers(u)]
    telegram.send(u["tg_id"], telegram.TXT["approved"] + "\n\n" + "\n".join(lines), telegram.back_button())


def staff_json(c, u, viewer):
    return core.public_user(c, u, viewer) | {"status": u["status"], "created_at": u["created_at"],
                                            "last_seen": u["last_seen"], "linked": bool(u.get("tg_id"))}


# ------------------------------------------------------------------ API (faqat admin / только админ)
def _body(b):
    return (str(b.get("title") or ""), b.get("level"), str(b.get("place_id") or ""),
            [p for p in (b.get("powers") or []) if p in model.POWERS])


@router.get("/api/admin/staff")
def staff_list(authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        v = core.current_user(c, authorization)
        core.need_admin(v)
        rows = c.q("SELECT * FROM users WHERE kind='staff' AND status IN ('active','pending') "
                   "ORDER BY CASE status WHEN 'pending' THEN 0 ELSE 1 END, name")
        return {"staff": [staff_json(c, r, v) for r in rows]}


@router.post("/api/admin/staff")
async def staff_create(request: Request, authorization: Optional[str] = Header(default=None)):
    """Admin raqam bo‘yicha yaratadi; odam botga raqamini ulashganda shu hisobga kiradi.
    Админ создаёт по номеру; человек войдёт в этот аккаунт, когда поделится номером в боте."""
    import register as reg
    b = await request.json()
    title, level, place_id, powers = _body(b)
    with db.tx() as c:
        v = core.current_user(c, authorization)
        core.need_admin(v)
        try:
            name = reg.clean_name(b.get("name"))
            phone = norm_phone(b.get("phone"))
            check_area(c, level, place_id)
        except reg.RegError:
            err(400, "bad_name")
        except StaffError as e:
            err(400, e.code)
        same = [u for u in c.q("SELECT * FROM users WHERE phone<>''")
                if re.sub(r"\D", "", u["phone"]) == phone[1:]]
        u = same[0] if same else None
        if u and (u["role"] == "admin" or (u["status"] in ("active", "pending") and u.get("kind") != "staff")):
            err(409, "phone_taken")  # bu raqam band (koordinator, o‘quvchi…) / номер уже занят
        if not u:
            uid = core.new_id()
            c.x("INSERT INTO users (id, phone, name, role, status, created_at) VALUES (?, ?, ?, 'user', 'new', ?)",
                (uid, phone, name, db.now()))
        else:
            uid = u["id"]
            c.x("UPDATE users SET name=? WHERE id=?", (name, uid))
        try:
            u, fresh = setup(c, uid, title, level, place_id, powers)
        except StaffError as e:
            err(400, e.code)
        if fresh:
            notify_ready(c, u)
        return staff_json(c, u, v)


@router.post("/api/admin/staff/{uid}")
async def staff_edit(uid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    """Sozlash/tahrirlash (kutilayotgan arizani ham tasdiqlaydi) yoki {"remove": true} — xodimlikdan olish.
    Настроить/изменить (подтверждает и ожидающую заявку) или {"remove": true} — снять с должности."""
    b = await request.json()
    with db.tx() as c:
        v = core.current_user(c, authorization)
        core.need_admin(v)
        u = c.one("SELECT * FROM users WHERE id=? AND kind='staff'", (uid,))
        if not u:
            err(404, "not_found")
        if b.get("remove"):
            c.x("UPDATE users SET status='rejected', level=NULL, place_id=NULL, title='', powers='' WHERE id=?", (uid,))
            c.x("DELETE FROM tokens WHERE user_id=?", (uid,))
            core.seat_changed(c, uid)
            return {"ok": True}
        try:
            u, fresh = setup(c, uid, *_body(b))
        except StaffError as e:
            err(400, e.code)
        if fresh:
            notify_ready(c, u)
        return staff_json(c, u, v)
