"""Xodimlar («Boshqa»): bot orqali ariza → admin botda sozlaydi; admin ilovada yaratadi; vakolatlar.
Сотрудники («Другое»): заявка в боте → админ настраивает в боте; админ создаёт в приложении; полномочия."""
import db
import telegram
from test_api import client, login  # noqa: F401
from test_plan import w as world  # noqa: F401


def _bot(client, monkeypatch):
    sent = []
    monkeypatch.setattr(telegram, "api", lambda m, p: sent.append((m, p)))
    monkeypatch.setattr(telegram, "WEBHOOK_SECRET", "s3cret")
    hdr = {"X-Telegram-Bot-Api-Secret-Token": "s3cret"}

    def msg(who, **kw):
        client.post("/api/telegram/webhook", json={"message": {"from": who, "chat": {"id": who["id"], "type": "private"}, **kw}},
                    headers=hdr)

    def press(who, data):
        client.post("/api/telegram/webhook", json={"callback_query": {
            "id": "q", "from": who, "data": data, "message": {"chat": {"id": who["id"]}, "message_id": 9}}}, headers=hdr)

    def kb():
        for m, p in reversed(sent):
            rows = (p.get("reply_markup") or {}).get("inline_keyboard")
            if rows:
                return [b["callback_data"] for row in rows for b in row if "callback_data" in b]
        return []

    return sent, msg, press, kb


def test_staff_via_bot_and_powers(client, world, monkeypatch):  # noqa: F811
    w = world
    sent, msg, press, kb = _bot(client, monkeypatch)
    boss = {"id": 1, "first_name": "Admin", "username": "boss", "is_bot": False}
    dir_ = {"id": 800, "first_name": "Dilnoza", "username": "dilnoza_d", "is_bot": False}

    # 1) odam: «Boshqa» → tasdiqlash / человек: «Другое» → подтверждение
    msg(dir_, text="/start")
    msg(dir_, contact={"user_id": 800, "phone_number": "998935550001"})
    msg(dir_, text="karimova dilnoza")
    assert "r:role:staff" in kb()
    press(dir_, "r:role:staff")
    assert "Boshqa" in sent[-1][1]["text"] and "r:ok" in kb()
    sent.clear()
    press(dir_, "r:ok")
    to_admin = [p for m, p in sent if m == "sendMessage" and p["chat_id"] == 1]
    assert to_admin and "Boshqa" in to_admin[0]["text"]
    go = [b["callback_data"] for row in to_admin[0]["reply_markup"]["inline_keyboard"] for b in row][0]
    assert go.startswith("st:go:")
    uid = go[6:]
    # ilovada oddiy tasdiqlab bo‘lmaydi — avval sozlash / в приложении просто подтвердить нельзя
    r = client.post(f"/api/approvals/{uid}", json={"approve": True}, headers=w["admin"])
    assert r.status_code == 400 and r.json()["error"] == "needs_setup"
    # boshqa odam sozlay olmaydi / другой человек настроить не может
    press({"id": 20, "is_bot": False}, go)
    assert "Ruxsat" in sent[-1][1]["text"]

    # 2) admin botda: lavozim → hudud → vakolatlar → saqlash
    press(boss, go)
    assert "Lavozimini" in sent[-1][1]["text"]
    msg(boss, text="Paxtaobod Kelajak Markazi direktori")
    assert "st:a:district:paxtaobod" in kb() and "st:a:region:andijon" in kb()
    press(boss, "st:a:district:paxtaobod")
    assert "✅ 👁" in str(sent[-1][1]["reply_markup"])  # «view» oldindan belgilangan / «view» отмечено заранее
    press(boss, "st:p:plan")
    press(boss, "st:p:announce")
    sent.clear()
    press(boss, "st:save")
    edited = [p for m, p in sent if m == "editMessageText"]
    assert edited and "Paxtaobod Kelajak Markazi direktori" in edited[0]["text"]
    told = [p for m, p in sent if m == "sendMessage" and p["chat_id"] == 800]
    assert told and "tasdiqlandi" in told[0]["text"] and "Kelajak Markazi" in told[0]["text"]

    h = login(client, 800, "x", "dilnoza_d")
    me = client.get("/api/me", headers=h).json()
    assert me["kind"] == "staff" and me["status"] == "active" and me["title"] == "Paxtaobod Kelajak Markazi direktori"
    assert me["level"] == "district" and me["place_id"] == "paxtaobod" and me["powers"] == ["announce", "plan", "view"]
    assert me["can_give"] and me["can_view_area"] and me["can_announce"] and not me["can_create_channels"]

    # 3) ko‘rish: hudud koordinatorlari telefoni ko‘rinadi, o‘rinni bo‘shata olmaydi
    m59 = client.get("/api/users/search", params={"q": "P1 IT"}, headers=h).json()["users"][0]
    assert m59.get("phone")
    assert client.get(f"/api/users/{m59['id']}", headers=h).json()["can_manage"] is False
    r = client.post("/api/seats/free", json={"level": "school", "place_id": w["s1"], "direction": "it"}, headers=h)
    assert r.status_code == 403
    v_it = client.get("/api/users/search", params={"q": "U3 IT"}, headers=h).json()["users"][0]
    assert "phone" not in v_it  # Ulug‘nor — hududdan tashqarida / вне территории
    # kanallar: Asaka jamoasi — faqat o‘qiydi / каналы: команда Асаки — только чтение
    chans = client.get("/api/channels", headers=h).json()["channels"]
    team = [ch for ch in chans if ch["auto_key"] == "dt:paxtaobod"]
    assert team and team[0]["can_post"] is False and team[0]["role"] == "viewer"
    assert any(ch["auto_key"] == "dd:paxtaobod:it" for ch in chans)
    r = client.post(f"/api/channels/{team[0]['id']}/messages", json={"text": "salom"}, headers=h)
    assert r.status_code == 403

    # 4) vazifa: faqat hududidagilarga / задача: только своей территории
    t = client.post("/api/tasks", json={"title": "Hisobot", "deadline": db.now() + 3 * 86400,
                                        "audience": [{"level": "school", "district_ids": ["paxtaobod"], "directions": ["it"]}]},
                    headers=h).json()
    names = {p["user"]["name"] for p in client.get(f"/api/tasks/{t['id']}", headers=h).json()["people"]}
    assert names == {"P1 IT", "P2 IT"}
    r = client.post("/api/tasks", json={"title": "Viloyatga", "deadline": db.now() + 3 * 86400,
                                        "audience": [{"level": "region"}]}, headers=h)
    assert r.status_code == 400  # viloyat koordinatorlari — hududdan tashqari / вне территории

    # 5) e’lon va faollik — faqat Asaka / объявление и активность — только Асака
    mine = client.post("/api/admin/broadcast/count", json={"filter": {}}, headers=h).json()["count"]
    everyone = client.post("/api/admin/broadcast/count", json={"filter": {}}, headers=w["admin"]).json()["count"]
    assert 0 < mine < everyone
    act = client.get("/api/admin/activity", headers=h).json()
    assert [d["id"] for d in act["districts"]] == ["paxtaobod"]
    assert client.post("/api/admin/export", json={"what": "books"}, headers=h).status_code == 403
    # boshqa admin ishlari — yo‘q / прочие админ-функции — нет
    assert client.get("/api/admin/users", headers=h).status_code == 403
    assert client.get("/api/admin/staff", headers=h).status_code == 403

    # 6) vakolatsiz xodim: hech narsa / без полномочий: ничего
    r = client.post(f"/api/admin/staff/{uid}", json={"title": "Metodist", "level": "district", "place_id": "paxtaobod",
                                                     "powers": []}, headers=w["admin"])
    assert r.status_code == 200 and r.json()["powers"] == []
    me = client.get("/api/me", headers=h).json()
    assert not me["can_give"] and not me["can_view_area"] and me["title"] == "Metodist"
    assert "phone" not in client.get("/api/users/search", params={"q": "P1 IT"}, headers=h).json()["users"][0]
    assert client.get("/api/admin/activity", headers=h).status_code == 403
    assert not any(ch["auto_key"] == "dt:paxtaobod" for ch in client.get("/api/channels", headers=h).json()["channels"])


