"""Kanallar testlari / тесты каналов:  cd server && python -m pytest -q"""

import base64
import io

import pytest

from test_api import client, login, seat, give_seat  # noqa: F401  (umumiy server / общий сервер)

import storage


@pytest.fixture(autouse=True)
def fake_storage(monkeypatch):
    files = {}
    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "upload_url", lambda path: f"https://storage.test/upload/{path}")
    monkeypatch.setattr(storage, "put", lambda path, data, mime: files.__setitem__(path, data))
    monkeypatch.setattr(storage, "info", lambda path: len(files[path]) if path in files else None)
    monkeypatch.setattr(storage, "sign", lambda paths: {p: f"https://storage.test/signed/{p}" for p in paths})
    removed = []
    monkeypatch.setattr(storage, "remove", lambda paths: removed.extend(paths))
    files["__removed__"] = removed
    return files


@pytest.fixture(scope="module")
def ch(client):  # noqa: F811
    """Marhamat: tuman IT, tuman Lider, maktab 1 IT, maktab 2 IT, maktab 1 Sport; Baliqchi maktab IT; viloyat IT."""
    admin = login(client, 1, "Admin", "boss")
    client.post("/api/admin/schools/bulk", json={"district_id": "marhamat", "spec": "1-2"}, headers=admin)
    client.post("/api/admin/schools/bulk", json={"district_id": "oltinkol", "spec": "7"}, headers=admin)
    sch = {s["number"]: s["id"] for s in client.get("/api/schools", params={"district_id": "marhamat"}, headers=admin).json()["schools"]}
    other = client.get("/api/schools", params={"district_id": "oltinkol"}, headers=admin).json()["schools"][0]["id"]
    w = {"admin": admin, "s1": sch[1], "s2": sch[2], "other": other}
    vit = login(client, 2001, "Viloyat IT 2", "vit2")
    # viloyat IT o‘rni test_api da band bo‘lishi mumkin — admin o‘rnini almashtiradi / место может быть занято
    uid = client.get("/api/me", headers=vit).json()["id"]
    holder = [s for s in client.get("/api/seats", params={"level": "region", "place_id": "andijon"}, headers=admin).json()["seats"]
              if s["direction"] == "it"][0]["user"]
    if holder:
        client.post("/api/seats/free", json=seat("region", "andijon", "it"), headers=admin)
    assert client.post(f"/api/admin/users/{uid}/seat", json=seat("region", "andijon", "it"), headers=admin).status_code == 200
    w["vit"] = vit
    w["tit"] = login(client, 2002, "Marhamat IT", "mit")
    give_seat(client, admin, w["tit"], seat("district", "marhamat", "it"))
    w["tlid"] = login(client, 2003, "Marhamat Lider", "mlid")
    give_seat(client, admin, w["tlid"], seat("district", "marhamat", "lider"))
    w["m1"] = login(client, 2004, "M1 IT", "m1it")
    give_seat(client, w["tit"], w["m1"], seat("school", sch[1], "it"))
    w["m2"] = login(client, 2005, "M2 IT", "m2it")
    give_seat(client, w["tit"], w["m2"], seat("school", sch[2], "it"))
    w["m1s"] = login(client, 2006, "M1 Sport", "m1sp")
    give_seat(client, w["tlid"], w["m1s"], seat("school", sch[1], "sport"))
    w["o7"] = login(client, 2007, "Oltinkol IT", "o7it")
    give_seat(client, admin, w["o7"], seat("school", other, "it"))
    return w


def chans(client, h):  # noqa: F811
    r = client.get("/api/channels", headers=h)
    assert r.status_code == 200, r.text
    return {c["auto_key"] or c["title_uz"]: c for c in r.json()["channels"]}


