"""«Mening yo‘lim» — portfolio: bajarilgan vazifalar (suratlar bilan), tadbirlar, sertifikatlar, o‘qilgan kitoblar,
reyting. Ilovada ko‘rinadi; egasi xohlasa — ochiq havola (universitet, grant, rezyume uchun), brauzerda PDF qilib
saqlash mumkin.

«Мой путь» — портфолио: выполненные задачи (с фото), мероприятия, сертификаты, прочитанные книги, рейтинг.
Видно в приложении; по желанию владельца — открытая ссылка (для вуза, гранта, резюме), можно сохранить как PDF.
"""
import datetime
import html
import json
import secrets
from typing import Optional

from fastapi import APIRouter, Header
from fastapi.responses import HTMLResponse

import app as core
import db
import storage
from model import DIRECTIONS
from rating import TZ, quarter, rank_of

router = APIRouter()
err = core.err


def _base():
    import telegram
    return telegram.PUBLIC_URL or "https://kengash-api.onrender.com"

DIR_UZ = dict((k, uz) for k, uz, _ in DIRECTIONS) | {"maslahatchi": "Maslahatchi"}


def _date(ts):
    return datetime.datetime.fromtimestamp(ts, TZ).strftime("%d.%m.%Y") if ts else ""


def certificates_of(c, u, quarters=4):
    """Oxirgi choraklardagi top-3 o‘rinlar / места в топ-3 за последние кварталы."""
    import certificates
    out = []
    if u.get("kind") != "coordinator" or u.get("level") not in ("school", "district"):
        return out
    if u["level"] == "school":
        s = c.one("SELECT district_id FROM schools WHERE id=?", (u["place_id"],))
        if not s:
            return out
        level, gid = "school", s["district_id"]
        gname = (core.place_info(c, "district", gid) or {}).get("name_uz", "")
    else:
        d = c.one("SELECT region_id FROM districts WHERE id=?", (u["place_id"],))
        if not d:
            return out
        level, gid, gname = "district", d["region_id"], "Andijon viloyati"
    end, _ = quarter()
    for _ in range(quarters):
        start, label = quarter(end - 1)
        for rank, score, w in certificates.winners(c, level, gid, start, end):
            if w["id"] == u["id"]:
                out.append({"quarter": label, "rank": rank, "score": score, "group": gname})
        end = start
    return out


def build(c, u, sign=True):
    tasks = c.q("SELECT t.id, t.title, t.created_by, a.status, a.photos, a.submitted_at FROM task_assignees a "
                "JOIN tasks t ON t.id=a.task_id WHERE a.user_id=? AND a.status IN ('submitted','accepted') "
                "ORDER BY a.submitted_at DESC LIMIT 60", (u["id"],))
    events = c.q("SELECT e.id, e.title, e.place, e.starts_at FROM event_guests g JOIN events e ON e.id=g.event_id "
                 "WHERE g.user_id=? AND e.starts_at<=? AND (g.checked_at>0 OR EXISTS (SELECT 1 FROM points p "
                 "WHERE p.kind='event' AND p.ref_id=e.id AND p.user_id=g.user_id AND p.value>0)) "
                 "ORDER BY e.starts_at DESC LIMIT 60", (u["id"], db.now()))
    books = c.q("SELECT title, author, at FROM read_log WHERE user_id=? ORDER BY at DESC LIMIT 40", (u["id"],))
    total = c.one("SELECT COALESCE(SUM(value), 0) AS s FROM points WHERE user_id=?", (u["id"],))["s"]
    rank, score, group_total = rank_of(c, u)
    givers = {}
    paths = []
    items = []
    for t in tasks:
        photos = json.loads(t["photos"] or "[]")[:3]
        paths += photos
        if t["created_by"] not in givers:
            g = c.one("SELECT name FROM users WHERE id=?", (t["created_by"],))
            givers[t["created_by"]] = g["name"] if g else ""
        items.append({"id": t["id"], "title": t["title"], "by": givers[t["created_by"]], "at": t["submitted_at"],
                      "accepted": t["status"] == "accepted", "photos": photos})
    urls = {}
    if sign and paths and storage.enabled():
        try:
            urls = storage.sign(paths, 6 * 3600)
        except Exception:
            urls = {}
    for it in items:
        it["photo_urls"] = [urls.get(p, "") for p in it.pop("photos") if urls.get(p)]
    place = core.place_info(c, u["level"], u["place_id"]) if u.get("level") else None
    return {
        "user": {"id": u["id"], "name": u["name"], "photo": core.photo_url(u), "kind": u.get("kind") or "",
                 "direction": u["direction"], "title": u.get("title") or "", "class_name": u.get("class_name") or "",
                 "place": place, "since": u["created_at"]},
        "stats": {"tasks": len(items), "events": len(events), "books": len(books), "points": int(total),
                  "rank": rank, "rank_total": group_total, "quarter_score": score},
        "tasks": items, "events": [dict(e) for e in events], "books": [dict(b) for b in books],
        "certificates": certificates_of(c, u), "shared": bool(u.get("share_token")),
        "share_url": f"{_base()}/p/{u['share_token']}" if u.get("share_token") else "",
    }


