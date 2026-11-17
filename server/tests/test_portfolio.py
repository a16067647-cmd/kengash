"""Portfolio: ichki ko‘rinish va ochiq havola / портфолио: внутренний вид и открытая ссылка."""
import app  # noqa: F401
import db

from test_api import client, login  # noqa: F401
from test_plan import w, uid, make_task  # noqa: F401


def test_portfolio(client, w):  # noqa: F811
    t = make_task(client, w["tit"], title="Portfolio vazifasi", photo_required=False).json()
    assert client.post(f"/api/tasks/{t['id']}/submit", json={"comment": "Tayyor"}, headers=w["m1"]).status_code == 200
    m1 = uid(client, w["m1"])
    p = client.get("/api/portfolio/me", headers=w["m1"]).json()
    assert p["user"]["name"] == "P1 IT" and p["stats"]["tasks"] >= 1 and not p["shared"]
    assert any(x["title"] == "Portfolio vazifasi" and x["by"] == "Paxta IT" for x in p["tasks"])
    # boshqalar ko‘ra oladi (ruxsat bo‘yicha), lekin havolasiz / другие видят, но без ссылки
    other = client.get(f"/api/portfolio/{m1}", headers=w["tit"]).json()
    assert other["user"]["id"] == m1 and "share_url" not in other
    # ochiq havola / открытая ссылка
    r = client.post("/api/portfolio/share", headers=w["m1"]).json()
    token = r["share_url"].rsplit("/", 1)[1]
    page = client.get(f"/p/{token}")
    assert page.status_code == 200 and "P1 IT" in page.text and "Portfolio vazifasi" in page.text
    assert "style-src 'unsafe-inline'" in page.headers["content-security-policy"]
    assert page.headers["x-robots-tag"] == "noindex"
    # o‘chirilgandan keyin eski havola ishlamaydi / после отключения ссылка не работает
    client.post("/api/portfolio/share", params={"on": False}, headers=w["m1"])
    assert client.get(f"/p/{token}").status_code == 404
    assert client.get("/p/xxxxxxxxxxxx").status_code == 404
    with db.tx() as c:
        c.x("UPDATE users SET share_token='' WHERE id=?", (m1,))