def test_auto_channels(client, ch):  # noqa: F811
    m1 = chans(client, ch["m1"])
    assert set(m1) == {"all", f"school:{ch['s1']}", f"news:{ch['s1']}", f"chat:{ch['s1']}", "dd:marhamat:it"}
    assert m1[f"news:{ch['s1']}"]["can_post"] and m1[f"news:{ch['s1']}"]["mode"] == "announce"
    assert m1["all"]["mode"] == "announce" and not m1["all"]["can_post"]
    tit = chans(client, ch["tit"])
    assert set(tit) == {"all", "dd:marhamat:it", "dt:marhamat", "rd:andijon:it"}
    assert tit["dd:marhamat:it"]["role"] == "admin" and tit["dt:marhamat"]["role"] == "member"
    assert chans(client, ch["tlid"])["dt:marhamat"]["role"] == "admin"
    vit = chans(client, ch["vit"])
    assert {"all", "rd:andijon:it", "rt:andijon"} <= set(vit)
    assert not vit["all"]["can_post"] and vit["rd:andijon:it"]["role"] == "admin"  # faqat viloyat Lideri / только Лидер
    assert "Marhamat tumani · IT va sun’iy intellekt" == m1["dd:marhamat:it"]["title_uz"]
    assert m1[f"school:{ch['s1']}"]["members"] == 2  # IT + Sport


def test_messages_and_unread(client, ch):  # noqa: F811
    cid = chans(client, ch["m1"])["dd:marhamat:it"]["id"]
    r = client.post(f"/api/channels/{cid}/messages", json={"text": "Salom, IT jamoasi!"}, headers=ch["m1"])
    assert r.status_code == 200 and r.json()["user"]["name"] == "M1 IT"
    assert chans(client, ch["m2"])["dd:marhamat:it"]["unread"] == 1
    assert chans(client, ch["m1"])["dd:marhamat:it"]["unread"] == 0
    assert chans(client, ch["m2"])["dd:marhamat:it"]["last"]["text"] == "Salom, IT jamoasi!"
    msgs = client.get(f"/api/channels/{cid}/messages", headers=ch["m2"]).json()["messages"]
    assert msgs[0]["text"] == "Salom, IT jamoasi!"
    client.post(f"/api/channels/{cid}/read", json={"seq": msgs[0]["seq"]}, headers=ch["m2"])
    assert chans(client, ch["m2"])["dd:marhamat:it"]["unread"] == 0
    # boshqa tuman / другой район
    assert client.get(f"/api/channels/{cid}/messages", headers=ch["o7"]).status_code == 403
    assert client.post(f"/api/channels/{cid}/messages", json={"text": "x"}, headers=ch["m1s"]).status_code == 403
    # admin hamma kanalni ko‘radi / админ видит все каналы
    assert client.get(f"/api/channels/{cid}/messages", headers=ch["admin"]).status_code == 200
    # javob / ответ
    r = client.post(f"/api/channels/{cid}/messages", json={"text": "Vaalaykum", "reply_to": msgs[0]["id"]}, headers=ch["tit"])
    assert r.json()["reply"]["text"] == "Salom, IT jamoasi!"
    assert client.post(f"/api/channels/{cid}/messages", json={"text": "  "}, headers=ch["m1"]).status_code == 400


def test_announcements(client, ch):  # noqa: F811
    cid = chans(client, ch["m1"])["all"]["id"]
    assert client.post(f"/api/channels/{cid}/messages", json={"text": "x"}, headers=ch["m1"]).json()["error"] == "read_only"
    assert client.post(f"/api/channels/{cid}/messages", json={"text": "E’lon!"}, headers=ch["vit"]).status_code == 403
    assert client.post(f"/api/channels/{cid}/messages", json={"text": "Admin e’loni"}, headers=ch["admin"]).status_code == 200
    msgs = client.get(f"/api/channels/{cid}/messages", headers=ch["m1"]).json()["messages"]
    assert "seen" in msgs[0]


