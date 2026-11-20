"""Dushanba dayjesti / дайджест понедельника."""
import datetime

import app  # noqa: F401
import db
import digest
import telegram
from rating import TZ

from test_api import client, login  # noqa: F401
from test_plan import w, uid, make_task  # noqa: F401


def test_monday_digest(client, w, monkeypatch):  # noqa: F811
    sent = []
    monkeypatch.setattr(telegram, "api", lambda m, p: sent.append((m, p)))
    # Kelasi dushanba 9:00 — vazifa muddati shu haftaga to‘g‘ri keladi (testning natijasi hafta kuniga bog‘liq emas).
    # Следующий понедельник 9:00 — срок задачи внутри этой недели (результат не зависит от дня недели).
    d = datetime.datetime.fromtimestamp(db.now(), TZ)
    monday = (datetime.datetime(d.year, d.month, d.day, 9, 0, tzinfo=TZ)
              - datetime.timedelta(days=d.weekday()) + datetime.timedelta(days=7))
    make_task(client, w["tit"], title="Dayjest vazifasi", deadline=int((monday + datetime.timedelta(days=2)).timestamp()))
    sunday = monday - datetime.timedelta(days=1)
    assert digest.send_weekly(int(sunday.timestamp())) == 0  # yakshanba — yo‘q / воскресенье — нет
    assert digest.send_weekly(int((monday - datetime.timedelta(hours=2)).timestamp())) == 0  # 7:00 — erta
    n = digest.send_weekly(int(monday.timestamp()))
    assert n >= 2
    msgs = {p["chat_id"]: p["text"] for m, p in sent if m == "sendMessage"}
    # dayjestda faqat 3 ta vazifa nomi chiqadi (eng yaqin muddatlar) — shuning uchun bo‘limni tekshiramiz
    # в дайджесте видны только 3 ближайшие задачи — поэтому проверяем раздел, а не конкретное название
    assert "Vazifalar:" in msgs[3004] and "Reyting" in msgs[3004]  # P1 IT
    assert digest.send_weekly(int(monday.timestamp()) + 3600) == 0  # shu hafta takror yo‘q / без повтора
    # xabarnoma o‘chirilgan — yuborilmaydi / уведомления выключены — не шлём
    with db.tx() as c:
        c.x("UPDATE users SET notify_tg=0 WHERE tg_id=3005")
    sent.clear()
    digest.send_weekly(int((monday + datetime.timedelta(days=7)).timestamp()))
    assert 3005 not in {p["chat_id"] for m, p in sent if m == "sendMessage"}
    with db.tx() as c:
        c.x("UPDATE users SET notify_tg=1 WHERE tg_id=3005")
