"""QR davomat: kod har daqiqada o‘zgaradi; to‘g‘ri kod → keldi va +1 / QR-посещаемость: код меняется; верный код → +1."""
import checkin
import db
import rating

from test_api import client, login  # noqa: F401
from test_plan import w, uid  # noqa: F401


def test_qr_checkin(client, w, monkeypatch):  # noqa: F811
    body = {"title": "QR uchrashuv", "starts_at": db.now() + 3 * 3600,
            "audience": [{"level": "school", "district_ids": ["paxtaobod"], "directions": ["it"]}]}
    eid = client.post("/api/events", json=body, headers=w["tit"]).json()["id"]
    m1 = uid(client, w["m1"])
    with db.tx() as c:
        before = rating.score(c, m1)
    # faqat tashkilotchi QR ko‘radi / QR видит только организатор
    assert client.get(f"/api/events/{eid}/qr", headers=w["m1"]).status_code == 403
    qr = client.get(f"/api/events/{eid}/qr", headers=w["tit"]).json()
    assert len(qr["code"]) == 6 and qr["qr"].endswith(f"?checkin={eid}&code={qr['code']}") and qr["open"] is False
    assert qr["total"] == 2 and qr["came"] == 0
    # juda erta / слишком рано
    r = client.post(f"/api/events/{eid}/checkin", json={"code": qr["code"]}, headers=w["m1"])
    assert r.json()["error"] == "checkin_closed"
    with db.tx() as c:
        c.x("UPDATE events SET starts_at=? WHERE id=?", (db.now() - 600, eid))
    code = client.get(f"/api/events/{eid}/qr", headers=w["tit"]).json()["code"]
    wrong = f"{(int(code) + 1) % 1_000_000:06d}"
    assert client.post(f"/api/events/{eid}/checkin", json={"code": wrong}, headers=w["m1"]).json()["error"] == "bad_code"
    # taklif qilinmagan / не приглашён
    assert client.post(f"/api/events/{eid}/checkin", json={"code": code}, headers=w["u3"]).json()["error"] == "not_invited"
    r = client.post(f"/api/events/{eid}/checkin", json={"code": code}, headers=w["m1"]).json()
    assert r["ok"] and r["already"] is False and r["title"] == "QR uchrashuv"
    assert client.post(f"/api/events/{eid}/checkin", json={"code": code}, headers=w["m1"]).json()["already"] is True
    with db.tx() as c:
        assert rating.score(c, m1) == before + 1
    ppl = {p["user"]["id"]: p for p in client.get(f"/api/events/{eid}", headers=w["tit"]).json()["people"]}
    assert ppl[m1]["checked_in"] and ppl[m1]["came"] is True and ppl[m1]["rsvp"] == "yes"
    assert client.get(f"/api/events/{eid}", headers=w["m1"]).json()["my_checkin"] is True
    assert client.get(f"/api/events/{eid}/qr", headers=w["tit"]).json()["came"] == 1
    # oldingi daqiqa kodi hali o‘tadi, undan eskisi — yo‘q / код прошлой минуты ещё действует, старше — нет
    with db.tx() as c:
        e = c.one("SELECT * FROM events WHERE id=?", (eid,))
    now_w = db.now() // checkin.STEP
    assert checkin.code_at(e["checkin_key"], now_w) != checkin.code_at(e["checkin_key"], now_w - 1)
    m2 = w["m2"]
    old = checkin.code_at(e["checkin_key"], now_w - 2)
    if old not in (checkin.code_at(e["checkin_key"], now_w), checkin.code_at(e["checkin_key"], now_w - 1)):
        assert client.post(f"/api/events/{eid}/checkin", json={"code": old}, headers=m2).json()["error"] == "bad_code"
    prev = checkin.code_at(e["checkin_key"], now_w - 1)
    assert client.post(f"/api/events/{eid}/checkin", json={"code": prev}, headers=m2).json()["ok"]
    # umumiy test bazasi: boshqa testlar uchun ballarni olib tashlaymiz / убираем баллы для других тестов
    with db.tx() as c:
        c.x("DELETE FROM points WHERE kind='event' AND ref_id=?", (eid,))
