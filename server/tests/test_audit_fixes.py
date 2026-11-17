"""Ishlab chiqarish auditidagi tuzatishlar / исправления по аудиту продакшена:  cd server && python -m pytest -q"""

import logging

import pytest

from test_api import client, login  # noqa: F401  (umumiy server / общий сервер)
from test_channels import ch, fake_storage  # noqa: F401

import app as core
import channels
import db
import plan
import telegram


@pytest.fixture
def count_queries(monkeypatch):
    """Bazaga so‘rovlar sonini sanaydi / считает запросы к базе."""
    n = {"n": 0}
    for name in ("q", "x"):
        orig = getattr(db._Conn, name)

        def wrap(self, *a, _o=orig, **k):
            n["n"] += 1
            return _o(self, *a, **k)
        monkeypatch.setattr(db._Conn, name, wrap)
    return n


# --- 1. Poyga / гонка: msg_seq ---------------------------------------------------------------------------------------
def test_message_seq_atomic_with_stale_channel_row(client, ch):  # noqa: F811
    """Ikki xabar bir vaqtda: ikkalasi ham eski `ch` qatorini o‘qigan. Avval ikkinchisi seq’ni takrorlab yiqilardi.
    Два сообщения одновременно, оба прочитали старую строку `ch`. Раньше второе падало на повторе seq."""
    h = ch["admin"]
    cid = client.post("/api/channels", json={"title": "Poyga", "mode": "group"}, headers=h).json()["id"]
    with db.tx() as c:
        stale = c.one("SELECT * FROM channels WHERE id=?", (cid,))
        u = c.one("SELECT * FROM users WHERE tg_id=1")
        r1 = channels._insert_message(c, stale, u, "birinchi", [])[0]
        r2 = channels._insert_message(c, stale, u, "ikkinchi", [])[0]  # eski `stale` bilan / с устаревшим `stale`
    assert (r1["seq"], r2["seq"]) == (1, 2)
    msgs = client.get(f"/api/channels/{cid}/messages", headers=h).json()["messages"]
    assert sorted((m["seq"], m["text"]) for m in msgs) == [(1, "birinchi"), (2, "ikkinchi")]
    assert client.get(f"/api/channels/{cid}", headers=h).json()["seq"] == 2


# --- 2. N+1: kanallar ro‘yxati / список каналов ---------------------------------------------------------------------
def test_channel_list_queries_do_not_grow_with_channels(client, ch, count_queries):  # noqa: F811
    h = ch["admin"]

    def list_cost():
        count_queries["n"] = 0
        r = client.get("/api/channels", headers=h)
        assert r.status_code == 200
        return count_queries["n"], r.json()["channels"]

    before, rows_before = list_cost()
    for i in range(6):
        cid = client.post("/api/channels", json={"title": f"Kanal {i}", "mode": "group"}, headers=h).json()["id"]
        assert client.post(f"/api/channels/{cid}/messages", json={"text": f"salom {i}"}, headers=h).status_code == 200
    after, rows_after = list_cost()
    assert len(rows_after) >= len(rows_before) + 6
    assert after <= before + 1, (before, after)  # kanal boshiga so‘rov yo‘q / нет запросов на каждый канал
    # ro‘yxat ma’lumotlari o‘zgarmagan / данные списка те же, что и у одиночного запроса
    k = next(x for x in rows_after if x["title_uz"] == "Kanal 5")
    assert k["last"]["text"] == "salom 5" and k["last"]["user_name"] == "Admin"
    assert k["members"] == 1 and k["unread"] == 0 and k["role"] == "owner" and k["can_post"]
    one = client.get(f"/api/channels/{k['id']}", headers=h).json()
    assert {f: one[f] for f in ("members", "last", "role", "unread", "can_post")} == \
           {f: k[f] for f in ("members", "last", "role", "unread", "can_post")}


# --- 2b. N+1: joy nomlari (reyting) / названия мест (рейтинг) -------------------------------------------------------
def test_place_lookups_memoized_within_transaction(client, ch, count_queries):  # noqa: F811
    with db.tx() as c:
        count_queries["n"] = 0
        a = core.place_info(c, "school", ch["s1"])
        for _ in range(50):
            assert core.place_info(c, "school", ch["s1"]) == a
            core.model.place_chain(c, "school", ch["s1"])
        assert count_queries["n"] == 2  # bittadan / по одному
        c.x("UPDATE schools SET name=name WHERE id=?", (ch["s1"],))  # yozuv keshni tozalaydi / запись сбрасывает кэш
        count_queries["n"] = 0
        core.place_info(c, "school", ch["s1"])
        assert count_queries["n"] == 1
    with db.tx() as c:  # yangi so‘rov — yangi kesh / новый запрос — новый кэш
        count_queries["n"] = 0
        core.place_info(c, "school", ch["s1"])
        assert count_queries["n"] == 1


# --- 3. Fon ishlari xatolari / ошибки фоновых задач --------------------------------------------------------------------
def test_background_errors_are_logged_and_others_still_run(monkeypatch, caplog):
    import digest
    import report
    ran = []
    monkeypatch.setattr(plan, "run_reminders", lambda: (_ for _ in ()).throw(RuntimeError("boom")))
    monkeypatch.setattr(report, "send_monthly", lambda: ran.append("report"))
    monkeypatch.setattr(digest, "send_weekly", lambda: ran.append("digest"))
    with caplog.at_level(logging.ERROR, logger="kengash.plan"):
        plan.background_tick()
    assert ran == ["report", "digest"]
    assert "background job failed: reminders" in caplog.text and "boom" in caplog.text


# --- 4. Telegram webhook ----------------------------------------------------------------------------------------------
def test_webhook_error_is_logged_and_acknowledged(client, monkeypatch, caplog):  # noqa: F811
    """Xato bo‘lsa ham 200 — Telegram navbatni to‘xtatmaydi / при ошибке 200 — очередь Telegram не застревает."""
    monkeypatch.setattr(telegram, "WEBHOOK_SECRET", "s3cret")
    monkeypatch.setattr(telegram, "handle_update", lambda u: (_ for _ in ()).throw(RuntimeError("bad update")))
    hdr = {"X-Telegram-Bot-Api-Secret-Token": "s3cret"}
    with caplog.at_level(logging.ERROR, logger="kengash.app"):
        r = client.post("/api/telegram/webhook", json={"update_id": 42}, headers=hdr)
    assert r.status_code == 200
    assert "telegram update 42 failed" in caplog.text
    assert client.post("/api/telegram/webhook", json={"update_id": 43}).status_code == 403  # sir hali tekshiriladi


def test_webhook_runs_off_the_event_loop(client, monkeypatch):  # noqa: F811
    import threading
    seen = []
    monkeypatch.setattr(telegram, "WEBHOOK_SECRET", "s3cret")
    monkeypatch.setattr(telegram, "handle_update", lambda u: seen.append(threading.current_thread().name))
    main = []

    @core.app.get("/api/_test_loop_thread")
    async def _probe():
        main.append(threading.current_thread().name)
        return {}
    client.get("/api/_test_loop_thread")
    client.post("/api/telegram/webhook", json={"update_id": 1}, headers={"X-Telegram-Bot-Api-Secret-Token": "s3cret"})
    assert seen and main and seen[0] != main[0]
