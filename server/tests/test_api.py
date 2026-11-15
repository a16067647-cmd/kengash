"""Server testlari / тесты сервера:  cd server && python -m pytest -q"""

import base64
import io
import os
import sys
import tempfile

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
_tmp = tempfile.mkdtemp()
os.environ["KENGASH_DB"] = os.path.join(_tmp, "test.db")
os.environ["DEV_LOGIN"] = "1"
os.environ["ADMIN_TG_IDS"] = "1"
os.environ["REMINDERS"] = "0"
os.environ.pop("DATABASE_URL", None)

from fastapi.testclient import TestClient  # noqa: E402

import app as server  # noqa: E402
import db  # noqa: E402
import telegram  # noqa: E402
import push  # noqa: E402

# Testlarda bildirishnomalar darhol (fon oqimisiz) — kech kelgan xabarlar boshqa testni chalkashtirmaydi.
# В тестах уведомления сразу (без фоновых потоков) — запоздалые сообщения не путают другие тесты.
push.TELEGRAM_SYNC = True


@pytest.fixture(scope="module")
def client():
    with TestClient(server.app) as c:
        yield c


def login(client, tg_id, name="Test User", username="", phone="+998900000000"):
    r = client.post("/api/auth/dev-login", json={"tg_id": tg_id, "name": name, "username": username, "phone": phone})
    assert r.status_code == 200, r.text
    return {"Authorization": "Bearer " + r.json()["token"]}


def seat(level, place_id, direction):
    return {"level": level, "place_id": place_id, "direction": direction}


def give_seat(client, giver, user_h, s):
    """Admin o‘rinni beradi (tasdiqlangan hisob) / админ назначает место (подтверждённый аккаунт).
    `giver` — eski imzo uchun / для совместимости."""
    admin = login(client, 1, "Admin", "boss")
    uid = client.get("/api/me", headers=user_h).json()["id"]
    r = client.post(f"/api/admin/users/{uid}/seat", json=s, headers=admin)
    assert r.status_code == 200, r.text
    me = client.get("/api/me", headers=user_h).json()
    assert me["status"] == "active", me
    return me


def register(client, h, **data):
    return client.post("/api/dev/register", json=data, headers=h)


@pytest.fixture(scope="module")
def world(client):
    """Admin, viloyat IT, Asaka IT (tuman), maktab 59 IT, maktab 60 IT, Asaka Lider."""
    admin = login(client, 1, "Admin", "boss")
    assert client.get("/api/me", headers=admin).json()["role"] == "admin"
    r = client.post("/api/admin/schools/bulk", json={"district_id": "asaka", "spec": "58-60"}, headers=admin)
    assert r.json()["added"] == 3
    client.post("/api/admin/schools/bulk", json={"district_id": "baliqchi", "spec": "1"}, headers=admin)
    schools = client.get("/api/schools", params={"district_id": "asaka"}, headers=admin).json()["schools"]
    s59 = [s for s in schools if s["number"] == 59][0]["id"]
    s60 = [s for s in schools if s["number"] == 60][0]["id"]
    b1 = client.get("/api/schools", params={"district_id": "baliqchi"}, headers=admin).json()["schools"][0]["id"]

    v_it = login(client, 10, "Viloyat IT", "vit")
    give_seat(client, admin, v_it, seat("region", "andijon", "it"))
    t_it = login(client, 20, "Asaka IT", "ait")
    give_seat(client, v_it, t_it, seat("district", "asaka", "it"))
    m59 = login(client, 30, "Maktab59 IT", "m59", phone="+998901111111")
    give_seat(client, t_it, m59, seat("school", s59, "it"))
    m60 = login(client, 31, "Maktab60 IT", "m60")
    give_seat(client, t_it, m60, seat("school", s60, "it"))
    t_lider = login(client, 21, "Asaka Lider", "alider")
    give_seat(client, admin, t_lider, seat("district", "asaka", "lider"))
    return dict(admin=admin, v_it=v_it, t_it=t_it, m59=m59, m60=m60, t_lider=t_lider, s59=s59, s60=s60, b1=b1)


