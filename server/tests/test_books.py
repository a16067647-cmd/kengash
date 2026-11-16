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
    assert len(books[0]["colors"]) == 3 and all(x.startswith("#") for x in books[0]["colors"])
    sport_first = client.get("/api/books", headers=w["m1s"]).json()["books"]
    assert sport_first[0]["direction"] == "sport"

    # «O‘qidim» va hisoblagich / «Прочитал» и счётчик
    it = [b for b in books if b["direction"] == "it"][0]
    assert client.post(f"/api/books/{it['id']}/read", json={"read": True}, headers=st).json()["reads"] == 1
    assert client.post(f"/api/books/{it['id']}/read", json={"read": True}, headers=w["m1"]).json()["reads"] == 2
    assert client.post(f"/api/books/{it['id']}/read", json={"read": False}, headers=w["m1"]).json()["reads"] == 1
    mine = [b for b in client.get("/api/books", headers=st).json()["books"] if b["direction"] == "it"][0]
    assert mine["my_read"] and mine["reads"] == 1
    assert [r["name"] for r in mine["readers"]] == ["Kitob Talaba"]

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


def _book_photo(w=185, h=234):
    """Oq fonda turgan kichik kitob rasmi (umurtqa va soya bilan) / маленькое фото книги на белом фоне."""
    import io
    from PIL import Image, ImageDraw
    im = Image.new("RGB", (w, h), (255, 255, 255))
    d = ImageDraw.Draw(im)
    d.rectangle((28, 22, 157, 206), fill=(228, 222, 210))  # old yuz / лицо
    d.rectangle((28, 22, 37, 206), fill=(200, 196, 188))  # umurtqa / корешок
    d.line((37, 22, 37, 206), fill=(110, 110, 110), width=1)  # bukilish / сгиб
    d.rectangle((60, 80, 130, 120), fill=(205, 180, 120))  # oltin sarlavha / золотой заголовок
    out = io.BytesIO()
    im.save(out, "JPEG", quality=80)
    return out.getvalue()


def test_cover_enhance_trims_and_upscales():
    import io
    from PIL import Image
    import cover
    out = Image.open(io.BytesIO(cover.enhance(_book_photo()))).convert("RGB")
    assert out.height >= 400  # kattalashtirildi (silliq) / увеличена (плавно)
    # oq fon va umurtqa qolmadi: chap va o‘ng chetlar muqova rangida / нет белого фона и корешка
    for x in (2, out.width - 3):
        r, g, b = out.getpixel((x, out.height // 2))
        assert 200 < r < 245 and abs(r - b) > 8, (x, r, g, b)


def test_cover_enhance_keeps_flat_cover():
    import io
    from PIL import Image
    import cover
    im = Image.new("RGB", (600, 900), (20, 60, 140))
    im.paste((250, 200, 0), (0, 0, 600, 120))
    b = io.BytesIO()
    im.save(b, "JPEG")
    out = Image.open(io.BytesIO(cover.enhance(b.getvalue())))
    assert abs(out.width / out.height - 600 / 900) < 0.01  # hech narsa kesilmadi / ничего не обрезано


def test_cover_uses_online_original_only_when_it_matches(monkeypatch):
    import io
    from PIL import Image, ImageDraw
    import cover
    small = Image.open(io.BytesIO(_book_photo())).convert("RGB")
    # asl muqova: xuddi shu dizayn, lekin katta / оригинал: тот же дизайн, но крупный
    big = Image.new("RGB", (400, 600), (228, 222, 210))
    ImageDraw.Draw(big).rectangle((100, 180, 330, 320), fill=(205, 180, 120))
    assert cover.similar(small, big)
    other = Image.new("RGB", (400, 600), (20, 60, 140))
    ImageDraw.Draw(other).rectangle((40, 420, 360, 560), fill=(250, 250, 250))
    assert not cover.similar(small, other)
    seen = {}

    def fake(title, author, uploaded):
        seen["q"] = (title, author)
        return big

    monkeypatch.setattr(cover, "find_online", fake)
    out = Image.open(io.BytesIO(cover.enhance(_book_photo(), "Atomic Habits", "James Clear"))).convert("RGB")
    assert seen["q"] == ("Atomic Habits", "James Clear")
    assert abs(out.width / out.height - 400 / 600) < 0.01 and out.height >= 1000
