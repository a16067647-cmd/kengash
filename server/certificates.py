"""Chorak sertifikatlari: har tumanda eng faol 3 maktab koordinatori va viloyatda eng faol 3 tuman koordinatori.
Sertifikat — A4 (yotiq) PDF, rahbar imzosi uchun joy bilan. Admin va «view» vakolatli xodim yuklab oladi;
g‘olib o‘z sertifikatini ilovadan oladi.

Квартальные сертификаты: топ-3 школьных координатора каждого района и топ-3 районных координатора области.
Сертификат — PDF A4 (альбомный) с местом для подписи руководителя. Скачивают админ и сотрудники с «view»;
победитель получает свой сертификат в приложении.
"""
import asyncio
import datetime
import io
import os
from typing import Optional

from fastapi import APIRouter, Header, Request

import app as core
import db
import model
import storage
from model import DIRECTIONS
from rating import TZ, quarter

router = APIRouter()
err = core.err

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, "fonts")
TOP = 3
W, H = 1754, 1240  # A4 yotiq, 150 dpi / A4 альбом, 150 dpi
DIR_UZ = dict((k, uz) for k, uz, _ in DIRECTIONS)
ROMAN = ["I", "II", "III", "IV"]


def quarter_range(which="prev", now=None):
    """'prev' (o‘tgan chorak) yoki 'current' → (boshlanish, tugash, yorliq) / прошлый или текущий квартал."""
    now = now or db.now()
    start, label = quarter(now)
    if which == "current":
        d = datetime.datetime.fromtimestamp(start, TZ)
        end = int((d.replace(day=1) + datetime.timedelta(days=95)).replace(day=1).timestamp())
        return start, min(end, now + 1), label
    pstart, plabel = quarter(start - 1)
    return pstart, start, plabel


def winners(c, level, group_id, start, end):
    """Guruhdagi top-3 (ball > 0) / топ-3 группы (баллы > 0).
    level='school' → group_id = tuman; level='district' → group_id = viloyat."""
    where = ("u.place_id IN (SELECT id FROM schools WHERE district_id=?)" if level == "school"
             else "u.place_id IN (SELECT id FROM districts WHERE region_id=?)")
    rows = c.q(
        "SELECT u.*, COALESCE((SELECT SUM(p.value) FROM points p WHERE p.user_id=u.id AND p.created_at>=? "
        "AND p.created_at<?), 0) AS score "
        f"FROM users u WHERE u.level=? AND {where} AND u.status='active' AND u.kind='coordinator' "
        "ORDER BY score DESC, u.name LIMIT 20", (start, end, level, group_id))
    out, rank, prev = [], 0, None
    for i, r in enumerate(rows):
        if r["score"] <= 0:
            break
        if r["score"] != prev:
            rank, prev = i + 1, r["score"]
        if rank > TOP:
            break
        out.append((rank, int(r["score"]), r))
    return out


def groups_for(c, viewer):
    """Kim qaysi guruhlarni ko‘radi / какие группы видит: admin — hammasi; xodim — o‘z hududi."""
    if viewer["role"] == "admin" or (model.is_staff(viewer) and viewer["level"] == "region"):
        region = viewer["place_id"] if viewer["role"] != "admin" else "andijon"
        dist = c.q("SELECT id, name_uz FROM districts WHERE region_id=? AND hidden=0 ORDER BY sort, name_uz", (region,))
        return [("district", region, "Andijon viloyati · tuman koordinatorlari")] + \
            [("school", d["id"], d["name_uz"]) for d in dist]
    d = core.place_info(c, "district", viewer["place_id"])
    return [("school", viewer["place_id"], d["name_uz"] if d else "")]


def _font(weight, size):
    from PIL import ImageFont
    return ImageFont.truetype(os.path.join(FONTS, f"Manrope-{weight}.ttf"), size)


def _center(draw, y, text, font, fill):
    w = draw.textlength(text, font=font)
    draw.text(((W - w) / 2, y), text, font=font, fill=fill)


def _fit(draw, text, weight, size, max_w):
    f = _font(weight, size)
    while draw.textlength(text, font=f) > max_w and size > 30:
        size -= 4
        f = _font(weight, size)
    return f


