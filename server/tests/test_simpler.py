"""Soddalashtirish va o‘sish: davomat tugmasi, ovozli hisobot / упрощение и рост: кнопка отметки, голосовой отчёт."""

import pytest

from test_api import client, login  # noqa: F401
from test_plan import w, make_task, uid, fake_storage  # noqa: F401

import db
import storage


def test_event_checkin_open_only_near_start(client, w):  # noqa: F811
    aud = [{"level": "school", "district_ids": ["paxtaobod"], "directions": ["it"]}]
    later = client.post("/api/events", json={"title": "Keyinroq", "starts_at": db.now() + 2 * 86400, "audience": aud},
                        headers=w["tit"]).json()
    soon = client.post("/api/events", json={"title": "Hozir", "starts_at": db.now() + 1800, "audience": aud},
                       headers=w["tit"]).json()
    assert client.get(f"/api/events/{later['id']}", headers=w["m1"]).json()["checkin_open"] is False
    assert client.get(f"/api/events/{soon['id']}", headers=w["m1"]).json()["checkin_open"] is True


@pytest.fixture
def upload_urls(monkeypatch):
    monkeypatch.setattr(storage, "upload_url", lambda path: f"https://storage.test/upload/{path}")


def test_voice_report(client, w, upload_urls):  # noqa: F811
    tid = make_task(client, w["tit"], photo_required=False).json()["id"]
    me = uid(client, w["m1"])
    # faqat vazifa egasi yuklay oladi / загружать может только исполнитель
    assert client.post(f"/api/tasks/{tid}/voice", json={"size": 1000, "mime": "audio/mp4", "duration": 4},
                       headers=w["u3"]).status_code == 403
    assert client.post(f"/api/tasks/{tid}/voice", json={"size": 1000, "mime": "image/png", "duration": 4},
                       headers=w["m1"]).status_code == 400
    r = client.post(f"/api/tasks/{tid}/voice", json={"size": 1000, "mime": "audio/mp4", "duration": 4}, headers=w["m1"]).json()
    assert r["path"].startswith(f"tasks/{tid}/{me}/") and r["path"].endswith(".m4a") and r["upload_url"]
    # boshqa birovning yo‘li — rad / чужой путь — отказ
    bad = client.post(f"/api/tasks/{tid}/submit", json={"voice": f"tasks/{tid}/someone/x.m4a"}, headers=w["m1"])
    assert bad.status_code == 400
    assert client.post(f"/api/tasks/{tid}/submit", json={"voice": r["path"], "voice_sec": 4.4}, headers=w["m1"]).status_code == 200
    mine = client.get(f"/api/tasks/{tid}", headers=w["m1"]).json()["my"]
    assert mine["voice"] == r["path"] and mine["voice_sec"] == 4 and mine["voice_url"].endswith(r["path"])
    giver = client.get(f"/api/tasks/{tid}", headers=w["tit"]).json()
    p = next(x for x in giver["people"] if x["user"]["id"] == me)
    assert p["status"] == "submitted" and p["voice_url"].endswith(r["path"]) and p["voice_sec"] == 4


# --- Telegram Mini App ---------------------------------------------------------------------------------------------
def _init_data(token, user, auth_date=None, tamper=False):
    import hashlib
    import hmac
    import json
    from urllib.parse import urlencode
    fields = {"auth_date": str(auth_date or db.now()), "query_id": "AAE", "user": json.dumps(user, separators=(",", ":"))}
    check = "\n".join(f"{k}={v}" for k, v in sorted(fields.items()))
    secret = hmac.new(b"WebAppData", token.encode(), hashlib.sha256).digest()
    fields["hash"] = hmac.new(secret, check.encode(), hashlib.sha256).hexdigest()
    if tamper:
        fields["user"] = fields["user"].replace(str(user["id"]), "1")  # boshqa odam bo‘lib ko‘rinish / подмена
    return urlencode(fields)


def test_webapp_login(client, w, monkeypatch):  # noqa: F811
    import telegram
    import app as core
    monkeypatch.setattr(telegram, "BOT_TOKEN", "123:abc")
    url = "/api/auth/telegram/webapp"
    # ro‘yxatdan o‘tgan foydalanuvchi (tg 3004) — darhol kiradi / зарегистрированный — сразу входит
    r = client.post(url, json={"init_data": _init_data("123:abc", {"id": 3004, "first_name": "P1"})})
    assert r.status_code == 200 and r.json()["token"] and r.json()["me"]["name"] == "P1 IT"
    me = client.get("/api/me", headers={"Authorization": "Bearer " + r.json()["token"]})
    assert me.status_code == 200
    # yangi odam — avval bot (telefon) / новый — сначала бот (телефон)
    assert client.post(url, json={"init_data": _init_data("123:abc", {"id": 99999})}).json()["need_bot"] is True
    # soxta imzo, boshqa kalit, eskirgan — rad / подделка, чужой ключ, устаревшее — отказ
    assert client.post(url, json={"init_data": _init_data("123:abc", {"id": 3004}, tamper=True)}).status_code == 403
    assert client.post(url, json={"init_data": _init_data("999:zzz", {"id": 3004})}).status_code == 403
    old = db.now() - 2 * 86400
    assert client.post(url, json={"init_data": _init_data("123:abc", {"id": 3004}, auth_date=old)}).status_code == 403
    assert client.post(url, json={"init_data": "garbage"}).status_code == 403
    assert core.check_webapp_init("", "123:abc") is None


