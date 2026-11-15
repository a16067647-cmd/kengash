"""Reyting va o‘quvchi chat qoidasi / рейтинг и правило чата учеников."""
import db
import rating

from test_api import client, login, register  # noqa: F401
from test_plan import w, uid, make_task, fake_storage  # noqa: F401


def test_task_rating(client, w):  # noqa: F811
    t = make_task(client, w["tit"], photo_required=False).json()
    m1, m2 = uid(client, w["m1"]), uid(client, w["m2"])
    # muddatidan oldin va hisobotsiz baholab bo‘lmaydi / до срока без отчёта нельзя
    assert client.post(f"/api/tasks/{t['id']}/rate", json={"user_id": m1, "value": 1}, headers=w["tit"]).json()["error"] == "too_early"
    assert client.post(f"/api/tasks/{t['id']}/submit", json={"comment": "Bajardim"}, headers=w["m1"]).status_code == 200
    # faqat vazifa bergan / только выдавший
    assert client.post(f"/api/tasks/{t['id']}/rate", json={"user_id": m1, "value": 1}, headers=w["tlid"]).status_code == 403
    assert client.post(f"/api/tasks/{t['id']}/rate", json={"user_id": m1, "value": 5}, headers=w["tit"]).status_code == 400
    r = client.post(f"/api/tasks/{t['id']}/rate", json={"user_id": m1, "value": 1}, headers=w["tit"])
    assert r.status_code == 200, r.text
    # qayta baholash qo‘shmaydi, almashtiradi / повторная оценка заменяет
    client.post(f"/api/tasks/{t['id']}/rate", json={"user_id": m1, "value": 1}, headers=w["tit"])
    with db.tx() as c:
        assert rating.score(c, m1) == 1
    people = {p["user"]["id"]: p for p in client.get(f"/api/tasks/{t['id']}", headers=w["tit"]).json()["people"]}
    assert people[m1]["points"] == 1 and people[m1]["can_rate"] and people[m2]["points"] == 0
    # o‘chirish (0) / снять оценку
    client.post(f"/api/tasks/{t['id']}/rate", json={"user_id": m1, "value": 0}, headers=w["tit"])
    with db.tx() as c:
        assert rating.score(c, m1) == 0
    client.post(f"/api/tasks/{t['id']}/rate", json={"user_id": m1, "value": 1}, headers=w["tit"])


def test_attendance_and_leaderboard(client, w):  # noqa: F811
    body = {"title": "Yig‘ilish", "starts_at": db.now() + 3600,
            "audience": [{"level": "school", "district_ids": ["paxtaobod"], "directions": ["it"]}]}
    eid = client.post("/api/events", json=body, headers=w["tit"]).json()["id"]
    m2 = uid(client, w["m2"])
    assert client.post(f"/api/events/{eid}/attendance", json={"user_id": m2, "came": False}, headers=w["tit"]).json()["error"] == "too_early"
    with db.tx() as c:
        c.x("UPDATE events SET starts_at=? WHERE id=?", (db.now() - 60, eid))
    assert client.post(f"/api/events/{eid}/attendance", json={"user_id": m2, "came": False}, headers=w["m1"]).status_code == 403
    assert client.post(f"/api/events/{eid}/attendance", json={"user_id": m2, "came": False}, headers=w["tit"]).status_code == 200
    ppl = {p["user"]["id"]: p for p in client.get(f"/api/events/{eid}", headers=w["tit"]).json()["people"]}
    assert ppl[m2]["came"] is False and ppl[m2]["can_mark"]

    # ochiq reyting: maktab koordinatorlari tuman ichida / открытый рейтинг: школы внутри района
    r = client.get("/api/rating", headers=w["m2"]).json()
    assert r["level"] == "school" and r["place_id"] == "paxtaobod" and r["quarter"]
    names = [p["user"]["name"] for p in r["people"]]
    assert names[0] == "P1 IT" and names[-1] == "P2 IT"
    assert r["me"]["score"] == -1 and r["me"]["rank"] == len(names)
    assert "U3 IT" not in names  # boshqa tuman / другой район
    sport = client.get("/api/rating", params={"direction": "sport"}, headers=w["m2"]).json()
    assert [p["user"]["name"] for p in sport["people"]] == ["P1 Sport"]
    # tuman koordinatorlari viloyat ichida / районы внутри области
    r = client.get("/api/rating", headers=w["tit"]).json()
    assert r["level"] == "district" and "Paxta IT" in [p["user"]["name"] for p in r["people"]]


def test_quarter_reset():
    import datetime
    ts = int(datetime.datetime(2026, 11, 15, 12, tzinfo=rating.TZ).timestamp())
    start, label = rating.quarter(ts)
    assert label == "2026 · IV"
    assert start == int(datetime.datetime(2026, 10, 1, tzinfo=rating.TZ).timestamp())


def test_students_text_only(client, w, monkeypatch):  # noqa: F811
    import storage
    monkeypatch.setattr(storage, "upload_url", lambda path: "https://storage.test/up/" + path)
    st = login(client, 3901, "x", "talaba_r")
    register(client, st, name="Rating Talaba", kind="student", school_id=w["s1"], class_name="8-A")
    chans = {c["auto_key"]: c for c in client.get("/api/channels", headers=st).json()["channels"]}
    chat = chans[f"chat:{w['s1']}"]
    assert chat["can_post"] and not chat["can_media"]
    assert client.post(f"/api/channels/{chat['id']}/messages", json={"text": "Salom"}, headers=st).status_code == 200
    from test_plan import jpeg
    assert client.post(f"/api/channels/{chat['id']}/photo", json={"data": jpeg()}, headers=st).json()["error"] == "text_only"
    r = client.post(f"/api/channels/{chat['id']}/upload", json={"kind": "file", "name": "a.pdf", "size": 10}, headers=st)
    assert r.json()["error"] == "text_only"
    r = client.post(f"/api/channels/{chat['id']}/upload", json={"kind": "voice", "name": "v.m4a", "size": 10, "duration": 3},
                    headers=st)
    assert r.status_code == 200
    r = client.post(f"/api/channels/{chat['id']}/messages",
                    json={"attachments": [{"kind": "photo", "path": f"{chat['id']}/x.jpg", "size": 10}]}, headers=st)
    assert r.status_code in (400, 403)
    # o‘quvchilar baholanmaydi va reytingni ko‘rmaydi / ученики не оцениваются и не видят рейтинг
    assert client.get("/api/rating", headers=st).status_code == 403
    # koordinator rasm yubora oladi / координатор может фото
    co = {c["auto_key"]: c for c in client.get("/api/channels", headers=w["m1"]).json()["channels"]}
    assert co[f"chat:{w['s1']}"]["can_media"]
