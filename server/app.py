"""Kengash serveri / сервер Kengash (FastAPI).

Ishga tushirish / запуск:   uvicorn app:app --port 8787      (yoki / или)   python app.py

Muhit o‘zgaruvchilari / переменные окружения (Render → Environment):
    DATABASE_URL          Supabase Postgres ulanish manzili / строка подключения (bo‘lmasa SQLite / иначе SQLite)
    TELEGRAM_BOT_TOKEN    @BotFather bergan kalit / токен бота
    TELEGRAM_BOT_USERNAME bot nomi, @siz / имя бота без @
    TELEGRAM_WEBHOOK_SECRET  tasodifiy uzun satr / случайная длинная строка
    PUBLIC_URL            server manzili, masalan https://kengash-api.onrender.com
    APP_URL               sayt manzili / адрес сайта (https://a16067647-cmd.github.io/kengash/)
    ADMIN_TG_IDS          admin(lar)ning Telegram ID raqami, vergul bilan / Telegram ID админа(ов) через запятую
    DEV_LOGIN             "1" — sinov uchun Telegram’siz kirish (ishlab chiqarishda YOQMANG) / вход без Telegram только для тестов
"""

import base64
import hashlib
import io
import os
import re
import secrets
import threading
import time
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response

import db
import model
import telegram
from model import DIRECTION_KEYS, LEVELS, is_above

TOKEN_DAYS = 120
KEY_DAYS = 7
LOGIN_TTL = 600
LEGAL_VERSION = "2026-11-14"
MAX_BODY = 64_000
MAX_PHOTO_BODY = 3_000_000
ADMIN_TG_IDS = {int(x) for x in re.findall(r"\d+", os.environ.get("ADMIN_TG_IDS", ""))}
DEV_LOGIN = os.environ.get("DEV_LOGIN", "") == "1"
PAYMENTS_ENABLED = os.environ.get("PAYMENTS_ENABLED", "") == "1"

@asynccontextmanager
async def lifespan(_app):
    db.init()
    telegram.setup_webhook()
    import storage
    threading.Thread(target=storage.ensure_bucket, daemon=True).start()
    if os.environ.get("REMINDERS", "1") == "1":
        import plan
        plan.start_reminder_loop()
    yield
    db.close()


app = FastAPI(title="Kengash API", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
# Bearer token ishlatiladi (cookie yo‘q) — shuning uchun CORS * xavfsiz / токены Bearer, без cookie — CORS * безопасен
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])




@app.middleware("http")
async def _limits(request: Request, call_next):
    """Tana hajmi chegarasi / ограничение размера тела."""
    path = request.url.path
    limit = MAX_PHOTO_BODY if path == "/api/me/photo" else 15_000_000 if path.endswith("/photo") else MAX_BODY
    size = request.headers.get("content-length")
    if size and size.isdigit() and int(size) > limit:
        return JSONResponse({"error": "too_large"}, status_code=413)
    resp = await call_next(request)
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Referrer-Policy"] = "no-referrer"
    return resp


# ------------------------------------------------------------------ yordamchilar / помощники
def err(status, code):
    raise HTTPException(status_code=status, detail=code)


@app.exception_handler(HTTPException)
async def _http_err(_request, exc):
    return JSONResponse({"error": exc.detail}, status_code=exc.status_code)


def sha(s):
    return hashlib.sha256(s.encode()).hexdigest()


def new_id():
    return secrets.token_hex(8)


def clean(v, limit=80):
    return re.sub(r"\s+", " ", str(v or "")).strip()[:limit]


_hits = {}
_hits_lock = threading.Lock()


def rate_ok(key, limit, window):
    """Oddiy cheklov / простой лимит: `limit` urinish `window` soniyada."""
    t = time.time()
    with _hits_lock:
        arr = [x for x in _hits.get(key, []) if t - x < window]
        ok = len(arr) < limit
        if ok:
            arr.append(t)
        _hits[key] = arr
        if len(_hits) > 20000:
            for k in [k for k, v in _hits.items() if not v or t - v[-1] > 3600]:
                _hits.pop(k, None)
        return ok


def client_ip(request: Request):
    fwd = request.headers.get("x-forwarded-for", "")
    return (fwd.split(",")[0].strip() if fwd else "") or (request.client.host if request.client else "?")


def issue_token(c, user_id):
    token = secrets.token_urlsafe(32)
    t = db.now()
    c.x("INSERT INTO tokens (hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
        (sha(token), user_id, t, t + TOKEN_DAYS * 86400))
    return token


