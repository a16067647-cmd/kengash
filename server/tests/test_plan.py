"""Vazifalar, tadbirlar, «Bugun», push testlari / тесты задач, мероприятий, «Сегодня», push."""

import base64
import io
import os

import pytest

from test_api import client, login, seat, give_seat  # noqa: F401

import db
import plan
import push
import storage


@pytest.fixture(autouse=True)
def fake_storage(monkeypatch):
    files = {}
    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "put", lambda path, data, mime: files.__setitem__(path, data))
    monkeypatch.setattr(storage, "sign", lambda paths: {p: f"https://storage.test/{p}" for p in paths})
    monkeypatch.setattr(storage, "remove", lambda paths: None)
    push.SENT.clear()
    return files


def jpeg():
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", (60, 40), (9, 9, 9)).save(buf, "JPEG")
    return base64.b64encode(buf.getvalue()).decode()


@pytest.fixture(scope="module")
def w(client):  # noqa: F811
    """Paxtaobod: tuman IT, tuman Lider; maktab 1 IT, maktab 2 IT, maktab 1 Sport; Ulug‘nor maktab IT; tuman Sport."""
    admin = login(client, 1, "Admin", "boss")
    client.post("/api/admin/schools/bulk", json={"district_id": "paxtaobod", "spec": "1-2"}, headers=admin)
    client.post("/api/admin/schools/bulk", json={"district_id": "ulugnor", "spec": "3"}, headers=admin)
    sch = {s["number"]: s["id"] for s in client.get("/api/schools", params={"district_id": "paxtaobod"}, headers=admin).json()["schools"]}
    ul = client.get("/api/schools", params={"district_id": "ulugnor"}, headers=admin).json()["schools"][0]["id"]
    r = {"admin": admin, "s1": sch[1], "s2": sch[2]}
    for key, tg, name, s in [("tit", 3001, "Paxta IT", seat("district", "paxtaobod", "it")),
                             ("tlid", 3002, "Paxta Lider", seat("district", "paxtaobod", "lider")),
                             ("tsp", 3003, "Paxta Sport", seat("district", "paxtaobod", "sport")),
                             ("m1", 3004, "P1 IT", seat("school", sch[1], "it")),
                             ("m2", 3005, "P2 IT", seat("school", sch[2], "it")),
                             ("m1s", 3006, "P1 Sport", seat("school", sch[1], "sport")),
                             ("u3", 3007, "U3 IT", seat("school", ul, "it"))]:
        r[key] = login(client, tg, name, f"u{tg}")
        give_seat(client, admin, r[key], s)
    return r


def uid(client, h):  # noqa: F811
    return client.get("/api/me", headers=h).json()["id"]


def make_task(client, h, **kw):  # noqa: F811
    body = {"title": "Robototexnika hisoboti", "deadline": db.now() + 3 * 86400, "photo_required": True,
            "audience": [{"level": "school", "district_ids": ["paxtaobod"], "directions": ["it"]}]}
    body.update(kw)
    return client.post("/api/tasks", json=body, headers=h)


def test_task_permissions_and_audience(client, w):  # noqa: F811
    assert make_task(client, w["m1"]).status_code == 403  # maktab koordinatori vazifa bermaydi
    r = make_task(client, w["tit"])
    assert r.status_code == 200, r.text
    assert r.json()["total"] == 2  # P1 IT + P2 IT, Sport yo‘q
    assert set(push.SENT[-1]["users"]) == {uid(client, w["m1"]), uid(client, w["m2"])}
    # tengdosh (boshqa tuman koordinatori) olmaydi / ровесник не получает
    r = make_task(client, w["tit"], audience=[{"level": "district"}])
    assert r.json()["error"] == "no_people"
    # boshqa tuman maktabi tushmaydi / школа другого района не попадает
    r = make_task(client, w["tit"], audience=[{"level": "school", "directions": ["it"]}])
    assert r.json()["total"] == 2
    assert make_task(client, w["tit"], deadline=db.now() - 86400 * 2).json()["error"] == "bad_deadline"
    # Lider — barcha yo‘nalishlar / Лидер — все направления
    assert make_task(client, w["tlid"], audience=[{"level": "school", "district_ids": ["paxtaobod"]}]).json()["total"] == 3