def test_ping(client):
    assert client.get("/api/ping").json()["ok"]


def test_meta(client):
    m = client.get("/api/meta").json()
    assert len(m["directions"]) == 8
    assert len(m["districts"]) == 16


def test_auth_required(client):
    assert client.get("/api/me").status_code == 401
    assert client.get("/api/me", headers={"Authorization": "Bearer nope"}).status_code == 401


def test_new_user_must_register(client):
    h = login(client, 99, "Yangi", "")
    me = client.get("/api/me", headers=h).json()
    assert me["needs_registration"] and me["status"] == "new"
    assert client.get("/api/channels", headers=h).json()["error"] == "not_active"
    assert client.get("/api/seats", params={"level": "district", "place_id": "asaka"}, headers=h).status_code == 403


def test_registration_and_approvals(client, world):
    w = world
    # maslahatchi → tuman Lideri tasdiqlaydi / маслахатчи → подтверждает Лидер района
    mh = login(client, 400, "x", "maslahat59")
    assert register(client, mh, name="ali", kind="maslahatchi", school_id=w["s59"]).json()["error"] == "bad_name"
    me = register(client, mh, name="karimova nodira", kind="maslahatchi", school_id=w["s59"]).json()
    assert me["status"] == "pending" and me["name"] == "Karimova Nodira"
    assert me["approvers"][0]["name"] == "Asaka Lider"
    assert client.get("/api/channels", headers=mh).status_code == 403
    mid = me["id"]
    assert [u["id"] for u in client.get("/api/approvals", headers=w["t_lider"]).json()["users"]] == [mid]
    assert client.get("/api/approvals", headers=w["t_it"]).json()["users"] == []
    assert client.post(f"/api/approvals/{mid}", json={"approve": True}, headers=w["t_it"]).status_code == 403
    assert client.post(f"/api/approvals/{mid}", json={"approve": True}, headers=w["t_lider"]).json()["status"] == "active"
    # ikkinchi maslahatchi o‘sha maktabga — band / второй маслахатчи в ту же школу — занято
    m2 = login(client, 401, "x", "")
    r = register(client, m2, name="Boshqa Odam", kind="maslahatchi", school_id=w["s59"])
    assert r.status_code == 409 and r.json()["error"] == "seat_taken"
    # maktab koordinatori → maslahatchi tasdiqlaydi / школьный координатор → подтверждает маслахатчи
    sp = login(client, 402, "x", "sport59")
    me = register(client, sp, name="Sportchi Bola", kind="coordinator", level="school", school_id=w["s59"],
                  direction="sport").json()
    assert me["status"] == "pending" and me["approvers"][0]["name"] == "Karimova Nodira"
    assert client.get("/api/approvals", headers=w["t_lider"]).json()["users"] == []  # endi maslahatchi / теперь маслахатчи
    # band o‘rin (IT 59 — Maktab59 IT) / занятое место
    r = register(client, login(client, 403, "x", ""), name="Soxta Odam", kind="coordinator", level="school",
                 school_id=w["s59"], direction="it")
    assert r.json()["error"] == "seat_taken"
    # rad etish o‘rinni bo‘shatadi / отклонение освобождает место
    client.post(f"/api/approvals/{me['id']}", json={"approve": False}, headers=mh)
    me = client.get("/api/me", headers=sp).json()
    assert me["status"] == "rejected" and me["needs_registration"] and me["level"] is None
    me = register(client, sp, name="Sportchi Bola", kind="coordinator", level="school", school_id=w["s59"],
                  direction="sport").json()
    client.post(f"/api/approvals/{me['id']}", json={"approve": True}, headers=mh)
    assert client.get("/api/me", headers=sp).json()["status"] == "active"
    # o‘quvchi — darhol faol, bepul / ученик — сразу активен, бесплатно
    st = login(client, 404, "x", "talaba")
    assert register(client, st, name="Talaba Bola", kind="student", school_id=w["s59"], class_name="7-B").json()["status"] == "active"
    assert register(client, st, name="Talaba Bola", kind="student", school_id=w["s59"], class_name="13").json()["error"] == "bad_class"


