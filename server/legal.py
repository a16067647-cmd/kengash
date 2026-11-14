"""Ochiq huquqiy sahifalar (GitHub Pages) — matn manbai: app/assets/legal.json (ilova bilan bir xil).
Публичные правовые страницы — источник текста: app/assets/legal.json (тот же, что в приложении).

    python3 server/legal.py <papka / папка>
"""
import html
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = json.loads((ROOT / "app/assets/legal.json").read_text(encoding="utf-8"))
PAGES = ["about", "privacy", "terms", "cookies", "delete-account"]
APP = "Kengash"

OK_LOGO = """<svg viewBox="-130 -130 260 260" width="56" height="56" aria-hidden="true"><circle r="62" fill="none" stroke="#032BA5" stroke-width="20"/><g fill="#032BA5"><circle cx="70.7" cy="-70.7" r="19"/><circle cx="100" r="19"/><circle cx="70.7" cy="70.7" r="19"/><circle cy="100" r="19"/><circle cx="-70.7" cy="70.7" r="19"/><circle cx="-100" r="19"/><circle cx="-70.7" cy="-70.7" r="19"/></g><circle cy="-100" r="19" fill="#FFBB02"/></svg>"""


def href(p, lang):
    return p + ("-ru" if lang == "ru" else "") + ".html"


def linkify(text):
    t = html.escape(text)
    return t.replace("https://t.me/behruz_sk", '<a href="https://t.me/behruz_sk">https://t.me/behruz_sk</a>').replace(
        "behryzmamajon@gmail.com", '<a href="mailto:behryzmamajon@gmail.com">behryzmamajon@gmail.com</a>')


def page(p, lang):
    other = "uz" if lang == "ru" else "ru"
    title = DATA["titles"][p][lang]
    upd = ("Yangilangan" if lang == "uz" else "Обновлено") + ": " + DATA["updated"][lang]
    body = []
    for head, paras in DATA["pages"][p][lang]:
        body.append(f"<h2>{html.escape(head)}</h2>")
        for x in paras:
            if x == "[ok_logo]":
                body.append(f'<div class="ok">{OK_LOGO}<b>O‘QUVCHILAR<br>KENGASHI</b></div>')
            elif x == "[kelajak]":
                body.append('<img class="partner" src="team/kelajak.jpg" alt="Kelajak Markazlari">')
            elif x == "[team]":
                body.append('<div class="team">' + "".join(
                    f'<div class="m"><img src="team/{f}.jpg" alt="{html.escape(n)}"><b>{html.escape(n)}</b>'
                    f'<span>{html.escape(uz if lang == "uz" else ru)}</span></div>' for f, n, uz, ru in DATA["team"]) + "</div>")
            else:
                body.append(f"<p>{linkify(x.replace('{CONTACT}', DATA['contact']))}</p>")
    links = " · ".join(f'<a href="{href(q, lang)}">{html.escape(DATA["titles"][q][lang])}</a>' for q in PAGES if q != p)
    return f"""<!DOCTYPE html>
<html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#3A1B78"><title>{html.escape(title)} — {APP}</title>
<style>
:root{{--bg:#F5F3FA;--card:#fff;--text:#1A0F3D;--muted:#5F5878;--accent:#4A20B0}}
@media (prefers-color-scheme:dark){{:root{{--bg:#0A0714;--card:#141022;--text:#F4F1FA;--muted:#A9A2BE;--accent:#C3AEFF}}}}
body{{margin:0;background:var(--bg);font:16px/1.6 -apple-system,Segoe UI,Roboto,sans-serif;color:var(--text)}}
main{{max-width:720px;margin:0 auto;padding:32px 20px 60px}}
.card{{background:var(--card);border-radius:20px;padding:28px 24px;box-shadow:0 12px 30px -8px rgba(26,15,61,.10)}}
h1{{margin:0 0 4px;font-size:28px}} h2{{font-size:18px;margin:24px 0 6px}} p{{margin:6px 0}}
.muted{{color:var(--muted);font-size:14px}} a{{color:var(--accent);text-decoration:none}}
.top{{display:flex;justify-content:space-between;align-items:center;margin-bottom:16px}}
.team{{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:16px;margin:12px 0}}
.m{{text-align:center}} .m img{{width:100%;aspect-ratio:1;object-fit:cover;border-radius:18px;display:block;margin-bottom:8px}}
.m b{{display:block}} .m span{{color:var(--muted);font-size:14px}}
.partner{{width:180px;border-radius:18px;display:block;margin:12px 0}}
.ok{{display:flex;gap:12px;align-items:center;color:#032BA5;margin:10px 0;line-height:1.05}}
@media (prefers-color-scheme:dark){{.ok{{color:#fff}} .ok circle[stroke]{{stroke:#fff}} .ok g{{fill:#fff}}}}
</style></head><body><main>
<div class="top"><b>{APP}</b><a href="{href(p, other)}">{"Русский" if lang == "uz" else "O‘zbekcha"}</a></div>
<div class="card"><h1>{html.escape(title)}</h1><div class="muted">{upd}</div>
{"".join(body)}
</div><p class="muted" style="margin-top:20px">{links}</p></main></body></html>"""


if __name__ == "__main__":
    out = Path(sys.argv[1])
    (out / "team").mkdir(parents=True, exist_ok=True)
    for f in [t[0] for t in DATA["team"]] + ["kelajak"]:
        shutil.copy(ROOT / "app/assets/team" / f"{f}.jpg", out / "team" / f"{f}.jpg")
    for p in PAGES:
        for lg in ("uz", "ru"):
            (out / href(p, lg)).write_text(page(p, lg), encoding="utf-8")
    print("legal pages ->", out)