def test_custom_channel(client, ch):  # noqa: F811
    body = {"title": "IT tanlovi", "mode": "announce", "icon": "🏆",
            "audience": [{"level": "school", "district_ids": ["marhamat"], "directions": ["it"]}]}
    assert client.post("/api/channels", json=body, headers=ch["m1"]).status_code == 403
    r = client.post("/api/channels", json=body, headers=ch["tit"])
    assert r.status_code == 200, r.text
    cid = r.json()["id"]
    assert r.json()["members"] == 3  # egasi + 2 maktab IT
    assert "IT tanlovi" in chans(client, ch["m1"]) and "IT tanlovi" not in chans(client, ch["m1s"])
    assert client.post(f"/api/channels/{cid}/messages", json={"text": "x"}, headers=ch["m1"]).status_code == 403
    assert client.post(f"/api/channels/{cid}/messages", json={"text": "Tanlov ertaga"}, headers=ch["tit"]).status_code == 200
    # boshqa tumandagi odamni qo‘sha olmaydi / не может добавить из другого района
    o7 = client.get("/api/me", headers=ch["o7"]).json()["id"]
    assert client.post(f"/api/channels/{cid}/members/add", json={"user_ids": [o7]}, headers=ch["tit"]).json()["added"] == 0
    # boshqa yo‘nalishni ham / и другое направление
    m1s = client.get("/api/me", headers=ch["m1s"]).json()["id"]
    assert client.post(f"/api/channels/{cid}/members/add", json={"user_ids": [m1s]}, headers=ch["tit"]).json()["added"] == 0
    # rejim almashtirish / смена режима
    assert client.post(f"/api/channels/{cid}", json={"mode": "group"}, headers=ch["m1"]).status_code == 403
    client.post(f"/api/channels/{cid}", json={"mode": "group"}, headers=ch["tit"])
    assert client.post(f"/api/channels/{cid}/messages", json={"text": "Tayyormiz"}, headers=ch["m1"]).status_code == 200
    # chiqish va olib tashlash / выход и удаление
    m2 = client.get("/api/me", headers=ch["m2"]).json()["id"]
    assert client.post(f"/api/channels/{cid}/members/remove", json={"user_id": m2}, headers=ch["tit"]).status_code == 200
    assert client.get(f"/api/channels/{cid}/messages", headers=ch["m2"]).status_code == 403
    assert client.post(f"/api/channels/{cid}/leave", headers=ch["m1"]).status_code == 200
    assert client.post(f"/api/channels/{cid}/leave", headers=ch["tit"]).status_code == 400
    # viloyat koordinatori boshqa tumanni qo‘sha oladi / областной может добавить другой район
    r = client.post("/api/channels", json={"title": "Viloyat IT", "mode": "group",
                                           "audience": [{"level": "school", "directions": ["it"]}]}, headers=ch["vit"])
    names = [m["name"] for m in client.get(f"/api/channels/{r.json()['id']}/members", headers=ch["vit"]).json()["members"]]
    assert "Oltinkol IT" in names and "M1 IT" in names and "M1 Sport" not in names
    assert client.post(f"/api/channels/{cid}/delete", headers=ch["m2"]).status_code == 403
    assert client.post(f"/api/channels/{cid}/delete", headers=ch["tit"]).status_code == 200