def test_student_scope(client, world):
    w = world
    st = login(client, 410, "x", "talaba2")
    register(client, st, name="Oddiy Talaba", kind="student", school_id=w["s60"], class_name="9-A")
    keys = {c["auto_key"] for c in client.get("/api/channels", headers=st).json()["channels"]}
    assert keys == {"all", f"news:{w['s60']}", f"chat:{w['s60']}"}
    chans = {c["auto_key"]: c for c in client.get("/api/channels", headers=st).json()["channels"]}
    assert not chans[f"news:{w['s60']}"]["can_post"] and chans[f"chat:{w['s60']}"]["can_post"]
    assert not chans["all"]["can_post"]
    # o‘quvchi faqat o‘z maktabini ko‘radi / ученик видит только свою школу
    assert client.get("/api/seats", params={"level": "school", "place_id": w["s60"]}, headers=st).status_code == 200
    assert client.get("/api/seats", params={"level": "school", "place_id": w["s59"]}, headers=st).status_code == 403
    assert client.get("/api/seats", params={"level": "district", "place_id": "asaka"}, headers=st).status_code == 403
    assert client.get("/api/users/search", params={"q": "Asaka"}, headers=st).json()["users"] == []
    # o‘quvchini maktab koordinatori ko‘radi, tuman/viloyat — yo‘q / ученика видит координатор школы, район — нет
    sid = w["s60"]
    names = [u["name"] for u in client.get(f"/api/schools/{sid}/students", headers=w["m60"]).json()["students"]]
    assert "Oddiy Talaba" in names
    for who in ("t_it", "t_lider", "v_it", "m59"):
        assert client.get(f"/api/schools/{sid}/students", headers=w[who]).status_code == 403, who
    found = client.get("/api/users/search", params={"q": "Oddiy"}, headers=w["t_lider"]).json()["users"]
    assert found == []
    found = client.get("/api/users/search", params={"q": "Oddiy"}, headers=w["m60"]).json()["users"]
    assert found and found[0]["phone"]  # yuqoridagi telefonni ko‘radi / вышестоящий видит телефон
    # o‘quvchi vazifa bera olmaydi; koordinator o‘quvchilarga beradi / ученик не выдаёт задачи
    assert client.post("/api/tasks", json={"title": "x", "deadline": 0}, headers=st).status_code in (400, 403)
    r = client.post("/api/tasks", json={"title": "Insho yozing", "deadline": __import__("db").now() + 86400,
                                        "photo_required": False, "audience": [{"level": "school", "kind": "student",
                                                                               "school_ids": [sid]}]}, headers=w["m60"])
    assert r.status_code == 200 and r.json()["total"] >= 1
    r = client.post("/api/tasks", json={"title": "Tuman vazifasi", "deadline": __import__("db").now() + 86400, "audience": [
        {"level": "school", "kind": "student", "school_ids": [sid]}]}, headers=w["t_it"])
    assert r.json()["error"] == "no_people"  # tuman o‘quvchilarga bera olmaydi / район не может ученикам


def test_announcements_only_region_lider(client, world):
    w = world
    cid = {c["auto_key"]: c for c in client.get("/api/channels", headers=w["v_it"]).json()["channels"]}["all"]["id"]
    assert client.post(f"/api/channels/{cid}/messages", json={"text": "x"}, headers=w["v_it"]).status_code == 403
    assert client.post(f"/api/channels/{cid}/messages", json={"text": "E’lon"}, headers=w["admin"]).status_code == 200


def test_phone_visibility(client, world):
    w = world
    seats = client.get("/api/seats", params={"level": "school", "place_id": w["s59"]}, headers=w["m60"]).json()
    it = [s for s in seats["seats"] if s["direction"] == "it"][0]["user"]
    assert it["name"] == "Maktab59 IT" and "phone" not in it  # teng darajadagi ko‘rmaydi / равный не видит
    for viewer in ("t_it", "v_it", "admin", "t_lider"):  # yuqoridagilar / вышестоящие
        seats = client.get("/api/seats", params={"level": "school", "place_id": w["s59"]}, headers=w[viewer]).json()
        it = [s for s in seats["seats"] if s["direction"] == "it"][0]["user"]
        assert it["phone"] == "+998901111111", viewer
    # pastdagi yuqoridagining raqamini ko‘rmaydi / нижний не видит телефон вышестоящего
    seats = client.get("/api/seats", params={"level": "district", "place_id": "asaka"}, headers=w["m59"]).json()
    it = [s for s in seats["seats"] if s["direction"] == "it"][0]["user"]
    assert "phone" not in it
    found = client.get("/api/users/search", params={"q": "maktab59"}, headers=w["m60"]).json()["users"]
    assert found and "phone" not in found[0]


