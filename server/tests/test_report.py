"""Oylik hisobot / ежемесячный отчёт."""
import datetime

import app  # noqa: F401  (avval server, keyin modullar / сначала сервер)

import db
import report
import telegram
from rating import TZ

from test_api import client, login  # noqa: F401
from test_plan import w, uid, make_task  # noqa: F401


def test_monthly_report(client, w, monkeypatch):  # noqa: F811
    sent = []
    monkeypatch.setattr(telegram, "api", lambda m, p: sent.append((m, p)))
    admin = w["admin"]
    # xodim (view) — Paxtaobod / сотрудник (view) — Пахтаабад
    s = client.post("/api/admin/staff", json={"name": "Hisobot Rahbar", "phone": "+998935559911", "title": "Direktor",
                                              "level": "district", "place_id": "paxtaobod", "powers": ["view"]},
                    headers=admin).json()
    with db.tx() as c:
        c.x("UPDATE users SET tg_id=9911 WHERE id=?", (s["id"],))
    h = login(client, 9911, "x", "")
    t = make_task(client, w["tit"]).json()
    client.post(f"/api/tasks/{t['id']}/submit", json={"comment": "ok"}, headers=w["m1"])
    month = datetime.datetime.fromtimestamp(db.now(), TZ).strftime("%Y-%m")
    r = client.get("/api/report", params={"month": month}, headers=h).json()
    assert r["area"] == "Paxtaobod tumani" and r["tasks"] >= 2 and r["tasks_done"] >= 1 and r["people"] >= 5
    assert client.get("/api/report", headers=w["m1"]).status_code == 403  # oddiy koordinator — yo‘q
    assert client.get("/api/report", params={"month": "2026-13"}, headers=h).status_code == 400
    # o‘zimga Telegram’da / себе в Telegram
    assert client.post("/api/report/send", json={"month": month}, headers=h).json()["ok"]
    assert sent[-1][1]["chat_id"] == 9911 and "Oylik hisobot" in sent[-1][1]["text"]
    # avtomatik: faqat 1-kuni 9:00 dan keyin, bir marta / автоматически: только 1-го после 9:00, один раз
    d = datetime.datetime.fromtimestamp(db.now(), TZ)
    first = datetime.datetime(d.year, d.month, 1, 10, 0, tzinfo=TZ).timestamp()
    assert report.send_monthly(first - 86400 * 3 if d.day > 3 else first + 86400) == 0
    sent.clear()
    n = report.send_monthly(int(first))
    assert n >= 2  # admin + xodim
    chats = {p["chat_id"] for m, p in sent if m == "sendMessage"}
    assert 9911 in chats and 1 in chats
    assert report.send_monthly(int(first)) == 0  # takror yo‘q / без повтора
    client.post(f"/api/admin/staff/{s['id']}", json={"remove": True}, headers=admin)