def current_user(c, authorization: Optional[str], allow_blocked=False):
    if not authorization or not authorization.startswith("Bearer "):
        err(401, "auth")
    row = c.one("SELECT u.* FROM tokens t JOIN users u ON u.id=t.user_id WHERE t.hash=? AND t.expires_at>?",
                (sha(authorization[7:].strip()), db.now()))
    if not row:
        err(401, "auth")
    if row["status"] == "blocked" and not allow_blocked:
        err(403, "blocked")
    if db.now() - (row["last_seen"] or 0) > 300:
        c.x("UPDATE users SET last_seen=? WHERE id=?", (db.now(), row["id"]))
    return row


def need_admin(u):
    if u["role"] != "admin":
        err(403, "forbidden")


def school_names(s):
    if s.get("name"):
        return s["name"], s["name"]
    return f"{s['number']}-maktab", f"Школа №{s['number']}"


def place_info(c, level, place_id):
    """Joy nomi / название места."""
    if not level or not place_id:
        return None
    if level == "region":
        r = c.one("SELECT * FROM regions WHERE id=?", (place_id,))
        return r and {"level": level, "id": r["id"], "name_uz": r["name_uz"], "name_ru": r["name_ru"]}
    if level == "district":
        d = c.one("SELECT * FROM districts WHERE id=?", (place_id,))
        return d and {"level": level, "id": d["id"], "name_uz": d["name_uz"], "name_ru": d["name_ru"],
                      "region_id": d["region_id"]}
    s = c.one("SELECT s.*, d.name_uz AS d_uz, d.name_ru AS d_ru FROM schools s JOIN districts d ON d.id=s.district_id "
              "WHERE s.id=?", (place_id,))
    if not s:
        return None
    uz, ru = school_names(s)
    return {"level": level, "id": s["id"], "name_uz": uz, "name_ru": ru, "district_id": s["district_id"],
            "district_uz": s["d_uz"], "district_ru": s["d_ru"]}


def photo_url(u):
    return f"/api/photo/{u['id']}/{u['photo_ver']}.jpg" if u.get("photo_ver") else ""


def public_user(c, u, viewer=None):
    """Boshqalarga ko‘rinadigan ma’lumot / что видят другие. Telefon — faqat yuqoridagilarga / телефон только вышестоящим."""
    out = {
        "id": u["id"], "name": u["name"], "tg_username": u["tg_username"], "photo": photo_url(u),
        "level": u["level"], "place_id": u["place_id"], "direction": u["direction"],
        "place": place_info(c, u["level"], u["place_id"]), "role": u["role"], "status": u["status"],
    }
    if viewer is not None and (viewer["id"] == u["id"] or (u["level"] and is_above(c, viewer, u["level"], u["place_id"], u["direction"]))
                               or viewer["role"] == "admin"):
        out["phone"] = u["phone"]
    return out


def me_json(c, u):
    out = public_user(c, u, u)
    out.update({
        "phone": u["phone"],
        "consent": u["consent_version"] == LEGAL_VERSION,
        "needs_seat": u["role"] != "admin" and not u["level"],
        "needs_profile": not u["name"] or u["consent_version"] != LEGAL_VERSION,
        "can_keys": u["role"] == "admin" or u["level"] in ("district", "region"),
        "paid_until": u["paid_until"],
        "payments": PAYMENTS_ENABLED,
        "notify_tg": bool(u.get("notify_tg", 1)),
    })
    return out


def body_seat(b):
    level, place_id, direction = b.get("level"), str(b.get("place_id") or ""), b.get("direction")
    if level not in LEVELS or direction not in DIRECTION_KEYS or not place_id:
        err(400, "bad_seat")
    return level, place_id, direction


def delete_user_everything(c, uid):
    """Qaytaradi: o‘chiriladigan fayl yo‘llari / возвращает пути файлов для удаления."""
    import channels
    paths = channels.remove_user(c, uid)
    c.x("DELETE FROM tokens WHERE user_id=?", (uid,))
    c.x("DELETE FROM photos WHERE user_id=?", (uid,))
    c.x("UPDATE invite_keys SET revoked=1 WHERE created_by=? AND used_by IS NULL", (uid,))
    c.x("DELETE FROM users WHERE id=?", (uid,))
    return paths


def seat_changed(c, uid):
    """O‘rin o‘zgardi → avtomatik kanallar / место изменилось → автоканалы."""
    import channels
    import realtime
    if channels.sync_user(c, uid):
        realtime.send([uid], {"type": "channels.changed"})


