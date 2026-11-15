"""Adminga yozish, e’lon, faollik, tahrirlash, Excel, uzoq bosib tahrirlash / написать админу, рассылка, активность, правка, Excel."""
import base64
import io
import os

import db
import push
import storage
import telegram

from test_api import client, login, register  # noqa: F401
from test_plan import w, jpeg, fake_storage, uid, make_task  # noqa: F401
from test_books import _stub, add_book


def big_jpeg():
    """64 KB dan katta haqiqiy surat (shovqin) / настоящее фото больше 64 КБ (шум)."""
    from PIL import Image
    im = Image.frombytes("RGB", (900, 1300), os.urandom(900 * 1300 * 3))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=90)
    raw = base64.b64encode(buf.getvalue()).decode()
    assert len(raw) > 200_000
    return raw


def test_feedback_reply(client, w, monkeypatch):  # noqa: F811
    _stub(monkeypatch)
    sent = []
    monkeypatch.setattr(telegram, "api", lambda method, payload: sent.append((method, payload)) or {"ok": True})
    st = login(client, 3961, "x", "shikoyatchi")
    register(client, st, name="Shikoyat Talaba", kind="student", school_id=w["s1"], class_name="10-A")
    assert client.post("/api/feedback", json={"topic": "shikoyat", "text": ""}, headers=st).status_code == 400
    r = client.post("/api/feedback", json={"topic": "taklif", "text": "Ilovaga tungi rejim kerak", "photo": big_jpeg()},
                    headers=st)
    assert r.status_code == 200, r.text
    assert push.SENT[-1]["data"]["type"] == "feedback"  # admin xabardor / админ уведомлён
    reps = client.get("/api/admin/reports", headers=w["admin"]).json()["reports"]
    fb = [x for x in reps if x["kind"] == "feedback"][0]
    assert fb["reason"] == "taklif" and fb["note"] == "Ilovaga tungi rejim kerak" and fb["photo_url"]
    assert fb["reporter"]["name"] == "Shikoyat Talaba"
    assert client.get("/api/admin/reports", headers=w["m1"]).status_code == 403
    r = client.post(f"/api/admin/feedback/{fb['id']}/reply", json={"text": "Rahmat, qo‘shamiz!"}, headers=w["admin"])
    assert r.status_code == 200
    assert any("Rahmat, qo‘shamiz!" in p.get("text", "") for m, p in sent)
    assert not [x for x in client.get("/api/admin/reports", headers=w["admin"]).json()["reports"] if x["id"] == fb["id"]]
    done = client.get("/api/admin/reports", params={"status": "done"}, headers=w["admin"]).json()["reports"]
    assert [x for x in done if x["id"] == fb["id"]][0]["reply"] == "Rahmat, qo‘shamiz!"


def test_broadcast_and_activity(client, w):  # noqa: F811
    h = w["admin"]
    n_all = client.post("/api/admin/broadcast/count", json={"filter": {}}, headers=h).json()["count"]
    n_it = client.post("/api/admin/broadcast/count", json={"filter": {"direction": "it", "district_id": "paxtaobod"}},
                       headers=h).json()["count"]
    assert n_all > n_it >= 3  # tuman IT + 2 maktab IT
    r = client.post("/api/admin/broadcast", json={"text": "Ertaga yig‘ilish", "filter": {"direction": "it",
                                                                                      "district_id": "paxtaobod"}}, headers=h)
    assert r.json()["count"] == n_it and push.SENT[-1]["body"] == "Ertaga yig‘ilish"
    assert client.post("/api/admin/broadcast", json={"text": "x x"}, headers=w["tit"]).status_code == 403
    make_task(client, w["tit"])
    a = client.get("/api/admin/activity", headers=h).json()
    pax = [d for d in a["districts"] if d["id"] == "paxtaobod"][0]
    assert pax["schools"] >= 52 and pax["schools_empty"] < pax["schools"] and pax["tasks"] >= 1
    assert "inactive_count" in a and isinstance(a["top_schools"], list)


def test_admin_edit_user(client, w):  # noqa: F811
    h = w["admin"]
    eh = login(client, 3971, "x", "tahrir")
    register(client, eh, name="Tahrir Talaba", kind="student", school_id=w["s2"], class_name="5-A")
    m2 = uid(client, eh)
    r = client.post(f"/api/admin/users/{m2}/edit", json={"name": "tuzatilgan ism"}, headers=h)
    assert r.json()["name"] == "Tuzatilgan Ism"
    # band o‘ringa ko‘chirib bo‘lmaydi / нельзя на занятое место
    r = client.post(f"/api/admin/users/{m2}/edit", json={"kind": "coordinator", "level": "school", "place_id": w["s1"],
                                                         "direction": "it"}, headers=h)
    assert r.json()["error"] == "seat_taken"
    # o‘quvchiga aylantirish / сделать учеником
    r = client.post(f"/api/admin/users/{m2}/edit", json={"kind": "student", "place_id": w["s2"], "class_name": "8-B"},
                    headers=h)
    assert r.json()["kind"] == "student" and r.json()["class_name"] == "8-B" and r.json()["direction"] is None
    # va qaytarish / и вернуть
    r = client.post(f"/api/admin/users/{m2}/edit", json={"kind": "coordinator", "level": "school", "place_id": w["s2"],
                                                         "direction": "media"}, headers=h)
    assert r.json()["direction"] == "media" and r.json()["kind"] == "coordinator"
    client.post(f"/api/admin/users/{m2}/edit", json={"kind": "student", "place_id": w["s2"], "class_name": "5-A"}, headers=h)
    assert client.post(f"/api/admin/users/{m2}/edit", json={"name": "Boshqa Ism"}, headers=w["tit"]).status_code == 403


