"""Chorak sertifikatlari / квартальные сертификаты."""
import app  # noqa: F401  (avval server / сначала сервер)
import certificates
import db
import storage

from test_api import client, login  # noqa: F401
from test_plan import w, uid  # noqa: F401


def test_certificates(client, w, monkeypatch):  # noqa: F811
    files = {}
    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "put", lambda path, data, mime: files.__setitem__(path, data))
    monkeypatch.setattr(storage, "sign", lambda paths, *a: {p: f"https://storage.test/{p}" for p in paths})
    start, end, label = certificates.quarter_range("prev")
    m1, m2, m1s = uid(client, w["m1"]), uid(client, w["m2"]), uid(client, w["m1s"])
    with db.tx() as c:
        for i, (u, v) in enumerate([(m1, 5), (m2, 3), (m1s, 3)]):
            c.x("INSERT INTO points (kind, ref_id, user_id, by_id, value, created_at) VALUES ('task', ?, ?, ?, ?, ?)",
                (f"cert{i}", u, m1, v, start + 100))
    try:
        assert client.get("/api/certificates", headers=w["m1"]).status_code == 403
        r = client.get("/api/certificates", headers=w["admin"]).json()
        assert r["quarter"] == label
        g = [x for x in r["groups"] if x["id"] == "paxtaobod"][0]
        assert [(x["rank"], x["user"]["name"]) for x in g["winners"]] == [(1, "P1 IT"), (2, "P1 Sport"), (2, "P2 IT")]
        pdf = client.post("/api/certificates/pdf", json={"group": "paxtaobod"}, headers=w["admin"]).json()
        assert pdf["count"] == 3 and pdf["url"].startswith("https://storage.test/exports/sertifikat-")
        data = list(files.values())[-1]
        assert data[:5] == b"%PDF-" and data.count(b"/Type /Page\n") + data.count(b"/Type /Page ") + data.count(b"/Type/Page") >= 1
        # g‘olib o‘zinikini oladi / победитель получает свой
        mine = client.get("/api/certificates/mine", headers=w["m1"]).json()["certificate"]
        assert mine["rank"] == 1 and mine["score"] == 5 and mine["group"] == "Paxtaobod tumani"
        assert client.post("/api/certificates/mine/pdf", headers=w["m1"]).json()["url"]
        assert client.get("/api/certificates/mine", headers=w["u3"]).json()["certificate"] is None
        assert client.post("/api/certificates/mine/pdf", headers=w["u3"]).status_code == 404
        # chorak boshida bot tabriklaydi (bir marta) / в начале квартала бот поздравляет (один раз)
        import telegram
        sent = []
        monkeypatch.setattr(telegram, "api", lambda m, p: sent.append((m, p)))
        qstart, _ = certificates.quarter(db.now())
        assert certificates.notify_winners(qstart + 5 * 86400) == 0  # kech / поздно
        n = certificates.notify_winners(qstart + 10 * 3600)
        assert n == 3 and any("1-o‘rin" in p["text"] for m, p in sent if m == "sendMessage")
        assert certificates.notify_winners(qstart + 11 * 3600) == 0
        # bo‘sh guruh / пустая группа
        assert client.post("/api/certificates/pdf", json={"group": "ulugnor"}, headers=w["admin"]).status_code == 404
    finally:
        with db.tx() as c:
            c.x("DELETE FROM points WHERE ref_id LIKE 'cert%'")