# ------------------------------------------------------------------ umumiy / общее
@app.get("/api/ping")
def ping():
    return {"ok": True, "t": db.now()}


@app.get("/api/meta")
def meta():
    with db.tx() as c:
        regions = c.q("SELECT * FROM regions ORDER BY id")
        districts = c.q("SELECT * FROM districts WHERE hidden=0 ORDER BY sort, name_uz")
    return {
        "regions": regions, "districts": districts,
        "directions": [{"id": k, "uz": uz, "ru": ru} for k, uz, ru in model.DIRECTIONS],
        "legal_version": LEGAL_VERSION, "bot": telegram.BOT_USERNAME, "payments": PAYMENTS_ENABLED,
    }


@app.get("/api/photo/{uid}/{ver}.jpg")
def photo(uid: str, ver: str):
    with db.tx() as c:
        u = c.one("SELECT photo_ver FROM users WHERE id=?", (uid,))
        p = c.one("SELECT data FROM photos WHERE user_id=?", (uid,))
    if not u or not p or u["photo_ver"] != ver:
        err(404, "not_found")
    return Response(bytes(p["data"]), media_type="image/jpeg",
                    headers={"Cache-Control": "public, max-age=31536000, immutable"})


# ------------------------------------------------------------------ Telegram orqali kirish / вход через Telegram
@app.post("/api/auth/telegram/start")
def tg_start(request: Request):
    if not rate_ok("start:" + client_ip(request), 30, 600):
        err(429, "too_many")
    rid = secrets.token_urlsafe(16)
    with db.tx() as c:
        c.x("DELETE FROM login_requests WHERE created_at<?", (db.now() - LOGIN_TTL,))
        c.x("INSERT INTO login_requests (id, created_at) VALUES (?, ?)", (rid, db.now()))
    return {"id": rid, "url": telegram.start_link(rid), "bot": telegram.BOT_USERNAME}


