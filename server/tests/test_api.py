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
    r = client.post("/api/keys", json={"seats": [s]}, headers=giver)
    assert r.status_code == 200, r.text
    code = r.json()["keys"][0]["code"]
    r = client.post("/api/me/redeem-key", json={"code": code}, headers=user_h)
    assert r.status_code == 200, r.text
    return r.json()


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


def test_new_user_needs_seat_and_profile(client):
    h = login(client, 99, "Yangi", "")
    me = client.get("/api/me", headers=h).json()
    assert me["needs_seat"] and me["needs_profile"]
    r = client.post("/api/me/profile", json={"name": "Yangi Bola"}, headers=h)
    assert r.json()["error"] == "consent"
    r = client.post("/api/me/profile", json={"name": "Yangi Bola", "consent": True}, headers=h)
    assert r.status_code == 200 and not r.json()["needs_profile"]


def test_keys_permissions(client, world):
    w = world
    # maktab koordinatori kalit bera olmaydi / школьный координатор не может выдавать ключи
    r = client.post("/api/keys", json={"seats": [seat("school", w["s59"], "sport")]}, headers=w["m59"])
    assert r.status_code == 403
    # tuman IT boshqa yo‘nalishga bera olmaydi / районный IT не может на другое направление
    r = client.post("/api/keys", json={"seats": [seat("school", w["s59"], "sport")]}, headers=w["t_it"])
    assert r.status_code == 403
    # tuman Lider istalgan yo‘nalishga / районный Лидер — на любое направление
    r = client.post("/api/keys", json={"seats": [seat("school", w["s59"], "sport")]}, headers=w["t_lider"])
    assert r.status_code == 200 and r.json()["keys"]
    # boshqa tumanning maktabiga emas / не на школу другого района
    r = client.post("/api/keys", json={"seats": [seat("school", w["b1"], "it")]}, headers=w["t_it"])
    assert r.status_code == 403
    # viloyat IT — boshqa tuman maktabiga ham / областной IT — и на школу другого района
    r = client.post("/api/keys", json={"seats": [seat("school", w["b1"], "it")]}, headers=w["v_it"])
    assert r.status_code == 200
    # band o‘ringa kalit yaratilmaydi / на занятое место ключ не создаётся
    r = client.post("/api/keys", json={"seats": [seat("school", w["s59"], "it")]}, headers=w["t_it"])
    assert r.json()["keys"] == [] and r.json()["skipped"][0]["reason"] == "taken"
    # viloyat o‘rniga faqat admin / на областное место — только админ
    r = client.post("/api/keys", json={"seats": [seat("region", "andijon", "sport")]}, headers=w["v_it"])
    assert r.status_code == 403


def test_key_one_time(client, world):
    w = world
    r = client.post("/api/keys", json={"seats": [seat("school", w["s59"], "media")]}, headers=w["admin"])
    code = r.json()["keys"][0]["code"]
    a = login(client, 40, "A", "a40")
    b = login(client, 41, "B", "b41")
    assert client.post("/api/me/redeem-key", json={"code": code.lower()}, headers=a).status_code == 200
    r = client.post("/api/me/redeem-key", json={"code": code}, headers=b)
    assert r.status_code == 400 and r.json()["error"] == "bad_key"
    assert client.post("/api/me/redeem-key", json={"code": "KNG-AAAA-BBBB"}, headers=b).json()["error"] == "bad_key"


def test_key_revoke(client, world):
    w = world
    r = client.post("/api/keys", json={"seats": [seat("school", w["s60"], "it" if False else "lider")]},
                    headers=w["t_lider"])
    code = r.json()["keys"][0]["code"]
    keys = client.get("/api/keys", headers=w["t_lider"]).json()["keys"]
    kid = [k for k in keys if k["hint"] == code[-4:]][0]["id"]
    assert client.post(f"/api/keys/{kid}/revoke", headers=w["m59"]).status_code == 404
    assert client.post(f"/api/keys/{kid}/revoke", headers=w["t_lider"]).status_code == 200
    c = login(client, 42, "C", "c42")
    assert client.post("/api/me/redeem-key", json={"code": code}, headers=c).json()["error"] == "bad_key"