def test_task_flow(client, w):  # noqa: F811
    tid = make_task(client, w["tit"], title="Fotohisobot").json()["id"]
    mine = [t for t in client.get("/api/tasks", headers=w["m1"]).json()["tasks"] if t["id"] == tid][0]
    assert mine["my"]["status"] == "new"
    assert [t for t in client.get("/api/today", headers=w["m1"]).json()["tasks"] if t["id"] == tid]
    # surat talab qilinadi / фото обязательно
    assert client.post(f"/api/tasks/{tid}/submit", json={"comment": "Bajardim"}, headers=w["m1"]).json()["error"] == "photo_required"
    p = client.post(f"/api/tasks/{tid}/photo", json={"data": jpeg()}, headers=w["m1"]).json()["path"]
    assert client.post(f"/api/tasks/{tid}/photo", json={"data": jpeg()}, headers=w["m1s"]).status_code == 403
    # boshqa odamning surati yo‘li rad etiladi / путь чужого фото отклоняется
    bad = p.replace(uid(client, w["m1"]), uid(client, w["m2"]))
    assert client.post(f"/api/tasks/{tid}/submit", json={"photos": [bad]}, headers=w["m1"]).status_code == 400
    assert client.post(f"/api/tasks/{tid}/submit", json={"comment": "Bajardim", "photos": [p]}, headers=w["m1"]).status_code == 200
    assert push.SENT[-1]["users"] == [uid(client, w["tit"])]
    # giver ko‘radi / выдавший видит
    t = client.get(f"/api/tasks/{tid}", headers=w["tit"]).json()
    assert t["counts"]["submitted"] == 1 and t["can_review"]
    sub = [x for x in t["people"] if x["status"] == "submitted"][0]
    assert sub["comment"] == "Bajardim" and sub["photo_urls"][0].endswith(p)
    # yuqoridagi (tuman Lider) ham ko‘radi, tengdosh maktab ko‘rmaydi / вышестоящий видит, равный — нет
    assert client.get(f"/api/tasks/{tid}", headers=w["tlid"]).json()["can_review"]
    m2view = client.get(f"/api/tasks/{tid}", headers=w["m2"]).json()
    assert not m2view["can_review"] and m2view["people"] == []
    assert client.get(f"/api/tasks/{tid}", headers=w["m1s"]).status_code == 403
    assert client.get(f"/api/tasks/{tid}", headers=w["tsp"]).status_code == 403  # boshqa yo‘nalish
    # qaytarish izohsiz bo‘lmaydi / возврат без комментария нельзя
    m1 = uid(client, w["m1"])
    assert client.post(f"/api/tasks/{tid}/review", json={"user_id": m1, "action": "return"}, headers=w["tit"]).status_code == 400
    assert client.post(f"/api/tasks/{tid}/review", json={"user_id": m1, "action": "return", "note": "Surat xira"},
                       headers=w["m2"]).status_code == 403
    client.post(f"/api/tasks/{tid}/review", json={"user_id": m1, "action": "return", "note": "Surat xira"}, headers=w["tit"])
    my = client.get(f"/api/tasks/{tid}", headers=w["m1"]).json()["my"]
    assert my["status"] == "returned" and my["review_note"] == "Surat xira"
    client.post(f"/api/tasks/{tid}/submit", json={"photos": [p]}, headers=w["m1"])
    client.post(f"/api/tasks/{tid}/review", json={"user_id": m1, "action": "accept"}, headers=w["tlid"])
    assert client.get(f"/api/tasks/{tid}", headers=w["m1"]).json()["my"]["status"] == "accepted"
    assert not [t for t in client.get("/api/today", headers=w["m1"]).json()["tasks"] if t["id"] == tid]
    given = [t for t in client.get("/api/tasks", params={"box": "given"}, headers=w["tit"]).json()["tasks"] if t["id"] == tid][0]
    assert given["counts"]["accepted"] == 1 and given["total"] == 2
    assert client.post(f"/api/tasks/{tid}/delete", headers=w["m1"]).status_code == 403
    assert client.post(f"/api/tasks/{tid}/delete", headers=w["tit"]).status_code == 200


def test_task_without_photo(client, w):  # noqa: F811
    tid = make_task(client, w["tit"], title="Ro‘yxat yuborish", photo_required=False).json()["id"]
    assert client.post(f"/api/tasks/{tid}/submit", json={"comment": "Yubordim"}, headers=w["m2"]).status_code == 200


def test_events(client, w):  # noqa: F811
    body = {"title": "IT uchrashuv", "starts_at": db.now() + 2 * 86400, "place": "Paxtaobod, Yoshlar markazi",
            "audience": [{"level": "school", "district_ids": ["paxtaobod"], "directions": ["it"]}]}
    assert client.post("/api/events", json=body, headers=w["m1"]).status_code == 403
    r = client.post("/api/events", json=body, headers=w["tit"])
    assert r.status_code == 200 and r.json()["guests"] == 2
    eid = r.json()["id"]
    ev = [e for e in client.get("/api/events", headers=w["m1"]).json()["events"] if e["id"] == eid][0]
    assert ev["my_rsvp"] == "" and not ev["is_organizer"]
    assert client.post(f"/api/events/{eid}/rsvp", json={"rsvp": "yes"}, headers=w["m1"]).status_code == 200
    assert client.post(f"/api/events/{eid}/rsvp", json={"rsvp": "yes"}, headers=w["m1s"]).status_code == 403
    client.post(f"/api/events/{eid}/rsvp", json={"rsvp": "no"}, headers=w["m2"])
    org = client.get(f"/api/events/{eid}", headers=w["tit"]).json()
    assert org["yes"] == 1 and org["no"] == 1 and len(org["people"]) == 2
    assert "people" not in client.get(f"/api/events/{eid}", headers=w["m1"]).json()
    assert [e for e in client.get("/api/today", headers=w["m1"]).json()["events"] if e["id"] == eid]
    assert client.get(f"/api/events/{eid}", headers=w["u3"]).status_code == 403
    # eslatmalar: faqat bir marta / напоминания только один раз
    with db.tx() as c:
        c.x("UPDATE events SET starts_at=? WHERE id=?", (db.now() + 1800, eid))
    push.SENT.clear()
    plan.run_reminders()
    sent = [s for s in push.SENT if s["data"].get("id") == eid]
    assert sent and uid(client, w["m2"]) not in sent[0]["users"]  # «bora olmayman» degan
    push.SENT.clear()
    plan.run_reminders()
    assert not [s for s in push.SENT if s["data"].get("id") == eid]
    assert client.post(f"/api/events/{eid}/delete", headers=w["tit"]).status_code == 200