def test_export_xlsx(client, w, monkeypatch):  # noqa: F811
    _stub(monkeypatch)
    saved = {}
    monkeypatch.setattr(storage, "put", lambda path, data, mime: saved.__setitem__(path, data))
    from openpyxl import load_workbook
    for what in ("users", "tasks", "rating", "books"):
        r = client.post("/api/admin/export", json={"what": what}, headers=w["admin"])
        assert r.status_code == 200, r.text
        path = [p for p in saved if p.startswith(f"exports/{what}-")][0]
        assert r.json()["url"].endswith(path)
        ws = load_workbook(io.BytesIO(saved[path])).active
        assert ws.max_row >= 1
    users = load_workbook(io.BytesIO(saved[[p for p in saved if p.startswith("exports/users-")][0]])).active
    names = [row[0].value for row in users.iter_rows(min_row=2)]
    assert "P1 IT" in names
    assert client.post("/api/admin/export", json={"what": "users"}, headers=w["m1"]).status_code == 403


def test_book_edit_keeps_reads(client, w, monkeypatch):  # noqa: F811
    removed = _stub(monkeypatch)
    # katta muqova (64 KB dan ortiq) ham o‘tadi / большая обложка проходит
    up = client.post("/api/admin/books/upload", json={"size": 1000}, headers=w["admin"]).json()
    r = client.post("/api/admin/books", json={"direction": "media", "title": "Xato nom", "cover": big_jpeg(),
                                              "pdf_path": up["path"], "month": "Noyabr"}, headers=w["admin"])
    assert r.status_code == 200, r.text
    bid = r.json()["id"]
    client.post(f"/api/books/{bid}/read", json={"read": True}, headers=w["m1"])
    r = client.post("/api/admin/books", json={"direction": "media", "title": "To‘g‘ri nom", "edit": True,
                                              "author": "Muallif", "description": "Yangi tavsif", "month": "Noyabr"},
                    headers=w["admin"])
    assert r.json()["id"] == bid
    b = [x for x in client.get("/api/books", headers=w["m1"]).json()["books"] if x["direction"] == "media"][0]
    assert b["title"] == "To‘g‘ri nom" and b["reads"] == 1 and b["id"] == bid
    r = client.post("/api/admin/books", json={"direction": "media", "title": "To‘g‘ri nom", "edit": True, "cover": jpeg()},
                    headers=w["admin"])
    assert r.status_code == 200 and any(p.endswith("-cover.jpg") for p in removed)
    assert client.post("/api/admin/books", json={"direction": "talim", "title": "Yo‘q", "edit": True},
                       headers=w["admin"]).status_code == 404
    assert client.post("/api/admin/books/media/delete", headers=w["admin"]).status_code == 200


def test_task_event_edit(client, w):  # noqa: F811
    t = make_task(client, w["tit"]).json()
    body = {"title": "Yangi nom", "description": "aniqroq", "deadline": db.now() + 5 * 86400}
    assert client.post(f"/api/tasks/{t['id']}/edit", json=body, headers=w["m1"]).status_code == 403
    r = client.post(f"/api/tasks/{t['id']}/edit", json=body, headers=w["tit"])
    assert r.json()["title"] == "Yangi nom" and r.json()["deadline"] == body["deadline"]
    ev = client.post("/api/events", json={"title": "Yig‘ilish", "starts_at": db.now() + 3600, "audience": [
        {"level": "school", "district_ids": ["paxtaobod"], "directions": ["it"]}]}, headers=w["tit"]).json()
    r = client.post(f"/api/events/{ev['id']}/edit", json={"title": "Yig‘ilish (ko‘chirildi)", "place": "Zal",
                                                          "starts_at": db.now() + 7200}, headers=w["tit"])
    assert r.json()["title"] == "Yig‘ilish (ko‘chirildi)" and r.json()["place"] == "Zal"
    assert push.SENT[-1]["data"]["type"] == "event"  # vaqt o‘zgardi — xabar / время изменилось — уведомление
    assert client.post(f"/api/events/{ev['id']}/edit", json=body | {"starts_at": db.now() + 60}, headers=w["m1"]).status_code == 403


def test_channel_photo_rename_delete(client, w):  # noqa: F811
    h = w["admin"]
    ch = client.post("/api/channels", json={"title": "Sinov kanali", "mode": "announce", "audience": [
        {"level": "school", "district_ids": ["paxtaobod"], "directions": ["it"]}]}, headers=h).json()
    cid = ch["id"]
    r = client.post(f"/api/channels/{cid}/avatar", json={"data": big_jpeg()}, headers=h)
    assert r.status_code == 200 and r.json()["photo"]
    assert client.get(r.json()["photo"]).headers["content-type"] == "image/jpeg"
    got = client.get(f"/api/channels/{cid}", headers=h).json()
    assert got["photo"] == r.json()["photo"]
    assert client.post(f"/api/channels/{cid}/avatar", json={"data": jpeg()}, headers=w["m1"]).status_code == 403
    assert client.post(f"/api/channels/{cid}", json={"title": "Yangi nom"}, headers=h).status_code == 200
    assert client.get(f"/api/channels/{cid}", headers=h).json()["title_uz"] == "Yangi nom"
    assert client.post(f"/api/channels/{cid}/delete", headers=h).status_code == 200
    assert client.get(f"/api/channels/{cid}", headers=h).status_code == 404