def render(c, u, rank, score, label, group_name):
    """Bitta sahifa (Pillow rasmi) / одна страница (изображение Pillow)."""
    from PIL import Image, ImageDraw
    violet, deep, gold, ink, soft = (91, 45, 201), (58, 27, 120), (205, 160, 60), (27, 21, 48), (110, 100, 140)
    im = Image.new("RGB", (W, H), (252, 250, 245))
    d = ImageDraw.Draw(im)
    # yumshoq fon: yuqoridan och binafsha / мягкий фон
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=(int(246 + 6 * t), int(242 + 8 * t), int(252 - 7 * t)))
    # ramka: binafsha + oltin ichki chiziq / рамка
    d.rounded_rectangle((40, 40, W - 40, H - 40), radius=36, outline=violet, width=14)
    d.rounded_rectangle((74, 74, W - 74, H - 74), radius=24, outline=gold, width=4)
    # logo
    try:
        logo = Image.open(os.path.join(HERE, "assets", "logo.png")).convert("RGB").resize((120, 120))
        mask = Image.new("L", (120, 120), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, 119, 119), radius=28, fill=255)
        im.paste(logo, ((W - 120) // 2, 120), mask)
    except Exception:
        pass
    _center(d, 262, "KELAJAK O‘QUVCHILAR KENGASHI", _font(600, 34), soft)
    _center(d, 316, "SERTIFIKAT", _font(800, 120), deep)
    _center(d, 476, "Ushbu sertifikat taqdim etiladi", _font(400, 38), soft)
    name_font = _fit(d, u["name"], 800, 96, W - 320)
    _center(d, 520, u["name"], name_font, ink)
    # medal / медаль
    cx, cy, r = W // 2, 742, 64
    medal = {1: (232, 182, 40), 2: (170, 180, 192), 3: (196, 128, 64)}.get(rank, gold)
    d.ellipse((cx - r - 8, cy - r - 8, cx + r + 8, cy + r + 8), fill=(255, 255, 255), outline=medal, width=8)
    d.ellipse((cx - r + 6, cy - r + 6, cx + r - 6, cy + r - 6), fill=medal)
    f = _font(800, 70)
    tw = d.textlength(str(rank), font=f)
    d.text((cx - tw / 2, cy - 48), str(rank), font=f, fill=(255, 255, 255))
    place = core.place_info(c, u["level"], u["place_id"])
    where = place["name_uz"] if place else ""
    line1 = f"{label} chorak reytingida {rank}-o‘rin · {group_name}"
    line2 = f"{DIR_UZ.get(u['direction'], '')} yo‘nalishi · {where} · {score} ball"
    _center(d, 840, line1, _fit(d, line1, 700, 42, W - 300), ink)
    _center(d, 898, line2, _fit(d, line2, 400, 36, W - 300), soft)
    _center(d, 958, "Faol ishtirokingiz va yetakchiligingiz uchun minnatdorchilik bildiramiz!", _font(600, 32), violet)
    # imzo va sana / подпись и дата
    today = datetime.datetime.fromtimestamp(db.now(), TZ).strftime("%d.%m.%Y")
    small = _font(400, 30)
    d.line((240, 1090, 640, 1090), fill=soft, width=3)
    d.text((240, 1102), "Rahbar imzosi", font=small, fill=soft)
    d.line((W - 640, 1090, W - 240, 1090), fill=soft, width=3)
    d.text((W - 640, 1102), f"Sana: {today}", font=small, fill=soft)
    return im


def pdf_bytes(pages):
    out = io.BytesIO()
    first, rest = pages[0], pages[1:]
    first.save(out, "PDF", resolution=150, save_all=True, append_images=rest)
    return out.getvalue()


def _collect(c, viewer, which, group=None, user_id=None):
    start, end, label = quarter_range(which)
    items = []
    for level, gid, gname in groups_for(c, viewer):
        if group and gid != group:
            continue
        for rank, score, u in winners(c, level, gid, start, end):
            if user_id and u["id"] != user_id:
                continue
            items.append((u, rank, score, label, gname))
    return items, label


# ------------------------------------------------------------------ API
def _viewer(c, authorization):
    u = core.current_user(c, authorization)
    if not model.has_power(u, "view"):
        err(403, "forbidden")
    return u


@router.get("/api/certificates")
def cert_list(which: str = "prev", authorization: Optional[str] = Header(default=None)):
    """G‘oliblar ro‘yxati guruhlar bo‘yicha / победители по группам."""
    with db.tx() as c:
        v = _viewer(c, authorization)
        start, end, label = quarter_range(which)
        groups = []
        for level, gid, gname in groups_for(c, v):
            groups.append({"id": gid, "level": level, "name": gname, "winners": [
                {"rank": rank, "score": score, "user": core.public_user(c, u, v)}
                for rank, score, u in winners(c, level, gid, start, end)]})
        return {"quarter": label, "which": which, "groups": groups}


async def _upload(name, data):
    if not storage.enabled():
        err(503, "storage_off")
    path = f"exports/{name}-{core.new_id()[:8]}.pdf"
    await asyncio.to_thread(storage.put, path, data, "application/pdf")
    return (await asyncio.to_thread(storage.sign, [path], 600)).get(path, "")


@router.post("/api/certificates/pdf")
async def cert_pdf(request: Request, authorization: Optional[str] = Header(default=None)):
    """Bitta guruh yoki bitta odam uchun PDF (har sahifa — bitta sertifikat) / PDF группы или одного человека."""
    b = await request.json()
    which = "current" if b.get("which") == "current" else "prev"
    with db.tx() as c:
        v = _viewer(c, authorization)
        items, label = _collect(c, v, which, str(b.get("group") or "") or None, str(b.get("user_id") or "") or None)
        if not items:
            err(404, "no_winners")
        pages = [render(c, *it) for it in items[:TOP * 2]]
    data = await asyncio.to_thread(pdf_bytes, pages)
    return {"url": await _upload("sertifikat", data), "count": len(pages), "quarter": label}


@router.get("/api/certificates/mine")
def cert_mine(authorization: Optional[str] = Header(default=None)):
    """Koordinator: o‘tgan chorakda top-3 bo‘lsam / координатор: если я в топ-3 прошлого квартала."""
    with db.tx() as c:
        u = core.current_user(c, authorization)
        return {"certificate": _mine(c, u)}


def _mine(c, u):
    if u.get("kind") != "coordinator" or u.get("level") not in ("school", "district"):
        return None
    start, end, label = quarter_range("prev")
    if u["level"] == "school":
        s = c.one("SELECT district_id FROM schools WHERE id=?", (u["place_id"],))
        if not s:
            return None
        level, gid = "school", s["district_id"]
        gname = (core.place_info(c, "district", gid) or {}).get("name_uz", "")
    else:
        d = c.one("SELECT region_id FROM districts WHERE id=?", (u["place_id"],))
        if not d:
            return None
        level, gid, gname = "district", d["region_id"], "Andijon viloyati · tuman koordinatorlari"
    for rank, score, w in winners(c, level, gid, start, end):
        if w["id"] == u["id"]:
            return {"rank": rank, "score": score, "quarter": label, "group": gname}
    return None


@router.post("/api/certificates/mine/pdf")
async def cert_mine_pdf(authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        u = core.current_user(c, authorization)
        m = _mine(c, u)
        if not m:
            err(404, "no_winners")
        page = render(c, u, m["rank"], m["score"], m["quarter"], m["group"])
    data = await asyncio.to_thread(pdf_bytes, [page])
    return {"url": await _upload("sertifikat", data)}


def notify_winners(now=None):
    """Chorak boshida (1-kun, 9:00 dan keyin) g‘oliblarni bot orqali tabriklash, bir marta.
    В начале квартала (1-й день, после 9:00) поздравить победителей в боте, один раз."""
    import push
    import telegram
    now = now or db.now()
    qstart, _ = quarter(now)
    d = datetime.datetime.fromtimestamp(now, TZ)
    if now - qstart > 86400 or d.hour < 9:
        return 0
    start, end, label = quarter_range("prev", now)
    out = []
    with db.tx() as c:
        groups = [("district", "andijon", "Andijon viloyati · tuman koordinatorlari")] + [
            ("school", r["id"], r["name_uz"]) for r in c.q("SELECT id, name_uz FROM districts WHERE hidden=0")]
        for level, gid, gname in groups:
            for rank, score, u in winners(c, level, gid, start, end):
                if u.get("tg_id") and push.once(c, f"cert:{label}:{u['id']}"):
                    out.append((u["tg_id"], f"🏅 <b>Tabriklaymiz, {u['name']}!</b>\n\n{label} chorak reytingida "
                                f"<b>{rank}-o‘rin</b> — {gname} ({score} ball).\nSertifikatingizni ilovadagi «Reyting» "
                                f"bo‘limidan yuklab oling.\n\n🏅 Поздравляем! {rank}-е место за квартал. "
                                f"Сертификат — в разделе «Рейтинг»."))
    for chat, t in out:
        telegram.send(chat, t, telegram.back_button())
    return len(out)