def test_photo_strips_exif(client, world):
    from PIL import Image
    im = Image.new("RGB", (800, 600), (90, 45, 200))
    exif = Image.Exif()
    exif[0x8825] = {2: (41.0, 0.0, 0.0)}
    buf = io.BytesIO()
    im.save(buf, "JPEG", exif=exif)
    r = client.post("/api/me/photo", json={"data": base64.b64encode(buf.getvalue()).decode()}, headers=world["m60"])
    assert r.status_code == 200, r.text
    url = r.json()["photo"]
    img = client.get(url)
    assert img.status_code == 200
    out = Image.open(io.BytesIO(img.content))
    assert out.size == (512, 512) and not out.getexif()
    assert client.post("/api/me/photo", json={"data": "bm9wZQ=="}, headers=world["m60"]).status_code == 400


def test_admin_only(client, world):
    for path in ("/api/admin/users", "/api/admin/stats"):
        assert client.get(path, headers=world["v_it"]).status_code == 403
        assert client.get(path, headers=world["admin"]).status_code == 200
    assert client.post("/api/admin/schools/bulk", json={"district_id": "asaka", "spec": "1"},
                       headers=world["t_lider"]).status_code == 403
    assert client.post("/api/admin/schools/bulk", json={"district_id": "asaka", "spec": "1-9999"},
                       headers=world["admin"]).status_code == 400


def test_block_and_delete(client, world):
    h = login(client, 70, "Yomon", "bad")
    uid = client.get("/api/me", headers=h).json()["id"]
    client.post(f"/api/admin/users/{uid}/block", json={"blocked": True}, headers=world["admin"])
    assert client.get("/api/me", headers=h).status_code == 401  # tokenlar o‘chirildi / токены удалены
    h2 = login(client, 71, "O‘chadi", "del")
    assert client.post("/api/me/delete", json={"confirm": "yo‘q"}, headers=h2).status_code == 400
    assert client.post("/api/me/delete", json={"confirm": "O‘CHIRISH"}, headers=h2).status_code == 200
    assert client.get("/api/me", headers=h2).status_code == 401