def finish_login(c, req):
    """Telegram tasdiqlagan so‘rovdan foydalanuvchi va kalit / пользователь и токен по подтверждённому запросу."""
    u = c.one("SELECT * FROM users WHERE tg_id=?", (req["tg_id"],))
    role = "admin" if req["tg_id"] in ADMIN_TG_IDS else None
    if u:
        c.x("UPDATE users SET tg_username=? WHERE id=?", (req["tg_username"], u["id"]))
        if req["phone"]:
            c.x("UPDATE users SET phone=? WHERE id=?", (req["phone"], u["id"]))
        if role:
            c.x("UPDATE users SET role=? WHERE id=?", (role, u["id"]))
        uid = u["id"]
    else:
        uid = new_id()
        name = clean(f"{req['first_name']} {req['last_name']}", 60)
        c.x("INSERT INTO users (id, tg_id, tg_username, phone, name, role, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (uid, req["tg_id"], req["tg_username"], req["phone"], name, role or "user", db.now()))
    token = issue_token(c, uid)
    c.x("DELETE FROM login_requests WHERE id=?", (req["id"],))
    return token, c.one("SELECT * FROM users WHERE id=?", (uid,))


@app.get("/api/auth/telegram/status")
def tg_status(id: str, request: Request):
    if not rate_ok("status:" + client_ip(request), 600, 600):
        err(429, "too_many")
    with db.tx() as c:
        req = c.one("SELECT * FROM login_requests WHERE id=?", (id,))
        if not req or db.now() - req["created_at"] > LOGIN_TTL:
            return {"status": "expired"}
        if req["status"] != "done":
            return {"status": "waiting"}
        token, u = finish_login(c, req)
        if u["status"] == "blocked":
            c.x("DELETE FROM tokens WHERE user_id=?", (u["id"],))
            return {"status": "blocked"}
        return {"status": "done", "token": token, "me": me_json(c, u)}


@app.post("/api/telegram/webhook")
async def tg_webhook(request: Request,
                     x_telegram_bot_api_secret_token: Optional[str] = Header(default=None)):
    if not telegram.WEBHOOK_SECRET or not secrets.compare_digest(x_telegram_bot_api_secret_token or "",
                                                                  telegram.WEBHOOK_SECRET):
        err(403, "forbidden")
    update = await request.json()
    telegram.handle_update(update)
    return {"ok": True}


@app.post("/api/auth/dev-login")
async def dev_login(request: Request):
    """Faqat DEV_LOGIN=1 bo‘lsa (testlar, lokal) / только при DEV_LOGIN=1."""
    if not DEV_LOGIN:
        err(404, "not_found")
    b = await request.json()
    tg_id = int(b.get("tg_id") or 0)
    if not tg_id:
        err(400, "bad")
    with db.tx() as c:
        rid = secrets.token_urlsafe(8)
        c.x("INSERT INTO login_requests (id, created_at, status, tg_id, tg_username, first_name, last_name, phone) "
            "VALUES (?, ?, 'done', ?, ?, ?, '', ?)",
            (rid, db.now(), tg_id, clean(b.get("username"), 40), clean(b.get("name"), 60), clean(b.get("phone"), 20)))
        req = c.one("SELECT * FROM login_requests WHERE id=?", (rid,))
        token, u = finish_login(c, req)
        return {"token": token, "me": me_json(c, u)}


@app.post("/api/auth/logout")
def logout(authorization: Optional[str] = Header(default=None)):
    if authorization and authorization.startswith("Bearer "):
        with db.tx() as c:
            c.x("DELETE FROM tokens WHERE hash=?", (sha(authorization[7:].strip()),))
    return {"ok": True}


# ------------------------------------------------------------------ men / я
@app.get("/api/me")
def me(authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = current_user(c, authorization)
        return me_json(c, u)


@app.post("/api/me/profile")
async def me_profile(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        u = current_user(c, authorization)
        name = clean(b.get("name"), 60)
        if len(name) < 3:
            err(400, "bad_name")
        if b.get("consent") is True:
            c.x("UPDATE users SET consent_version=?, consent_at=? WHERE id=?", (LEGAL_VERSION, db.now(), u["id"]))
        elif u["consent_version"] != LEGAL_VERSION:
            err(400, "consent")
        c.x("UPDATE users SET name=? WHERE id=?", (name, u["id"]))
        return me_json(c, c.one("SELECT * FROM users WHERE id=?", (u["id"],)))


def process_photo(data: bytes) -> bytes:
    """Kvadrat 512 px JPEG, EXIF (joylashuv) olib tashlanadi / квадрат 512 px, EXIF (геолокация) удаляется."""
    from PIL import Image, ImageOps
    im = Image.open(io.BytesIO(data))
    im = ImageOps.exif_transpose(im).convert("RGB")
    side = min(im.size)
    left, top = (im.width - side) // 2, (im.height - side) // 2
    im = im.crop((left, top, left + side, top + side)).resize((512, 512), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, "JPEG", quality=86, optimize=True)  # yangi fayl — EXIF yo‘q / новый файл — без EXIF
    return out.getvalue()


@app.post("/api/me/photo")
async def me_photo(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    raw = str(b.get("data") or "")
    if "," in raw[:80]:
        raw = raw.split(",", 1)[1]
    try:
        jpg = process_photo(base64.b64decode(raw, validate=False))
    except Exception:
        err(400, "bad_photo")
    with db.tx() as c:
        u = current_user(c, authorization)
        if not rate_ok("photo:" + u["id"], 20, 3600):
            err(429, "too_many")
        c.x("DELETE FROM photos WHERE user_id=?", (u["id"],))
        c.x("INSERT INTO photos (user_id, data) VALUES (?, ?)", (u["id"], jpg))
        c.x("UPDATE users SET photo_ver=? WHERE id=?", (secrets.token_hex(4), u["id"]))
        return me_json(c, c.one("SELECT * FROM users WHERE id=?", (u["id"],)))


@app.post("/api/me/notify")
async def me_notify(request: Request, authorization: Optional[str] = Header(default=None)):
    """Telegram orqali bildirishnomalar yoq/o‘ch / уведомления через Telegram вкл/выкл."""
    b = await request.json()
    with db.tx() as c:
        u = current_user(c, authorization)
        c.x("UPDATE users SET notify_tg=? WHERE id=?", (1 if b.get("telegram") else 0, u["id"]))
        return me_json(c, c.one("SELECT * FROM users WHERE id=?", (u["id"],)))


@app.post("/api/me/redeem-key")
async def redeem_key(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    code = re.sub(r"[^A-Z0-9]", "", str(b.get("code") or "").upper())
    with db.tx() as c:
        u = current_user(c, authorization)
        if not rate_ok("key:" + u["id"], 10, 3600):
            err(429, "too_many")
        k = c.one("SELECT * FROM invite_keys WHERE hash=?", (sha(code),))
        if not k or k["revoked"] or k["used_by"]:
            err(400, "bad_key")
        if k["expires_at"] < db.now():
            err(400, "key_expired")
        holder = c.one("SELECT id FROM users WHERE level=? AND place_id=? AND direction=?",
                       (k["level"], k["place_id"], k["direction"]))
        if holder and holder["id"] != u["id"]:
            err(409, "seat_taken")
        c.x("UPDATE users SET level=NULL, place_id=NULL, direction=NULL WHERE id=?", (u["id"],))
        c.x("UPDATE users SET level=?, place_id=?, direction=? WHERE id=?",
            (k["level"], k["place_id"], k["direction"], u["id"]))
        c.x("UPDATE invite_keys SET used_by=?, used_at=? WHERE hash=?", (u["id"], db.now(), k["hash"]))
        seat_changed(c, u["id"])
        return me_json(c, c.one("SELECT * FROM users WHERE id=?", (u["id"],)))


@app.post("/api/me/delete")
async def me_delete(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    word = re.sub(r"[\s'‘’`ʻʼ]", "", clean(b.get("confirm"), 20)).upper()
    if word not in ("OCHIRISH", "УДАЛИТЬ"):
        err(400, "confirm")
    with db.tx() as c:
        u = current_user(c, authorization, allow_blocked=True)
        paths = delete_user_everything(c, u["id"])
    import storage
    storage.remove(paths)
    return {"ok": True}


# ------------------------------------------------------------------ joylar va koordinatorlar / места и координаторы
@app.get("/api/schools")
def schools(district_id: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = current_user(c, authorization)
        hidden = "" if u["role"] == "admin" else "AND s.hidden=0"
        rows = c.q(f"SELECT s.*, (SELECT COUNT(*) FROM users x WHERE x.level='school' AND x.place_id=s.id) AS filled "
                   f"FROM schools s WHERE s.district_id=? {hidden} ORDER BY s.number, s.name", (district_id,))
    for r in rows:
        r["name_uz"], r["name_ru"] = school_names(r)
    return {"schools": rows}


@app.get("/api/seats")
def seats(level: str, place_id: str, authorization: Optional[str] = Header(default=None)):
    """Bir joyning 8 o‘rni / 8 мест одного места."""
    if level not in LEVELS:
        err(400, "bad_seat")
    with db.tx() as c:
        v = current_user(c, authorization)
        place = place_info(c, level, place_id)
        if not place:
            err(404, "not_found")
        holders = {r["direction"]: r for r in c.q("SELECT * FROM users WHERE level=? AND place_id=?", (level, place_id))}
        contacts = {r["direction"]: r["tg_username"] for r in
                    c.q("SELECT * FROM seat_contacts WHERE level=? AND place_id=?", (level, place_id))}
        out = []
        for d in DIRECTION_KEYS:
            h = holders.get(d)
            out.append({
                "direction": d, "user": public_user(c, h, v) if h else None,
                "contact": contacts.get(d, ""), "can_manage": is_above(c, v, level, place_id, d),
            })
        return {"place": place, "seats": out}


@app.get("/api/key-contacts")
def key_contacts(level: str, place_id: str, direction: str, authorization: Optional[str] = Header(default=None)):
    """Shu o‘rin uchun kalitni kim beradi / кто выдаёт ключ на это место."""
    with db.tx() as c:
        v = current_user(c, authorization)
        out = []
        for kind, x in model.holders_above(c, level, place_id, direction):
            if kind == "user":
                out.append({"kind": "user", "user": public_user(c, x, v)})
            else:
                out.append({"kind": "contact", "level": x["level"], "place": place_info(c, x["level"], x["place_id"]),
                            "direction": x["direction"], "tg_username": x["tg_username"]})
        admin = c.one("SELECT * FROM users WHERE role='admin' AND tg_username<>'' ORDER BY created_at LIMIT 1")
        taken = c.one("SELECT id FROM users WHERE level=? AND place_id=? AND direction=?", (level, place_id, direction))
        return {"contacts": out, "admin": public_user(c, admin, v) if admin else None, "taken": bool(taken)}


@app.get("/api/users/search")
def users_search(q: str = "", authorization: Optional[str] = Header(default=None)):
    q = clean(q, 40)
    with db.tx() as c:
        v = current_user(c, authorization)
        if len(q) < 2:
            return {"users": []}
        rows = c.q("SELECT * FROM users WHERE status='active' AND (LOWER(name) LIKE ? OR LOWER(tg_username) LIKE ?) "
                   "ORDER BY name LIMIT 40", (f"%{q.lower()}%", f"%{q.lower().lstrip('@')}%"))
        return {"users": [public_user(c, r, v) for r in rows]}


@app.get("/api/users/{uid}")
def user_get(uid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        v = current_user(c, authorization)
        u = c.one("SELECT * FROM users WHERE id=?", (uid,))
        if not u:
            err(404, "not_found")
        out = public_user(c, u, v)
        out["can_manage"] = bool(u["level"]) and is_above(c, v, u["level"], u["place_id"], u["direction"])
        return out


@app.post("/api/seats/free")
async def seat_free(request: Request, authorization: Optional[str] = Header(default=None)):
    """O‘rinni bo‘shatish (odam hisobi qoladi) / освободить место (аккаунт остаётся)."""
    b = await request.json()
    level, place_id, direction = body_seat(b)
    with db.tx() as c:
        v = current_user(c, authorization)
        if not is_above(c, v, level, place_id, direction):
            err(403, "forbidden")
        holder = c.one("SELECT id FROM users WHERE level=? AND place_id=? AND direction=?", (level, place_id, direction))
        c.x("UPDATE users SET level=NULL, place_id=NULL, direction=NULL WHERE level=? AND place_id=? AND direction=?",
            (level, place_id, direction))
        if holder:
            seat_changed(c, holder["id"])
    return {"ok": True}


# ------------------------------------------------------------------ kalitlar / ключи
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def new_code():
    s = "".join(secrets.choice(ALPHABET) for _ in range(8))
    return f"KNG-{s[:4]}-{s[4:]}"


@app.post("/api/keys")
async def keys_create(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    items = b.get("seats") or []
    if not isinstance(items, list) or not 1 <= len(items) <= 200:
        err(400, "bad")
    with db.tx() as c:
        v = current_user(c, authorization)
        if not rate_ok("keys:" + v["id"], 60, 3600):
            err(429, "too_many")
        out, skipped = [], []
        for it in items:
            level, place_id, direction = body_seat(it)
            if not is_above(c, v, level, place_id, direction):
                err(403, "forbidden")
            if c.one("SELECT id FROM users WHERE level=? AND place_id=? AND direction=?", (level, place_id, direction)):
                skipped.append({"level": level, "place_id": place_id, "direction": direction, "reason": "taken"})
                continue
            # eski ishlatilmagan kalitlar bekor / старые неиспользованные ключи отменяются
            c.x("UPDATE invite_keys SET revoked=1 WHERE level=? AND place_id=? AND direction=? AND used_by IS NULL",
                (level, place_id, direction))
            code = new_code()
            t = db.now()
            c.x("INSERT INTO invite_keys (hash, hint, level, place_id, direction, created_by, created_at, expires_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (sha(code.replace("-", "")), code[-4:], level, place_id, direction, v["id"], t, t + KEY_DAYS * 86400))
            out.append({"code": code, "level": level, "place_id": place_id, "direction": direction,
                        "place": place_info(c, level, place_id), "expires_at": t + KEY_DAYS * 86400})
        return {"keys": out, "skipped": skipped}


@app.get("/api/keys")
def keys_list(authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        v = current_user(c, authorization)
        where = "" if v["role"] == "admin" else "AND k.created_by=?"
        params = (db.now() - 30 * 86400,) + (() if v["role"] == "admin" else (v["id"],))
        rows = c.q(f"SELECT k.*, u.name AS used_name FROM invite_keys k LEFT JOIN users u ON u.id=k.used_by "
                   f"WHERE k.created_at>? {where} ORDER BY k.created_at DESC LIMIT 300", params)
        out = []
        for r in rows:
            state = ("used" if r["used_by"] else "revoked" if r["revoked"] else
                     "expired" if r["expires_at"] < db.now() else "active")
            out.append({"id": r["hash"][:16], "hint": r["hint"], "level": r["level"], "place_id": r["place_id"],
                        "direction": r["direction"], "place": place_info(c, r["level"], r["place_id"]),
                        "state": state, "created_at": r["created_at"], "expires_at": r["expires_at"],
                        "used_name": r["used_name"] or ""})
        return {"keys": out}


@app.post("/api/keys/{kid}/revoke")
def keys_revoke(kid: str, authorization: Optional[str] = Header(default=None)):
    if not re.fullmatch(r"[0-9a-f]{16}", kid):
        err(400, "bad")
    with db.tx() as c:
        v = current_user(c, authorization)
        k = c.one("SELECT * FROM invite_keys WHERE hash LIKE ?", (kid + "%",))
        if not k or (v["role"] != "admin" and k["created_by"] != v["id"]):
            err(404, "not_found")
        c.x("UPDATE invite_keys SET revoked=1 WHERE hash=?", (k["hash"],))
    return {"ok": True}


# ------------------------------------------------------------------ admin
@app.get("/api/admin/users")
def admin_users(q: str = "", district_id: str = "", direction: str = "", level: str = "", page: int = 0,
                authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        v = current_user(c, authorization)
        need_admin(v)
        where, params = ["1=1"], []
        if q:
            where.append("(LOWER(u.name) LIKE ? OR LOWER(u.tg_username) LIKE ? OR u.phone LIKE ?)")
            params += [f"%{q.lower()}%", f"%{q.lower().lstrip('@')}%", f"%{q}%"]
        if direction in DIRECTION_KEYS:
            where.append("u.direction=?")
            params.append(direction)
        if level == "none":
            where.append("u.level IS NULL")
        elif level in LEVELS:
            where.append("u.level=?")
            params.append(level)
        if district_id:
            where.append("((u.level='district' AND u.place_id=?) OR (u.level='school' AND u.place_id IN "
                         "(SELECT id FROM schools WHERE district_id=?)))")
            params += [district_id, district_id]
        total = c.one(f"SELECT COUNT(*) AS n FROM users u WHERE {' AND '.join(where)}", params)["n"]
        rows = c.q(f"SELECT u.* FROM users u WHERE {' AND '.join(where)} ORDER BY u.created_at DESC "
                   f"LIMIT 50 OFFSET ?", params + [max(0, page) * 50])
        return {"total": total, "users": [public_user(c, r, v) | {"created_at": r["created_at"],
                                                                   "last_seen": r["last_seen"]} for r in rows]}


@app.post("/api/admin/users/{uid}/block")
async def admin_block(uid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        v = current_user(c, authorization)
        need_admin(v)
        if uid == v["id"]:
            err(400, "self")
        blocked = bool(b.get("blocked"))
        c.x("UPDATE users SET status=? WHERE id=?", ("blocked" if blocked else "active", uid))
        if blocked:
            c.x("DELETE FROM tokens WHERE user_id=?", (uid,))
        seat_changed(c, uid)
    return {"ok": True}


@app.post("/api/admin/users/{uid}/delete")
def admin_delete(uid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        v = current_user(c, authorization)
        need_admin(v)
        if uid == v["id"]:
            err(400, "self")
        paths = delete_user_everything(c, uid)
    import storage
    storage.remove(paths)
    return {"ok": True}


@app.post("/api/admin/users/{uid}/seat")
async def admin_seat(uid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        v = current_user(c, authorization)
        need_admin(v)
        if not c.one("SELECT id FROM users WHERE id=?", (uid,)):
            err(404, "not_found")
        c.x("UPDATE users SET level=NULL, place_id=NULL, direction=NULL WHERE id=?", (uid,))
        if b.get("level"):
            level, place_id, direction = body_seat(b)
            if not model.place_chain(c, level, place_id):
                err(400, "bad_seat")
            if c.one("SELECT id FROM users WHERE level=? AND place_id=? AND direction=?", (level, place_id, direction)):
                err(409, "seat_taken")
            c.x("UPDATE users SET level=?, place_id=?, direction=? WHERE id=?", (level, place_id, direction, uid))
        seat_changed(c, uid)
    return {"ok": True}


@app.post("/api/admin/users/{uid}/free-months")
async def admin_free_months(uid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    months = int(b.get("months") or 0)
    if not 1 <= months <= 24:
        err(400, "bad")
    with db.tx() as c:
        v = current_user(c, authorization)
        need_admin(v)
        u = c.one("SELECT paid_until FROM users WHERE id=?", (uid,))
        if not u:
            err(404, "not_found")
        base = max(u["paid_until"] or 0, db.now())
        c.x("UPDATE users SET paid_until=? WHERE id=?", (base + months * 30 * 86400, uid))
    return {"ok": True}


def parse_numbers(spec):
    nums = set()
    for part in re.split(r"[,\s;]+", spec.strip()):
        if not part:
            continue
        m = re.fullmatch(r"(\d{1,3})\s*-\s*(\d{1,3})", part) or re.fullmatch(r"(\d{1,3})", part)
        if not m:
            err(400, "bad_spec")
        a = int(m.group(1))
        z = int(m.group(2)) if m.lastindex == 2 else a
        if a < 1 or z < a or z - a > 300:
            err(400, "bad_spec")
        nums.update(range(a, z + 1))
    return sorted(nums)


@app.post("/api/admin/schools/bulk")
async def admin_schools_bulk(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        v = current_user(c, authorization)
        need_admin(v)
        did = str(b.get("district_id") or "")
        if not c.one("SELECT id FROM districts WHERE id=?", (did,)):
            err(400, "bad_district")
        added = 0
        name = clean(b.get("name"), 80)
        if name and not b.get("spec"):
            c.x("INSERT INTO schools (id, district_id, number, name, created_at) VALUES (?, ?, NULL, ?, ?)",
                (new_id(), did, name, db.now()))
            return {"added": 1}
        for n in parse_numbers(str(b.get("spec") or "")):
            if c.one("SELECT id FROM schools WHERE district_id=? AND number=?", (did, n)):
                continue
            c.x("INSERT INTO schools (id, district_id, number, name, created_at) VALUES (?, ?, ?, '', ?)",
                (new_id(), did, n, db.now()))
            added += 1
        return {"added": added}


@app.post("/api/admin/schools/{sid}")
async def admin_school_edit(sid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        v = current_user(c, authorization)
        need_admin(v)
        s = c.one("SELECT * FROM schools WHERE id=?", (sid,))
        if not s:
            err(404, "not_found")
        if b.get("delete"):
            if c.one("SELECT id FROM users WHERE level='school' AND place_id=?", (sid,)):
                err(409, "has_users")
            c.x("DELETE FROM schools WHERE id=?", (sid,))
            return {"ok": True}
        num = b.get("number", s["number"])
        num = int(num) if str(num or "").isdigit() else None
        c.x("UPDATE schools SET name=?, number=?, hidden=? WHERE id=?",
            (clean(b.get("name", s["name"]), 80), num, 1 if b.get("hidden", s["hidden"]) else 0, sid))
    return {"ok": True}


@app.post("/api/admin/districts/{did}")
async def admin_district_edit(did: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        v = current_user(c, authorization)
        need_admin(v)
        d = c.one("SELECT * FROM districts WHERE id=?", (did,))
        if not d:
            err(404, "not_found")
        c.x("UPDATE districts SET name_uz=?, name_ru=?, hidden=? WHERE id=?",
            (clean(b.get("name_uz", d["name_uz"]), 60) or d["name_uz"],
             clean(b.get("name_ru", d["name_ru"]), 60) or d["name_ru"], 1 if b.get("hidden") else 0, did))
    return {"ok": True}


@app.post("/api/admin/seat-contact")
async def admin_seat_contact(request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    level, place_id, direction = body_seat(b)
    tg = re.sub(r"[^A-Za-z0-9_]", "", str(b.get("tg_username") or ""))[:40]
    with db.tx() as c:
        v = current_user(c, authorization)
        need_admin(v)
        c.x("DELETE FROM seat_contacts WHERE level=? AND place_id=? AND direction=?", (level, place_id, direction))
        if tg:
            c.x("INSERT INTO seat_contacts (level, place_id, direction, tg_username) VALUES (?, ?, ?, ?)",
                (level, place_id, direction, tg))
    return {"ok": True}


@app.get("/api/admin/stats")
def admin_stats(authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        v = current_user(c, authorization)
        need_admin(v)
        week = db.now() - 7 * 86400
        total = c.one("SELECT COUNT(*) AS n FROM users")["n"]
        seated = c.one("SELECT COUNT(*) AS n FROM users WHERE level IS NOT NULL")["n"]
        active = c.one("SELECT COUNT(*) AS n FROM users WHERE last_seen>?", (week,))["n"]
        schools = c.one("SELECT COUNT(*) AS n FROM schools WHERE hidden=0")["n"]
        by_district = c.q(
            "SELECT d.id, d.name_uz, d.name_ru, "
            "(SELECT COUNT(*) FROM users u WHERE (u.level='district' AND u.place_id=d.id) OR (u.level='school' AND "
            "u.place_id IN (SELECT id FROM schools s WHERE s.district_id=d.id))) AS users, "
            "(SELECT COUNT(*) FROM schools s WHERE s.district_id=d.id AND s.hidden=0) AS schools "
            "FROM districts d ORDER BY d.sort")
        return {"users": total, "seated": seated, "active_week": active, "schools": schools,
                "seats_total": (schools + len(by_district) + 1) * 8, "by_district": by_district}


import channels  # noqa: E402  (oxirida: app yordamchilaridan foydalanadi / в конце: использует помощники app)

app.include_router(channels.router)
import plan  # noqa: E402

app.include_router(plan.router)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8787")))
