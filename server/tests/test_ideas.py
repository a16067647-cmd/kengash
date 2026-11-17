"""Tashabbuslar / инициативы."""
import app  # noqa: F401
import push

from test_api import client, login  # noqa: F401
from test_plan import w, uid  # noqa: F401


def test_ideas(client, w):  # noqa: F811
    assert client.post("/api/ideas", json={"title": "x"}, headers=w["m1"]).json()["error"] == "bad_title"
    i = client.post("/api/ideas", json={"title": "Maktab hovlisida kitob javoni", "body": "Tanaffusda o‘qish uchun"},
                    headers=w["m1"]).json()
    assert i["district"]["id"] == "paxtaobod" and i["votes"] == 0 and i["mine"] and not i["can_answer"]
    # o‘ziga ovoz bera olmaydi / за свою голосовать нельзя
    assert client.post(f"/api/ideas/{i['id']}/vote", json={}, headers=w["m1"]).json()["error"] == "own_idea"
    assert client.post(f"/api/ideas/{i['id']}/vote", json={}, headers=w["m2"]).json()["votes"] == 1
    assert client.post(f"/api/ideas/{i['id']}/vote", json={}, headers=w["m1s"]).json()["my_vote"] is True
    lst = client.get("/api/ideas", headers=w["m2"]).json()
    assert lst["district"] == "paxtaobod" and lst["ideas"][0]["id"] == i["id"] and lst["ideas"][0]["votes"] == 2
    # boshqa tuman «o‘zimniki»da ko‘rmaydi, «hammasi»da ko‘radi / другой район видит только во «всех»
    assert all(x["id"] != i["id"] for x in client.get("/api/ideas", headers=w["u3"]).json()["ideas"])
    assert any(x["id"] == i["id"] for x in client.get("/api/ideas", params={"scope": "all"}, headers=w["u3"]).json()["ideas"])
    # javob: oddiy koordinator — yo‘q; tuman Lideri — ha / ответ: координатор — нет; Лидер района — да
    assert client.post(f"/api/ideas/{i['id']}/answer", json={"status": "planned"}, headers=w["tit"]).status_code == 403
    push.SENT.clear()
    r = client.post(f"/api/ideas/{i['id']}/answer", json={"status": "planned", "reply": "Keyingi oy qilamiz"},
                    headers=w["tlid"]).json()
    assert r["status"] == "planned" and r["replied_by"]["name"] == "Paxta Lider"
    assert push.SENT[-1]["users"] == [uid(client, w["m1"])]
    # rad etilganlar ro‘yxatda ko‘rinmaydi / отклонённые не показываются
    client.post(f"/api/ideas/{i['id']}/answer", json={"status": "declined"}, headers=w["admin"])
    assert all(x["id"] != i["id"] for x in client.get("/api/ideas", headers=w["m2"]).json()["ideas"])
    assert client.post(f"/api/ideas/{i['id']}/delete", headers=w["m2"]).status_code == 403
    assert client.post(f"/api/ideas/{i['id']}/delete", headers=w["m1"]).json()["ok"]