def test_telegram_registration_flow(client, world, monkeypatch):
    """Botda ro‘yxatdan o‘tish: raqam → ism → rol → tuman → maktab → yo‘nalish → tasdiqlash; tasdiqlovchiga ✅/❌.
    Регистрация в боте и подтверждение кнопкой."""
    w = world
    sent = []
    monkeypatch.setattr(telegram, "api", lambda m, p: sent.append((m, p)))
    monkeypatch.setattr(telegram, "WEBHOOK_SECRET", "s3cret")
    hdr = {"X-Telegram-Bot-Api-Secret-Token": "s3cret"}
    hook = "/api/telegram/webhook"
    assert client.post(hook, json={}).status_code == 403
    frm = {"id": 777, "first_name": "Ali", "last_name": "V", "username": "ali_v", "is_bot": False}
    chat = {"id": 777, "type": "private"}

    def msg(**kw):
        client.post(hook, json={"message": {"from": frm, "chat": chat, **kw}}, headers=hdr)

    def press(data, who=frm):
        client.post(hook, json={"callback_query": {"id": "q", "from": who, "data": data,
                                                    "message": {"chat": {"id": who["id"]}, "message_id": 5}}}, headers=hdr)

    def last_kb():
        for m, p in reversed(sent):
            kb = (p.get("reply_markup") or {}).get("inline_keyboard")
            if kb:
                return [b["callback_data"] for row in kb for b in row if "callback_data" in b]
        return []

    start = client.post("/api/auth/telegram/start").json()
    msg(text="/start login_" + start["id"])
    assert sent[-1][1]["reply_markup"]["keyboard"][0][0]["request_contact"]
    msg(contact={"user_id": 5, "phone_number": "998900000001"})  # boshqa odamniki / чужой
    assert "O‘ZINGIZNING" in sent[-1][1]["text"]
    msg(contact={"user_id": 777, "phone_number": "998901234567"})
    assert "Ism va familiyangizni" in sent[-1][1]["text"]
    msg(text="Ali")
    assert "to‘liq" in sent[-1][1]["text"]
    msg(text="valiyev ali")
    assert "r:role:coordinator" in last_kb()
    msg(text="tugma emas")
    assert "tugmalardan" in sent[-1][1]["text"]
    press("r:role:coordinator")
    press("r:lvl:school")
    assert "r:d:asaka" in last_kb()
    press("r:d:asaka")
    assert f"r:s:{w['s59']}" in last_kb()
    press(f"r:s:{w['s59']}")
    press("r:dir:it")  # band / занято
    assert "band" in sent[-1][1]["text"] and "Maktab59 IT" in sent[-1][1]["text"]
    press("r:dir:media")
    assert "Valiyev Ali" in sent[-1][1]["text"] and "r:ok" in last_kb()
    sent.clear()
    press("r:ok")
    assert client.get("/api/auth/telegram/status", params={"id": start["id"]}).json()["status"] == "done"
    # tasdiqlovchiga (maslahatchi) ✅/❌ tugmalari / подтверждающему (маслахатчи) кнопки
    to_approver = [p for m, p in sent if m == "sendMessage" and "Yangi ariza" in p["text"]]
    assert to_approver and to_approver[0]["chat_id"] == 400
    data = [b["callback_data"] for row in to_approver[0]["reply_markup"]["inline_keyboard"] for b in row]
    assert data[0].startswith("ap:")
    press(data[0], who={"id": 31, "is_bot": False})  # boshqa odam bossa — ruxsat yo‘q / чужой — нет прав
    assert "Ruxsat" in sent[-1][1]["text"]
    sent.clear()
    press(data[0], who={"id": 400, "is_bot": False})
    assert any(p.get("chat_id") == 777 and "tasdiqlandi" in p["text"] for m, p in sent)
    me = [u for u in client.get("/api/users/search", params={"q": "Valiyev"}, headers=w["admin"]).json()["users"]][0]
    assert me["status"] == "active" and me["direction"] == "media" and me["kind"] == "coordinator"
    # keyingi kirish: savolsiz / следующий вход — без вопросов
    start2 = client.post("/api/auth/telegram/start").json()
    msg(text="/start login_" + start2["id"])
    r = client.get("/api/auth/telegram/status", params={"id": start2["id"]}).json()
    assert r["status"] == "done" and r["me"]["status"] == "active"

    # o‘quvchi: sinf bilan, darhol faol / ученик: с классом, сразу активен
    frm2 = {"id": 778, "first_name": "S", "username": "", "is_bot": False}
    chat2 = {"id": 778, "type": "private"}
    client.post(hook, json={"message": {"from": frm2, "chat": chat2, "text": "/start"}}, headers=hdr)
    client.post(hook, json={"message": {"from": frm2, "chat": chat2, "contact": {"user_id": 778, "phone_number": "+998900000778"}}},
                headers=hdr)
    client.post(hook, json={"message": {"from": frm2, "chat": chat2, "text": "Toshmatov Sardor"}}, headers=hdr)
    for d in ("r:role:student", "r:d:asaka", f"r:s:{w['s60']}", "r:g:8", "r:l:V"):
        press(d, who=frm2)
    assert "8-V" in sent[-1][1]["text"]
    press("r:ok", who=frm2)
    st = [u for u in client.get("/api/users/search", params={"q": "Toshmatov"}, headers=w["admin"]).json()["users"]][0]
    assert st["status"] == "active" and st["kind"] == "student" and st["class_name"] == "8-V"
