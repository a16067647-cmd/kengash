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


def process_cover(data: bytes):
    """Muqova: 600×900 gacha, JPEG, EXIF yo‘q / обложка: до 600×900, JPEG, без EXIF."""
    from PIL import Image, ImageOps
    im = Image.open(io.BytesIO(data))
    im = ImageOps.exif_transpose(im).convert("RGB")
    im.thumbnail((600, 900), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, "JPEG", quality=86, optimize=True)
    return out.getvalue()


def _json(c, b, viewer, urls):
    n = c.one("SELECT COUNT(*) AS n FROM book_reads WHERE book_id=?", (b["id"],))["n"]
    mine = c.one("SELECT 1 AS x FROM book_reads WHERE book_id=? AND user_id=?", (b["id"], viewer["id"]))
    return {"id": b["id"], "direction": b["direction"], "title": b["title"], "author": b["author"],
            "description": b["description"], "month": b["month"], "pdf_size": b["pdf_size"],
            "cover_url": urls.get(b["cover_path"], ""), "pdf_url": urls.get(b["pdf_path"], ""),
            "reads": n, "my_read": bool(mine), "created_at": b["created_at"]}


@router.get("/api/books")
def books_list(authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        rows = c.q("SELECT * FROM books")
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
        jpg = await asyncio.to_thread(process_cover, base64.b64decode(raw, validate=False))
    except Exception:
        err(400, "bad_photo")
    size = await asyncio.to_thread(storage.info, pdf_path) if storage.enabled() else 0
    if size is None:
        err(400, "upload_failed")
    bid = core.new_id()
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
            "created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (direction, bid, title, clean(b.get("author"), 120), str(b.get("description") or "").strip()[:600],
             clean(b.get("month"), 30), cover_path, pdf_path, size or 0, u["id"], db.now()))
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
            jpg = await asyncio.to_thread(process_cover, base64.b64decode(raw, validate=False))
        except Exception:
            err(400, "bad_photo")
        cover_path = f"books/{core.new_id()}-cover.jpg"
        await asyncio.to_thread(storage.put, cover_path, jpg, "image/jpeg")
        drop.append(old["cover_path"])
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