def test_task_reminder(client, w):  # noqa: F811
    tid = make_task(client, w["tit"], title="Shoshilinch", deadline=db.now() + 3600).json()["id"]
    push.SENT.clear()
    plan.run_reminders()
    tags = [s["body"] for s in push.SENT if s["data"].get("id") == tid]
    assert len(tags) == 2  # 24 soat va 2 soat oynalari / окна 24 ч и 2 ч


def test_push_register_and_message_push(client, w):  # noqa: F811
    assert client.post("/api/push/register", json={"token": "x" * 40, "platform": "android"}, headers=w["m2"]).status_code == 200
    chans = {c["auto_key"]: c for c in client.get("/api/channels", headers=w["m1"]).json()["channels"]}
    cid = chans["dd:paxtaobod:it"]["id"]
    client.get("/api/channels", headers=w["m2"])
    push.SENT.clear()
    client.post(f"/api/channels/{cid}/messages", json={"text": "Salom!"}, headers=w["m1"])
    users = push.SENT[-1]["users"]
    assert uid(client, w["m2"]) in users and uid(client, w["m1"]) not in users
    # ovozsiz kanal — push yo‘q / канал без звука — без push
    client.post(f"/api/channels/{cid}/mute", json={"muted": True}, headers=w["m2"])
    push.SENT.clear()
    client.post(f"/api/channels/{cid}/messages", json={"text": "Yana"}, headers=w["m1"])
    assert all(uid(client, w["m2"]) not in s["users"] for s in push.SENT)
    assert client.post("/api/push/unregister", json={"token": "x" * 40}).status_code == 200


def test_push_disabled_without_key():
    assert not push.enabled() or os.environ.get("FIREBASE_SERVICE_ACCOUNT")


def test_telegram_notifications(client, w, monkeypatch):  # noqa: F811
    import telegram
    sent = []
    monkeypatch.setattr(telegram, "api", lambda m, p: sent.append(p))
    monkeypatch.setattr(push, "TELEGRAM_SYNC", True)
    tg = {"m1": 3004, "m2": 3005}
    # yangi vazifa → Telegram xabari / новая задача → сообщение в Telegram
    make_task(client, w["tit"], title="Telegram sinovi")
    chats = {p["chat_id"] for p in sent}
    assert {tg["m1"], tg["m2"]} <= chats
    assert "Telegram sinovi" in sent[-1]["text"] and sent[-1]["reply_markup"]["inline_keyboard"][0][0]["url"]
    # o‘chirib qo‘yganlarga yuborilmaydi / отключившим не отправляется
    me = client.post("/api/me/notify", json={"telegram": False}, headers=w["m2"]).json()
    assert me["notify_tg"] is False
    sent.clear()
    make_task(client, w["tit"], title="Ikkinchi")
    assert tg["m2"] not in {p["chat_id"] for p in sent} and tg["m1"] in {p["chat_id"] for p in sent}
    client.post("/api/me/notify", json={"telegram": True}, headers=w["m2"])
    # chat: bitta kanal uchun 10 daqiqada 1 ta / чат: 1 раз в 10 минут на канал
    chans = {c["auto_key"]: c for c in client.get("/api/channels", headers=w["m2"]).json()["channels"]}
    cid = chans[f"school:{w['s2']}"]["id"]
    client.post(f"/api/channels/{cid}/mute", json={"muted": False}, headers=w["m2"])
    sender = login(client, 3010, "P2 Media", "u3010")
    give_seat(client, w["tlid"], sender, seat("school", w["s2"], "media"))
    client.get("/api/channels", headers=sender)
    sent.clear()
    for i in range(3):
        client.post(f"/api/channels/{cid}/messages", json={"text": f"xabar {i}"}, headers=sender)
    assert [p["chat_id"] for p in sent].count(tg["m2"]) == 1
    # HTML xavfsiz / HTML экранируется
    sent.clear()
    make_task(client, w["tit"], title="<b>x</b> & y")
    assert "&lt;b&gt;x&lt;/b&gt; &amp; y" in sent[-1]["text"]
