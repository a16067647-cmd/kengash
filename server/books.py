"""Oy kitobi: har yo‘nalish uchun bitta kitob (8 ta). Admin muqova va PDF qo‘shadi; yangisi eskisini almashtiradi.
Hamma (o‘quvchilar ham) ko‘radi va ilova ichida o‘qiydi. «O‘qidim» tugmasi va hisoblagich.
Книга месяца: по одной книге на направление (8). Админ добавляет обложку и PDF; новая заменяет старую.
Видят все (и ученики), читают внутри приложения. Кнопка «Прочитал» и счётчик.
"""
import asyncio
import base64
import io
from typing import Optional

from fastapi import APIRouter, Header, Request

import app as core
import db
import storage
from model import DIRECTION_KEYS

router = APIRouter()
err = core.err
clean = core.clean
PDF_MAX = 50 * 1024 * 1024  # Supabase bepul tarif: fayl ≤ 50 MB / бесплатный тариф: файл ≤ 50 МБ
BOOK_SIGN_SECONDS = 6 * 3600  # uzoq o‘qish uchun / для долгого чтения


COVER_HQ = 2  # muqova ishlov versiyasi / версия обработки обложки


def process_cover(data: bytes, title: str = "", author: str = ""):
    """Muqova: fon kesiladi, AI bilan tiniqlashtiriladi, 1000×1500 gacha (cover.py).
    Обложка: обрезка фона, улучшение нейросетью, до 1000×1500 (cover.py)."""
    import cover
    return cover.enhance(data, title, author)