# --- E’lonni kim ko‘rdi + bir martalik eslatma / кто видел объявление + одно напоминание ----------------------------
def test_announcement_seen_and_single_reminder(client, w):  # noqa: F811
    import push
    body = {"title": "E’lonlar", "mode": "announce",
            "audience": [{"level": "school", "district_ids": ["paxtaobod"], "directions": ["it"]}]}
    cid = client.post("/api/channels", json=body, headers=w["tit"]).json()["id"]
    mid = client.post(f"/api/channels/{cid}/messages", json={"text": "Ertaga 10:00 da yig‘ilish"}, headers=w["tit"]).json()["id"]
    first = client.get(f"/api/channels/{cid}/messages", headers=w["tit"]).json()["messages"][0]
    assert (first["seen"], first["seen_of"]) == (0, 2)  # muallif hisobga olinmaydi / автор не считается
    client.post(f"/api/channels/{cid}/read", json={"seq": first["seq"]}, headers=w["m1"])
    first = client.get(f"/api/channels/{cid}/messages", headers=w["tit"]).json()["messages"][0]
    assert (first["seen"], first["seen_of"]) == (1, 2)
    # oddiy a’zo eslata olmaydi / обычный участник не может напомнить
    assert client.post(f"/api/messages/{mid}/remind", headers=w["m1"]).status_code == 403
    push.SENT.clear()
    r = client.post(f"/api/messages/{mid}/remind", headers=w["tit"])
    assert r.status_code == 200 and r.json()["sent"] == 1
    assert push.SENT[-1]["users"] == [uid(client, w["m2"])]  # faqat ko‘rmagan / только не видевший
    # ikkinchi marta — yo‘q (bezovta qilmaymiz) / второй раз — нет (не надоедаем)
    assert client.post(f"/api/messages/{mid}/remind", headers=w["tit"]).status_code == 409


# --- Maktab taklif havolasi / ссылка-приглашение школы -------------------------------------------------------------
def test_school_invite_link(client, w, monkeypatch):  # noqa: F811
    import telegram
    sent = []
    monkeypatch.setattr(telegram, "api", lambda m, p: sent.append((m, p)))
    monkeypatch.setattr(telegram, "WEBHOOK_SECRET", "s3cret")
    hdr = {"X-Telegram-Bot-Api-Secret-Token": "s3cret"}
    # havola: faqat o‘sha maktab koordinatori / ссылка: только координатор этой школы
    assert client.get(f"/api/schools/{w['s1']}/invite", headers=w["m2"]).status_code == 403
    inv = client.get(f"/api/schools/{w['s1']}/invite", headers=w["m1"]).json()
    assert inv["url"].endswith(f"?start=join_{w['s1']}") and inv["share_url"].startswith("https://t.me/share/url?url=")

    frm = {"id": 8801, "first_name": "Laylo", "is_bot": False}

    def msg(**kw):
        client.post("/api/telegram/webhook", json={"message": {"from": frm, "chat": {"id": 8801, "type": "private"}, **kw}},
                    headers=hdr)

    def press(data):
        client.post("/api/telegram/webhook", json={"callback_query": {
            "id": "q", "from": frm, "data": data, "message": {"chat": {"id": 8801}, "message_id": 5}}}, headers=hdr)

    msg(text=f"/start join_{w['s1']}")
    msg(contact={"user_id": 8801, "phone_number": "998907770011"})
    msg(text="Karimova Laylo")
    last = sent[-1][1]
    # rol, tuman, maktab so‘ralmaydi — darhol sinf / роль, район, школа не спрашиваются — сразу класс
    assert "o‘quvchisi sifatida" in last["text"]
    assert "r:g:7" in str(last["reply_markup"])
    press("r:g:7")
    press("r:l:A")
    press("r:ok")
    u = client.get("/api/users/search", params={"q": "Laylo"}, headers=w["admin"]).json()["users"][0]
    assert u["kind"] == "student" and u["place_id"] == w["s1"] and u["class_name"] == "7-A"
