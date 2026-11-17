"""QR davomat: tashkilotchi ekranida QR (har daqiqada yangilanadi) va 6 xonali kod; mehmon skanerlaydi yoki kodni yozadi
→ «keldi» belgilanadi va reytingga +1 (koordinatorlar uchun) avtomatik qo‘shiladi.

QR-посещаемость: у организатора на экране QR (меняется каждую минуту) и 6-значный код; гость сканирует или вводит код
→ отмечается «пришёл» и автоматически +1 в рейтинг (для координаторов).
Kod har daqiqada o‘zgaradi: rasmini Telegram’da yuborib, uyda turib «kelish» qiyin.
"""
import hashlib
import hmac
import secrets
from typing import Optional

from fastapi import APIRouter, Header, Request

import app as core
import db

router = APIRouter()
err = core.err

STEP = 60  # soniya / секунд
OPEN_BEFORE = 3600  # boshlanishidan 1 soat oldin ochiladi / открывается за час до начала
DEFAULT_LEN = 4 * 3600  # tugash vaqti bo‘lmasa — 4 soat / если нет конца — 4 часа
SITE = "https://a16067647-cmd.github.io/kengash/"


def _key(c, e):
    if e.get("checkin_key"):
        return e["checkin_key"]
    k = secrets.token_hex(16)
    c.x("UPDATE events SET checkin_key=? WHERE id=?", (k, e["id"]))
    return k


def code_at(key, window):
    d = hmac.new(key.encode(), str(window).encode(), hashlib.sha256).hexdigest()
    return f"{int(d[:10], 16) % 1_000_000:06d}"


def is_open(e, now=None):
    now = now or db.now()
    end = e["ends_at"] or e["starts_at"] + DEFAULT_LEN
    return e["starts_at"] - OPEN_BEFORE <= now <= end


def _organizer(e, u):
    return e["created_by"] == u["id"] or u["role"] == "admin"


@router.get("/api/events/{eid}/qr")
def event_qr(eid: str, authorization: Optional[str] = Header(default=None)):
    """Tashkilotchi uchun: joriy kod, QR matni va nechta odam keldi / для организатора: код, текст QR, сколько пришло."""
    with db.tx() as c:
        u = core.current_user(c, authorization)
        e = c.one("SELECT * FROM events WHERE id=?", (eid,))
        if not e:
            err(404, "not_found")
        if not _organizer(e, u):
            err(403, "forbidden")
        now = db.now()
        window = now // STEP
        code = code_at(_key(c, e), window)
        came = c.one("SELECT COUNT(*) AS n FROM event_guests WHERE event_id=? AND checked_at>0", (eid,))["n"]
        total = c.one("SELECT COUNT(*) AS n FROM event_guests WHERE event_id=?", (eid,))["n"]
        return {"code": code, "qr": f"{SITE}?checkin={eid}&code={code}", "expires_in": STEP - now % STEP,
                "open": is_open(e, now), "opens_at": e["starts_at"] - OPEN_BEFORE, "came": came, "total": total}


@router.post("/api/events/{eid}/checkin")
async def event_checkin(eid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    """Mehmon: kod to‘g‘ri bo‘lsa — keldi (+1) / гость: если код верный — пришёл (+1)."""
    import rating
    b = await request.json()
    code = "".join(ch for ch in str(b.get("code") or "") if ch.isdigit())[:6]
    with db.tx() as c:
        u = core.current_user(c, authorization)
        if not core.rate_ok("checkin:" + u["id"], 20, 600):
            err(429, "too_many")
        e = c.one("SELECT * FROM events WHERE id=?", (eid,))
        if not e:
            err(404, "not_found")
        g = c.one("SELECT * FROM event_guests WHERE event_id=? AND user_id=?", (eid, u["id"]))
        if not g:
            err(403, "not_invited")
        now = db.now()
        if not is_open(e, now):
            err(400, "checkin_closed")
        key = _key(c, e)
        w = now // STEP
        # joriy yoki oldingi daqiqa kodi (skanerlash chegarada bo‘lsa) / код текущей или прошлой минуты
        if len(code) != 6 or not any(hmac.compare_digest(code, code_at(key, x)) for x in (w, w - 1)):
            err(400, "bad_code")
        if g["checked_at"]:
            return {"ok": True, "already": True, "title": e["title"]}
        c.x("UPDATE event_guests SET checked_at=?, rsvp='yes' WHERE event_id=? AND user_id=?", (now, eid, u["id"]))
        if rating.rated(u):
            rating.set_point(c, "event", eid, u["id"], e["created_by"], 1)
    return {"ok": True, "already": False, "title": e["title"]}