def cover_colors(data: bytes):
    """Muqovadan 3 ta rang: asosiy (eng ko‘p), yorqin aksent, to‘q. Masalan, «Atomic Habits»: oq, oltin, to‘q.
    Aksent — yorqin piksellarning o‘rtachasi (kichik maydon bo‘lsa ham: oltin harflar).
    3 цвета обложки: основной (самый частый), яркий акцент (среднее насыщенных пикселей), тёмный."""
    import colorsys
    from PIL import Image
    im = Image.open(io.BytesIO(data)).convert("RGB")
    im.thumbnail((96, 96))
    q = im.quantize(colors=5, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()
    cols = [tuple(pal[i * 3:i * 3 + 3]) for n, i in sorted(q.getcolors() or [], reverse=True)]
    if not cols:
        return []

    def hsv(c):
        return colorsys.rgb_to_hsv(*[x / 255 for x in c])

    base = cols[0]
    deep = min(cols, key=lambda c: hsv(c)[2])
    pixels = list(im.getdata()) if not hasattr(im, "get_flattened_data") else list(im.get_flattened_data())
    vivid = [p for p in pixels if hsv(p)[1] > 0.3 and hsv(p)[2] > 0.25]
    if len(vivid) >= 0.015 * len(pixels):
        # eng ko‘p uchraydigan rang tusi atrofidagi piksellar / пиксели вокруг самого частого тона
        buckets = {}
        for p in vivid:
            buckets.setdefault(int(hsv(p)[0] * 12) % 12, []).append(p)
        bh, bs, _ = hsv(base)
        base_bucket = int(bh * 12) % 12 if bs > 0.3 else -1
        ranked = sorted(buckets.items(), key=lambda kv: -len(kv[1]))
        # fondan farqli tus bo‘lsa — o‘sha (sariq harflar ko‘k fonda) / тон, отличный от фона
        other = [v for k, v in ranked if abs(k - base_bucket) % 12 not in (0, 1, 11) and len(v) >= 0.015 * len(pixels)]
        top = other[0] if other else ranked[0][1]
        accent = tuple(sum(p[k] for p in top) // len(top) for k in range(3))
    else:
        accent = max(cols, key=lambda c: hsv(c)[1])
    return ["#%02x%02x%02x" % c for c in (base, accent, deep)]


def _ensure_cover(c, b):
    """Eski kitoblar uchun bir marta: muqovani yaxshilash va ranglarni hisoblash.
    Один раз для старых книг: улучшить обложку и вычислить цвета."""
    if ((b.get("cover_hq") or 0) >= COVER_HQ and b.get("colors")) or not storage.enabled():
        return b
    try:
        data = storage.get(b["cover_path"])
        path = b["cover_path"]
        if (b.get("cover_hq") or 0) < COVER_HQ:
            data = process_cover(data, b["title"], b.get("author") or "")
            path = f"books/{core.new_id()}-cover.jpg"
            storage.put(path, data, "image/jpeg")
        cols = ",".join(cover_colors(data))
    except Exception:
        return b
    c.x("UPDATE books SET cover_path=?, cover_hq=?, colors=? WHERE id=?", (path, COVER_HQ, cols, b["id"]))
    if path != b["cover_path"]:
        try:
            storage.remove([b["cover_path"]])
        except Exception:
            pass
    return {**b, "cover_path": path, "cover_hq": COVER_HQ, "colors": cols}


def _readers(c, bid, limit=6):
    rows = c.q("SELECT u.id, u.name, u.photo_ver FROM book_reads r JOIN users u ON u.id=r.user_id "
               "WHERE r.book_id=? ORDER BY r.at DESC LIMIT ?", (bid, limit))
    return [{"id": r["id"], "name": r["name"], "photo": core.photo_url(r)} for r in rows]


def _json(c, b, viewer, urls):
    n = c.one("SELECT COUNT(*) AS n FROM book_reads WHERE book_id=?", (b["id"],))["n"]
    mine = c.one("SELECT 1 AS x FROM book_reads WHERE book_id=? AND user_id=?", (b["id"], viewer["id"]))
    return {"id": b["id"], "direction": b["direction"], "title": b["title"], "author": b["author"],
            "description": b["description"], "month": b["month"], "pdf_size": b["pdf_size"],
            "cover_url": urls.get(b["cover_path"], ""), "pdf_url": urls.get(b["pdf_path"], ""),
            "reads": n, "my_read": bool(mine), "created_at": b["created_at"],
            "colors": [x for x in (b.get("colors") or "").split(",") if x], "readers": _readers(c, b["id"])}


@router.get("/api/books")
def books_list(authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        rows = [_ensure_cover(c, b) for b in c.q("SELECT * FROM books")]
        urls = {}
        if rows and storage.enabled():
            try:
                urls = storage.sign([p for b in rows for p in (b["cover_path"], b["pdf_path"])], BOOK_SIGN_SECONDS)
            except Exception:
                urls = {}
        order = {d: i for i, d in enumerate(DIRECTION_KEYS)}
        mine = u.get("direction")
        rows.sort(key=lambda b: (b["direction"] != mine, order.get(b["direction"], 99)))
        return {"books": [_json(c, b, u, urls) for b in rows]}


@router.post("/api/books/{bid}/read")
async def book_read(bid: str, request: Request, authorization: Optional[str] = Header(default=None)):
    b = await request.json()
    with db.tx() as c:
        u = core.current_user(c, authorization)
        if not c.one("SELECT id FROM books WHERE id=?", (bid,)):
            err(404, "not_found")
        c.x("DELETE FROM book_reads WHERE book_id=? AND user_id=?", (bid, u["id"]))
        if b.get("read", True):
            c.x("INSERT INTO book_reads (book_id, user_id, at) VALUES (?, ?, ?)", (bid, u["id"], db.now()))
        n = c.one("SELECT COUNT(*) AS n FROM book_reads WHERE book_id=?", (bid,))["n"]
    return {"ok": True, "reads": n, "my_read": bool(b.get("read", True))}


# ------------------------------------------------------------------ admin
@router.post("/api/admin/books/upload")
async def book_upload_url(request: Request, authorization: Optional[str] = Header(default=None)):
    """PDF uchun imzolangan yuklash havolasi / подписанная ссылка для загрузки PDF."""
    b = await request.json()
    size = int(b.get("size") or 0)
    with db.tx() as c:
        core.need_admin(core.current_user(c, authorization))
    if size <= 0 or size > PDF_MAX:
        err(413, "too_large")
    if not storage.enabled():
        err(503, "storage_off")
    path = f"books/{core.new_id()}.pdf"
    return {"path": path, "upload_url": await asyncio.to_thread(storage.upload_url, path)}


@router.post("/api/admin/books")
async def book_save(request: Request, authorization: Optional[str] = Header(default=None)):
    """Kitob qo‘shish/almashtirish (yo‘nalish bo‘yicha bitta) / добавить или заменить (одна на направление)."""
    b = await request.json()
    direction = b.get("direction")
    if direction not in DIRECTION_KEYS:
        err(400, "bad_direction")
    title = clean(b.get("title"), 120)
    if len(title) < 2:
        err(400, "bad_title")
    pdf_path = str(b.get("pdf_path") or "")
    raw = str(b.get("cover") or "")
    if "," in raw[:80]:
        raw = raw.split(",", 1)[1]
    if pdf_path and (not pdf_path.startswith("books/") or ".." in pdf_path or not pdf_path.endswith(".pdf")):
        err(400, "bad_attachment")
    with db.tx() as c:
        u = core.current_user(c, authorization)
        core.need_admin(u)
        if b.get("edit"):
            return await _edit(c, direction, title, b, raw, pdf_path)
    if not pdf_path:
        err(400, "bad_attachment")
    try:
        jpg = await asyncio.to_thread(process_cover, base64.b64decode(raw, validate=False), title,
                                    clean(b.get("author"), 120))
    except Exception:
        err(400, "bad_photo")
    size = await asyncio.to_thread(storage.info, pdf_path) if storage.enabled() else 0
    if size is None:
        err(400, "upload_failed")
    bid = core.new_id()
    colors = cover_colors(jpg)
    cover_path = f"books/{bid}-cover.jpg"
    await asyncio.to_thread(storage.put, cover_path, jpg, "image/jpeg")
    old_paths = []
    with db.tx() as c:
        old = c.one("SELECT * FROM books WHERE direction=?", (direction,))
        if old:
            old_paths = [old["cover_path"], old["pdf_path"]]
            c.x("DELETE FROM book_reads WHERE book_id=?", (old["id"],))
            c.x("DELETE FROM books WHERE direction=?", (direction,))
        c.x("INSERT INTO books (direction, id, title, author, description, month, cover_path, pdf_path, pdf_size, "
            "created_by, created_at, colors, cover_hq) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (direction, bid, title, clean(b.get("author"), 120), str(b.get("description") or "").strip()[:600],
             clean(b.get("month"), 30), cover_path, pdf_path, size or 0, u["id"], db.now(), ",".join(colors), COVER_HQ))
    storage.remove([p for p in old_paths if p])
    return {"ok": True, "id": bid}


async def _edit(c, direction, title, b, raw, pdf_path):
    """Xatoni tuzatish: id va «O‘qidim»lar saqlanadi; yangi muqova/PDF bo‘lsa — almashtiriladi.
    Исправление ошибки: id и отметки сохраняются; новая обложка/PDF заменяют старые."""
    old = c.one("SELECT * FROM books WHERE direction=?", (direction,))
    if not old:
        err(404, "not_found")
    cover_path, size, drop = old["cover_path"], old["pdf_size"], []
    if raw:
        try:
            jpg = await asyncio.to_thread(process_cover, base64.b64decode(raw, validate=False), title,
                                        clean(b.get("author"), 120))
        except Exception:
            err(400, "bad_photo")
        cover_path = f"books/{core.new_id()}-cover.jpg"
        await asyncio.to_thread(storage.put, cover_path, jpg, "image/jpeg")
        drop.append(old["cover_path"])
        c.x("UPDATE books SET colors=?, cover_hq=? WHERE direction=?", (",".join(cover_colors(jpg)), COVER_HQ, direction))
    if pdf_path:
        size = (await asyncio.to_thread(storage.info, pdf_path) if storage.enabled() else 0)
        if size is None:
            err(400, "upload_failed")
        drop.append(old["pdf_path"])
    c.x("UPDATE books SET title=?, author=?, description=?, month=?, cover_path=?, pdf_path=?, pdf_size=? WHERE direction=?",
        (title, clean(b.get("author"), 120), str(b.get("description") or "").strip()[:600], clean(b.get("month"), 30),
         cover_path, pdf_path or old["pdf_path"], size or 0, direction))
    storage.remove(drop)
    return {"ok": True, "id": old["id"]}


@router.post("/api/admin/books/{direction}/delete")
def book_delete(direction: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        core.need_admin(core.current_user(c, authorization))
        old = c.one("SELECT * FROM books WHERE direction=?", (direction,))
        if not old:
            err(404, "not_found")
        c.x("DELETE FROM book_reads WHERE book_id=?", (old["id"],))
        c.x("DELETE FROM books WHERE direction=?", (direction,))
    storage.remove([old["cover_path"], old["pdf_path"]])
    return {"ok": True}