def test_staff_created_by_admin(client, world, monkeypatch):  # noqa: F811
    w = world
    sent, msg, press, kb = _bot(client, monkeypatch)
    body = {"name": "Toshmatov Bekzod", "phone": "93 555 44 33", "title": "Viloyat bo‘limi boshlig‘i",
            "level": "region", "place_id": "andijon", "powers": ["view", "announce"]}
    assert client.post("/api/admin/staff", json=body, headers=w["m1"]).status_code == 403
    r = client.post("/api/admin/staff", json=body | {"phone": "+998900000000"}, headers=w["admin"])
    assert r.status_code == 409 and r.json()["error"] == "phone_taken"  # koordinator raqami / номер координатора
    assert client.post("/api/admin/staff", json=body | {"place_id": "nowhere"}, headers=w["admin"]).status_code == 400
    s = client.post("/api/admin/staff", json=body, headers=w["admin"]).json()
    assert s["kind"] == "staff" and s["status"] == "active" and s["linked"] is False and s["powers"] == ["announce", "view"]
    assert any(x["id"] == s["id"] for x in client.get("/api/admin/staff", headers=w["admin"]).json()["staff"])

    # odam botga kiradi va raqamini ulashadi → tayyor hisob / человек делится номером → готовый аккаунт
    who = {"id": 801, "first_name": "Bekzod", "username": "bekzod_t", "is_bot": False}
    msg(who, text="/start")
    msg(who, contact={"user_id": 801, "phone_number": "998935554433"})
    assert "Ism va familiyangizni" not in sent[-1][1]["text"]  # ro‘yxat so‘ralmaydi / регистрация не нужна
    h = login(client, 801, "x", "bekzod_t")
    me = client.get("/api/me", headers=h).json()
    assert me["id"] == s["id"] and me["title"] == "Viloyat bo‘limi boshlig‘i" and not me["can_give"]
    # viloyat: hamma tumanlar faolligi / область: активность всех районов
    assert len(client.get("/api/admin/activity", headers=h).json()["districts"]) > 1
    keys = {ch["auto_key"] for ch in client.get("/api/channels", headers=h).json()["channels"]}
    assert "rt:andijon" in keys and "dt:paxtaobod" in keys

    # xodimlikdan olish / снять с должности
    assert client.post(f"/api/admin/staff/{s['id']}", json={"remove": True}, headers=w["admin"]).json()["ok"]
    assert client.get("/api/me", headers=h).status_code == 401
    assert not any(x["id"] == s["id"] for x in client.get("/api/admin/staff", headers=w["admin"]).json()["staff"])