# ------------------------------------------------------------------ API
@router.get("/api/portfolio/{uid}")
def portfolio(uid: str, authorization: Optional[str] = Header(default=None)):
    with db.tx() as c:
        v = core.current_user(c, authorization)
        u = c.one("SELECT * FROM users WHERE id=?", (v["id"] if uid == "me" else uid,))
        if not u or not core.visible_to(c, v, u) or u["role"] == "admin" or u.get("kind") == "staff":
            err(404, "not_found")
        out = build(c, u)
        if u["id"] != v["id"]:
            out.pop("share_url")
        return out


@router.post("/api/portfolio/share")
def portfolio_share(authorization: Optional[str] = Header(default=None), on: bool = True):
    """Ochiq havolani yoqish/o‘chirish (o‘chirilsa eski havola ishlamaydi) / включить/выключить открытую ссылку."""
    with db.tx() as c:
        u = core.current_user(c, authorization)
        token = secrets.token_urlsafe(9) if on else ""
        c.x("UPDATE users SET share_token=? WHERE id=?", (token, u["id"]))
        return {"shared": on, "share_url": f"{_base()}/p/{token}" if on else ""}


# ------------------------------------------------------------------ ochiq sahifa / открытая страница
CSS = """
*{box-sizing:border-box}body{margin:0;font-family:Manrope,-apple-system,Segoe UI,Roboto,sans-serif;background:#f6f4fb;
color:#1b1530;-webkit-font-smoothing:antialiased}.wrap{max-width:860px;margin:0 auto;padding:32px 20px 60px}
.head{display:flex;gap:20px;align-items:center;background:#fff;border-radius:24px;padding:24px;
box-shadow:0 10px 30px rgba(58,27,120,.08)}.ava{width:84px;height:84px;border-radius:50%;object-fit:cover;
background:linear-gradient(135deg,#7a4cf0,#3a1b78);color:#fff;display:flex;align-items:center;justify-content:center;
font-size:30px;font-weight:800;flex:none}h1{margin:0;font-size:28px;letter-spacing:-.5px}.sub{color:#6e648c;margin-top:4px}
.badge{display:inline-block;margin-top:10px;padding:6px 12px;border-radius:999px;background:#efe9ff;color:#5b2dc9;
font-weight:700;font-size:13px}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:18px 0}
.stat{background:#fff;border-radius:18px;padding:16px;text-align:center}.stat b{display:block;font-size:26px;color:#5b2dc9}
.stat span{color:#6e648c;font-size:13px}h2{font-size:19px;margin:28px 0 12px}.card{background:#fff;border-radius:18px;
padding:14px 16px;margin-bottom:10px}.row{display:flex;justify-content:space-between;gap:12px}.muted{color:#6e648c;
font-size:13px}.pics{display:flex;gap:8px;margin-top:10px;flex-wrap:wrap}.pics img{width:120px;height:90px;
object-fit:cover;border-radius:12px}.cert{background:linear-gradient(135deg,#fff7df,#fff);border:1px solid #f0d58a}
.foot{margin-top:36px;text-align:center;color:#8a82a6;font-size:13px}.print{position:fixed;right:18px;bottom:18px;
background:#5b2dc9;color:#fff;border:0;border-radius:999px;padding:12px 18px;font-weight:700;cursor:pointer;
box-shadow:0 8px 20px rgba(91,45,201,.35)}@media(max-width:600px){.stats{grid-template-columns:repeat(2,1fr)}
.head{flex-direction:column;text-align:center}}@media print{.print{display:none}body{background:#fff}.card,.stat,.head{box-shadow:none;border:1px solid #eee}}
"""


