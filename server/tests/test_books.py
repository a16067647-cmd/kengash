"""Oy kitobi / книга месяца."""
from test_api import client, login, register  # noqa: F401
from test_plan import w, jpeg, fake_storage  # noqa: F401

import storage


def _stub(monkeypatch):
    removed = []
    monkeypatch.setattr(storage, "upload_url", lambda path: "https://storage.test/up/" + path)
    monkeypatch.setattr(storage, "info", lambda path: 1234)
    monkeypatch.setattr(storage, "sign", lambda paths, seconds=3600: {p: f"https://storage.test/{p}" for p in paths})
    monkeypatch.setattr(storage, "remove", lambda paths: removed.extend(paths))
    return removed


def add_book(client, h, direction="it", title="Sun’iy intellekt asoslari"):  # noqa: F811
    up = client.post("/api/admin/books/upload", json={"size": 5_000_000}, headers=h)
    assert up.status_code == 200, up.text
    return client.post("/api/admin/books", json={"direction": direction, "title": title, "author": "A. Muallif",
                                                 "description": "Qisqacha", "month": "Noyabr", "cover": jpeg(),
                                                 "pdf_path": up.json()["path"]}, headers=h)


def test_books_flow(client, w, monkeypatch):  # noqa: F811
    removed = _stub(monkeypatch)
    # faqat admin qo‘shadi / добавляет только админ
    assert client.post("/api/admin/books/upload", json={"size": 10}, headers=w["tit"]).status_code == 403
    assert client.post("/api/admin/books/upload", json={"size": 60 * 1024 * 1024}, headers=w["admin"]).status_code == 413
    assert add_book(client, w["admin"], direction="nope").json()["error"] == "bad_direction"
    r = add_book(client, w["admin"])
    assert r.status_code == 200, r.text
    add_book(client, w["admin"], direction="sport", title="Chempion odatlari")

    # hamma ko‘radi, o‘quvchi ham; o‘z yo‘nalishi birinchi / видят все; своё направление первым
    st = login(client, 3951, "x", "kitobxon")
    register(client, st, name="Kitob Talaba", kind="student", school_id=w["s1"], class_name="9-A")
    books = client.get("/api/books", headers=st).json()["books"]
    assert {b["direction"] for b in books} == {"it", "sport"}
    assert books[0]["pdf_url"].endswith(".pdf") and books[0]["cover_url"]
    sport_first = client.get("/api/books", headers=w["m1s"]).json()["books"]
    assert sport_first[0]["direction"] == "sport"

    # «O‘qidim» va hisoblagich / «Прочитал» и счётчик
    it = [b for b in books if b["direction"] == "it"][0]
    assert client.post(f"/api/books/{it['id']}/read", json={"read": True}, headers=st).json()["reads"] == 1
    assert client.post(f"/api/books/{it['id']}/read", json={"read": True}, headers=w["m1"]).json()["reads"] == 2
    assert client.post(f"/api/books/{it['id']}/read", json={"read": False}, headers=w["m1"]).json()["reads"] == 1
    mine = [b for b in client.get("/api/books", headers=st).json()["books"] if b["direction"] == "it"][0]
    assert mine["my_read"] and mine["reads"] == 1

    # yangi kitob eskisini almashtiradi, eski fayllar o‘chadi / новая заменяет старую, старые файлы удаляются
    add_book(client, w["admin"], title="Yangi IT kitob")
    books = client.get("/api/books", headers=st).json()["books"]
    new_it = [b for b in books if b["direction"] == "it"][0]
    assert new_it["title"] == "Yangi IT kitob" and new_it["reads"] == 0 and len(books) == 2
    assert any(p.endswith(".pdf") for p in removed)
    assert client.post(f"/api/books/{it['id']}/read", json={}, headers=st).status_code == 404

    assert client.post("/api/admin/books/sport/delete", headers=w["tit"]).status_code == 403
    assert client.post("/api/admin/books/sport/delete", headers=w["admin"]).status_code == 200
    assert [b["direction"] for b in client.get("/api/books", headers=st).json()["books"]] == ["it"]