def test_edit_delete_pin(client, ch):  # noqa: F811
    cid = chans(client, ch["m1"])["dd:marhamat:it"]["id"]
    mid = client.post(f"/api/channels/{cid}/messages", json={"text": "xato"}, headers=ch["m1"]).json()["id"]
    assert client.post(f"/api/messages/{mid}/edit", json={"text": "to‘g‘ri"}, headers=ch["m2"]).status_code == 403
    assert client.post(f"/api/messages/{mid}/edit", json={"text": "to‘g‘ri"}, headers=ch["m1"]).status_code == 200
    m = [x for x in client.get(f"/api/channels/{cid}/messages", headers=ch["m2"]).json()["messages"] if x["id"] == mid][0]
    assert m["text"] == "to‘g‘ri" and m["edited"]
    assert client.post(f"/api/messages/{mid}/pin", json={}, headers=ch["m1"]).status_code == 403
    assert client.post(f"/api/messages/{mid}/pin", json={}, headers=ch["tit"]).status_code == 200
    assert client.get(f"/api/channels/{cid}", headers=ch["m2"]).json()["pinned_message"]["id"] == mid
    assert client.post(f"/api/messages/{mid}/delete", headers=ch["m2"]).status_code == 403
    assert client.post(f"/api/messages/{mid}/delete", headers=ch["tit"]).status_code == 200  # kanal admini
    m = [x for x in client.get(f"/api/channels/{cid}/messages", headers=ch["m2"]).json()["messages"] if x["id"] == mid][0]
    assert m["deleted"] and m["text"] == ""
    assert client.get(f"/api/channels/{cid}", headers=ch["m2"]).json()["pinned"] is None


def test_files(client, ch, fake_storage):  # noqa: F811
    cid = chans(client, ch["m1"])["dd:marhamat:it"]["id"]
    up = lambda body: client.post(f"/api/channels/{cid}/upload", json=body, headers=ch["m1"])  # noqa: E731
    assert up({"kind": "file", "name": "virus.exe", "size": 10, "mime": "application/octet-stream"}).json()["error"] == "bad_type"
    assert up({"kind": "video", "name": "a.mp4", "size": 60 * 1024 * 1024, "mime": "video/mp4"}).status_code == 413
    assert up({"kind": "voice", "name": "v.m4a", "size": 1000, "mime": "audio/mp4", "duration": 400}).json()["error"] == "too_long"
    assert up({"kind": "file", "name": "x.pdf", "size": 30 * 1024 * 1024, "mime": "application/pdf"}).status_code == 413
    r = up({"kind": "file", "name": "Reja 2026.pdf", "size": 1234, "mime": "application/pdf"})
    assert r.status_code == 200
    path = r.json()["path"]
    assert path.startswith(cid + "/") and r.json()["upload_url"].startswith("https://storage.test/upload/")
    # yuklanmagan fayl bilan xabar rad etiladi / сообщение с незагруженным файлом отклоняется
    att = {"kind": "file", "path": path, "name": "Reja 2026.pdf", "mime": "application/pdf"}
    assert client.post(f"/api/channels/{cid}/messages", json={"attachments": [att]}, headers=ch["m1"]).json()["error"] == "bad_attachment"
    fake_storage[path] = b"%PDF" * 300
    r = client.post(f"/api/channels/{cid}/messages", json={"attachments": [att]}, headers=ch["m1"])
    assert r.status_code == 200 and r.json()["attachments"][0]["url"].startswith("https://storage.test/signed/")
    assert r.json()["attachments"][0]["size"] == 1200
    # boshqa kanal yo‘li / путь другого канала
    bad = dict(att, path="other-channel/x.pdf")
    assert client.post(f"/api/channels/{cid}/messages", json={"attachments": [bad]}, headers=ch["m1"]).status_code == 400
    # surat: EXIF o‘chadi, o‘lcham kichrayadi / фото: EXIF удаляется, размер уменьшается
    from PIL import Image
    im = Image.new("RGB", (3000, 2000), (91, 45, 201))
    exif = Image.Exif()
    exif[0x8825] = {2: (40.7, 0.0, 0.0)}
    buf = io.BytesIO()
    im.save(buf, "JPEG", exif=exif)
    r = client.post(f"/api/channels/{cid}/photo", json={"data": base64.b64encode(buf.getvalue()).decode()}, headers=ch["m1"])
    assert r.status_code == 200, r.text
    p = r.json()
    assert (p["w"], p["h"]) == (1600, 1067)
    out = Image.open(io.BytesIO(fake_storage[p["path"]]))
    assert not out.getexif()
    r = client.post(f"/api/channels/{cid}/messages", json={"text": "Rasm", "attachments": [p]}, headers=ch["m1"])
    assert r.json()["attachments"][0]["kind"] == "photo"
    # e’lon kanaliga yuklab bo‘lmaydi / в канал объявлений загрузить нельзя
    all_id = chans(client, ch["m1"])["all"]["id"]
    assert client.post(f"/api/channels/{all_id}/upload", json={"kind": "file", "name": "a.pdf", "size": 5, "mime": "application/pdf"},
                       headers=ch["m1"]).status_code == 403