def _page(p):
    e = html.escape
    u, s = p["user"], p["stats"]
    initials = "".join(w[:1] for w in u["name"].split()[:2]).upper()
    ava = f'<img class="ava" src="{e(_base() + u["photo"])}">' if u["photo"] else f'<div class="ava">{e(initials)}</div>'
    place = (u["place"] or {}).get("name_uz", "")
    role = {"coordinator": f"{DIR_UZ.get(u['direction'], '')} koordinatori", "maslahatchi": "Maslahatchi",
            "student": f"O‘quvchi{' · ' + u['class_name'] + '-sinf' if u['class_name'] else ''}"}.get(u["kind"], "")
    rank = f"{s['rank']}-o‘rin / {s['rank_total']}" if s["rank"] else "—"
    parts = [f"""<!doctype html><html lang="uz"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{e(u['name'])} — Kengash portfolio</title>
<meta property="og:title" content="{e(u['name'])} — Kelajak O‘quvchilar Kengashi">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;600;800&display=swap" rel="stylesheet">
<style>{CSS}</style></head><body><div class="wrap">
<div class="head">{ava}<div><h1>{e(u['name'])}</h1><div class="sub">{e(role)} · {e(place)}</div>
<span class="badge">✓ Kelajak O‘quvchilar Kengashi · {e(_date(u['since']))} dan beri</span></div></div>
<div class="stats"><div class="stat"><b>{s['tasks']}</b><span>bajarilgan vazifa</span></div>
<div class="stat"><b>{s['events']}</b><span>tadbirda qatnashgan</span></div>
<div class="stat"><b>{s['books']}</b><span>kitob o‘qigan</span></div>
<div class="stat"><b>{e(rank)}</b><span>chorak reytingi</span></div></div>"""]
    if p["certificates"]:
        parts.append("<h2>🏅 Sertifikatlar</h2>")
        parts += [f'<div class="card cert"><b>{c["quarter"]} chorak · {c["rank"]}-o‘rin</b>'
                  f'<div class="muted">{e(c["group"])} · {c["score"]} ball</div></div>' for c in p["certificates"]]
    if p["tasks"]:
        parts.append("<h2>📋 Bajarilgan ishlar</h2>")
        for t in p["tasks"]:
            pics = "".join(f'<img src="{e(x)}" loading="lazy">' for x in t["photo_urls"])
            parts.append(f'<div class="card"><div class="row"><b>{e(t["title"])}</b><span class="muted">{_date(t["at"])}'
                         f'</span></div><div class="muted">Topshiriq beruvchi: {e(t["by"])}'
                         f'{" · ✓ qabul qilingan" if t["accepted"] else ""}</div>'
                         f'{f"<div class=pics>{pics}</div>" if pics else ""}</div>')
    if p["events"]:
        parts.append("<h2>📅 Qatnashgan tadbirlar</h2>")
        parts += [f'<div class="card"><div class="row"><b>{e(x["title"])}</b><span class="muted">{_date(x["starts_at"])}'
                  f'</span></div><div class="muted">{e(x["place"])}</div></div>' for x in p["events"]]
    if p["books"]:
        parts.append("<h2>📚 O‘qilgan kitoblar</h2>")
        parts += [f'<div class="card"><b>{e(b["title"])}</b> <span class="muted">— {e(b["author"])}</span></div>'
                  for b in p["books"]]
    parts.append(f"""<div class="foot">Ma’lumotlar Kengash ilovasidan avtomatik olingan · {_date(db.now())}<br>
Данные автоматически получены из приложения Kengash</div></div>
<button class="print" onclick="window.print()">⬇ PDF / Chop etish</button></body></html>""")
    return "".join(parts)


@router.get("/p/{token}", response_class=HTMLResponse)
def portfolio_public(token: str):
    if len(token) < 8:
        err(404, "not_found")
    with db.tx() as c:
        u = c.one("SELECT * FROM users WHERE share_token=? AND status='active'", (token,))
        if not u:
            return HTMLResponse("<h1 style='font-family:sans-serif;text-align:center;margin-top:20vh'>Havola o‘chirilgan "
                                "/ Ссылка отключена</h1>", status_code=404)
        page = _page(build(c, u))
    # sahifa — umumiy, lekin indekslanmasin / страница общая, но без индексации
    return HTMLResponse(page, headers={"X-Robots-Tag": "noindex", "Cache-Control": "no-store",
                                       "Content-Security-Policy": "default-src 'none'; img-src * data:; "
                                       "style-src 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; "
                                       "script-src 'unsafe-inline'; frame-ancestors 'none'"})
