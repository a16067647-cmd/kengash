"""Soddalashtirish va o‘sish: davomat tugmasi, ovozli hisobot / упрощение и рост: кнопка отметки, голосовой отчёт."""

import pytest

from test_api import client, login  # noqa: F401
from test_plan import w, make_task, uid, fake_storage  # noqa: F401

import db
import storage


def test_event_checkin_open_only_near_start(client, w):  # noqa: F811
    aud = [{"level": "school", "district_ids": ["paxtaobod"], "directions": ["it"]}]
    later = client.post("/api/events", json={"title": "Keyinroq", "starts_at": db.now() + 2 * 86400, "audience": aud},
                        headers=w["tit"]).json()
    soon = client.post("/api/events", json={"title": "Hozir", "starts_at": db.now() + 1800, "audience": aud},
                       headers=w["tit"]).json()
    assert client.get(f"/api/events/{later['id']}", headers=w["m1"]).json()["checkin_open"] is False
    assert client.get(f"/api/events/{soon['id']}", headers=w["m1"]).json()["checkin_open"] is True


@pytest.fixture
def upload_urls(monkeypatch):
    monkeypatch.setattr(storage, "upload_url", lambda path: f"https://storage.test/upload/{path}")


def test_voice_report(client, w, upload_urls):  # noqa: F811
    tid = make_task(client, w["tit"], photo_required=False).json()["id"]
    me = uid(client, w["m1"])
    # faqat vazifa egasi yuklay oladi / загружать может только исполнитель
    assert client.post(f"/api/tasks/{tid}/voice", json={"size": 1000, "mime": "audio/mp4", "duration": 4},
                       headers=w["u3"]).status_code == 403
    assert client.post(f"/api/tasks/{tid}/voice", json={"size": 1000, "mime": "image/png", "duration": 4},
                       headers=w["m1"]).status_code == 400
    r = client.post(f"/api/tasks/{tid}/voice", json={"size": 1000, "mime": "audio/mp4", "duration": 4}, headers=w["m1"]).json()
    assert r["path"].startswith(f"tasks/{tid}/{me}/") and r["path"].endswith(".m4a") and r["upload_url"]
    # boshqa birovning yo‘li — rad / чужой путь — отказ
    bad = client.post(f"/api/tasks/{tid}/submit", json={"voice": f"tasks/{tid}/someone/x.m4a"}, headers=w["m1"])
    assert bad.status_code == 400
    assert client.post(f"/api/tasks/{tid}/submit", json={"voice": r["path"], "voice_sec": 4.4}, headers=w["m1"]).status_code == 200
    mine = client.get(f"/api/tasks/{tid}", headers=w["m1"]).json()["my"]
    assert mine["voice"] == r["path"] and mine["voice_sec"] == 4 and mine["voice_url"].endswith(r["path"])
    giver = client.get(f"/api/tasks/{tid}", headers=w["tit"]).json()
    p = next(x for x in giver["people"] if x["user"]["id"] == me)
    assert p["status"] == "submitted" and p["voice_url"].endswith(r["path"]) and p["voice_sec"] == 4