def test_report_and_block(client, ch):  # noqa: F811
    cid = chans(client, ch["m1"])[f"school:{ch['s1']}"]["id"]
    bad = login(client, 2010, "Yomon Bola", "yomon")
    give_seat(client, ch["tlid"], bad, seat("school", ch["s1"], "media"))
    mid = client.post(f"/api/channels/{cid}/messages", json={"text": "haqorat"}, headers=bad).json()["id"]
    assert client.post(f"/api/messages/{mid}/report", json={"reason": "insult"}, headers=ch["m1"]).status_code == 200
    assert client.post(f"/api/messages/{mid}/report", json={"reason": "insult"}, headers=ch["o7"]).status_code == 403
    assert client.get("/api/admin/reports", headers=ch["m1"]).status_code == 403
    reps = client.get("/api/admin/reports", headers=ch["admin"]).json()["reports"]
    rep = [r for r in reps if r["message"] and r["message"]["id"] == mid][0]
    assert rep["reason"] == "insult" and rep["message"]["text"] == "haqorat"
    assert client.post(f"/api/admin/reports/{rep['id']}", json={"action": "block"}, headers=ch["admin"]).status_code == 200
    assert client.get("/api/me", headers=bad).status_code == 401
    msgs = client.get(f"/api/channels/{cid}/messages", headers=ch["m1"]).json()["messages"]
    assert [m for m in msgs if m["id"] == mid][0]["deleted"]
    assert not [r for r in client.get("/api/admin/reports", headers=ch["admin"]).json()["reports"] if r["id"] == rep["id"]]


def test_seat_change_updates_channels(client, ch):  # noqa: F811
    h = login(client, 2020, "Ko‘chuvchi", "kochuvchi")
    give_seat(client, ch["tlid"], h, seat("school", ch["s2"], "ekologiya"))
    assert f"school:{ch['s2']}" in chans(client, h)
    client.post("/api/seats/free", json=seat("school", ch["s2"], "ekologiya"), headers=ch["tlid"])
    assert set(chans(client, h)) == {"all"}


def test_delete_account_removes_messages(client, ch, fake_storage):  # noqa: F811
    h = login(client, 2030, "Ketuvchi", "ketuvchi")
    give_seat(client, ch["tlid"], h, seat("school", ch["s2"], "madaniyat"))
    cid = chans(client, h)[f"school:{ch['s2']}"]["id"]
    p = client.post(f"/api/channels/{cid}/photo", json={"data": _tiny_jpeg()}, headers=h).json()
    client.post(f"/api/channels/{cid}/messages", json={"text": "Xayr", "attachments": [p]}, headers=h)
    assert client.post("/api/me/delete", json={"confirm": "ochirish"}, headers=h).status_code == 200
    msgs = client.get(f"/api/channels/{cid}/messages", headers=ch["admin"]).json()["messages"]
    assert not [m for m in msgs if m["text"] == "Xayr"]
    assert p["path"] in fake_storage["__removed__"]


def _tiny_jpeg():
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", (40, 40), (1, 2, 3)).save(buf, "JPEG")
    return base64.b64encode(buf.getvalue()).decode()