def test_phone_visibility(client, world):
    w = world
    seats = client.get("/api/seats", params={"level": "school", "place_id": w["s59"]}, headers=w["m60"]).json()
    it = [s for s in seats["seats"] if s["direction"] == "it"][0]["user"]
    assert it["name"] == "Maktab59 IT" and "phone" not in it  # teng darajadagi ko‘rmaydi / равный не видит
    for viewer in ("t_it", "v_it", "admin", "t_lider"):
        seats = client.get("/api/seats", params={"level": "school", "place_id": w["s59"]}, headers=w[viewer]).json()
        it = [s for s in seats["seats"] if s["direction"] == "it"][0]["user"]
        assert it["phone"] == "+998901111111", viewer
    # pastdagi yuqoridagining raqamini ko‘rmaydi / нижний не видит телефон вышестоящего
    seats = client.get("/api/seats", params={"level": "district", "place_id": "asaka"}, headers=w["m59"]).json()
    it = [s for s in seats["seats"] if s["direction"] == "it"][0]["user"]
    assert "phone" not in it
    found = client.get("/api/users/search", params={"q": "maktab59"}, headers=w["m60"]).json()["users"]
    assert found and "phone" not in found[0]


def test_key_contacts(client, world):
    w = world
    h = login(client, 50, "Kalitsiz", "")
    r = client.get("/api/key-contacts", params={"level": "school", "place_id": w["s60"], "direction": "sport"},
                   headers=h).json()
    names = [x["user"]["name"] for x in r["contacts"] if x["kind"] == "user"]
    assert names[0] == "Asaka Lider"  # tumanda sport yo‘q → Lider / в районе нет спорта → Лидер
    assert r["admin"]["tg_username"] == "boss"
    client.post("/api/admin/seat-contact", json={**seat("district", "asaka", "sport"), "tg_username": "@asaka_sport"},
                headers=w["admin"])
    r = client.get("/api/key-contacts", params={"level": "school", "place_id": w["s60"], "direction": "sport"},
                   headers=h).json()
    assert r["contacts"][0]["kind"] == "contact" and r["contacts"][0]["tg_username"] == "asaka_sport"


def test_free_seat(client, world):
    w = world
    r = client.post("/api/keys", json={"seats": [seat("school", w["s60"], "ekologiya")]}, headers=w["admin"])
    code = r.json()["keys"][0]["code"]
    e = login(client, 60, "Eko", "eko")
    client.post("/api/me/redeem-key", json={"code": code}, headers=e)
    assert client.post("/api/seats/free", json=seat("school", w["s60"], "ekologiya"), headers=w["t_it"]).status_code == 403
    assert client.post("/api/seats/free", json=seat("school", w["s60"], "ekologiya"), headers=w["t_lider"]).status_code == 200
    assert client.get("/api/me", headers=e).json()["needs_seat"]


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


def test_telegram_flow(client, monkeypatch):
    sent = []
    monkeypatch.setattr(telegram, "api", lambda m, p: sent.append((m, p)))
    monkeypatch.setattr(telegram, "WEBHOOK_SECRET", "s3cret")
    start = client.post("/api/auth/telegram/start").json()
    assert start["url"].endswith("login_" + start["id"])
    assert client.get("/api/auth/telegram/status", params={"id": start["id"]}).json()["status"] == "waiting"
    frm = {"id": 777, "first_name": "Ali", "last_name": "Valiyev", "username": "ali_v", "is_bot": False}
    hook = "/api/telegram/webhook"
    assert client.post(hook, json={}).status_code == 403
    hdr = {"X-Telegram-Bot-Api-Secret-Token": "s3cret"}
    client.post(hook, json={"message": {"from": frm, "chat": {"id": 777, "type": "private"},
                                        "text": "/start login_" + start["id"]}}, headers=hdr)
    assert sent[-1][1]["reply_markup"]["keyboard"][0][0]["request_contact"]
    # boshqa odamning kontakti rad etiladi / чужой контакт отклоняется
    client.post(hook, json={"message": {"from": frm, "chat": {"id": 777, "type": "private"},
                                        "contact": {"user_id": 5, "phone_number": "998901234567"}}}, headers=hdr)
    assert client.get("/api/auth/telegram/status", params={"id": start["id"]}).json()["status"] == "waiting"
    client.post(hook, json={"message": {"from": frm, "chat": {"id": 777, "type": "private"},
                                        "contact": {"user_id": 777, "phone_number": "998901234567"}}}, headers=hdr)
    r = client.get("/api/auth/telegram/status", params={"id": start["id"]}).json()
    assert r["status"] == "done" and r["me"]["name"] == "Ali Valiyev" and r["me"]["tg_username"] == "ali_v"
    assert r["me"]["phone"] == "+998901234567"
    assert client.get("/api/auth/telegram/status", params={"id": start["id"]}).json()["status"] == "expired"
    # ikkinchi kirish: raqam so‘ralmaydi / второй вход: номер не спрашивается
    start2 = client.post("/api/auth/telegram/start").json()
    client.post(hook, json={"message": {"from": frm, "chat": {"id": 777, "type": "private"},
                                        "text": "/start login_" + start2["id"]}}, headers=hdr)
    assert client.get("/api/auth/telegram/status", params={"id": start2["id"]}).json()["status"] == "done"