def test_websocket_live(client, ch):  # noqa: F811
    token = ch["m2"]["Authorization"][7:]
    with client.websocket_connect(f"/api/ws?token={token}") as ws:
        assert ws.receive_json()["type"] == "hello"
        cid = chans(client, ch["m1"])["dd:marhamat:it"]["id"]
        client.post(f"/api/channels/{cid}/messages", json={"text": "Jonli!"}, headers=ch["m1"])
        ev = ws.receive_json()
        assert ev["type"] == "message.new" and ev["message"]["text"] == "Jonli!" and ev["channel_id"] == cid
    with pytest.raises(Exception):
        with client.websocket_connect("/api/ws?token=bad") as ws:
            ws.receive_json()


def test_polls(client, ch):  # noqa: F811
    """So‘rovnoma: ochish, ovoz, o‘zgartirish, yopish / опрос: создать, голос, смена, закрыть."""
    import realtime
    cid = chans(client, ch["m1"])["dd:marhamat:it"]["id"]
    bad = client.post(f"/api/channels/{cid}/polls", json={"question": "Qachon?", "options": ["Shanba"]}, headers=ch["tit"])
    assert bad.json()["error"] == "bad_options"
    r = client.post(f"/api/channels/{cid}/polls", json={"question": "Uchrashuv qaysi kuni?",
                                                         "options": ["Shanba", "Yakshanba", "Shanba", " "]}, headers=ch["tit"])
    assert r.status_code == 200, r.text
    poll = r.json()["attachments"][0]["poll"]
    assert r.json()["text"] == "Uchrashuv qaysi kuni?" and [o["text"] for o in poll["options"]] == ["Shanba", "Yakshanba"]
    pid = poll["id"]
    assert chans(client, ch["m2"])["dd:marhamat:it"]["last"]["kind"] == "poll"
    # boshqa kanal a’zosi emas / не участник
    assert client.post(f"/api/polls/{pid}/vote", json={"options": [0]}, headers=ch["o7"]).status_code == 403
    assert client.post(f"/api/polls/{pid}/vote", json={"options": [0, 1]}, headers=ch["m1"]).json()["error"] == "one_option"
    sent = []
    orig = realtime.send
    realtime.send = lambda ids, ev: sent.append((ids, ev))
    try:
        v = client.post(f"/api/polls/{pid}/vote", json={"options": [0]}, headers=ch["m1"]).json()
    finally:
        realtime.send = orig
    assert v["my"] == [0] and v["options"][0]["count"] == 1 and v["voters"] == 1
    assert sent and sent[0][1]["type"] == "poll.update" and sent[0][1]["poll"]["options"][0]["count"] == 1
    client.post(f"/api/polls/{pid}/vote", json={"options": [1]}, headers=ch["m2"])
    v = client.post(f"/api/polls/{pid}/vote", json={"options": [1]}, headers=ch["m1"]).json()  # fikrini o‘zgartirdi
    assert [o["count"] for o in v["options"]] == [0, 2] and v["my"] == [1]
    msgs = client.get(f"/api/channels/{cid}/messages", headers=ch["m2"]).json()["messages"]
    assert msgs[0]["attachments"][0]["poll"]["my"] == [1]
    # faqat muallif yoki moderator yopadi / закрывает автор или модератор
    assert client.post(f"/api/polls/{pid}/close", headers=ch["m2"]).status_code == 403
    assert client.post(f"/api/polls/{pid}/close", headers=ch["tit"]).json()["closed"] is True
    assert client.post(f"/api/polls/{pid}/vote", json={"options": [0]}, headers=ch["m2"]).json()["error"] == "poll_closed"
    # o‘quvchi so‘rovnoma ochmaydi; mijoz «poll» biriktirmasini yubora olmaydi
    r = client.post(f"/api/channels/{cid}/messages", json={"text": "x", "attachments": [{"kind": "poll", "poll_id": pid}]},
                    headers=ch["m1"])
    assert r.status_code == 400
