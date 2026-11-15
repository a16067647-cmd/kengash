"""Bildirishnomalar / уведомления.

1. Telegram bot orqali (asosiy, hammaga ishlaydi, sozlash shart emas): foydalanuvchi botda Start bosgan —
   bot unga yoza oladi. Profil → «Telegram bildirishnomalari» bilan o‘chiriladi.
   Через Telegram-бота (основной способ, работает у всех, настройка не нужна).
   Chat xabarlari: bitta kanal uchun 10 daqiqada eng ko‘pi 1 ta (spam yo‘q).
2. Firebase Cloud Messaging (ixtiyoriy, kelajakda / необязательно, на будущее).

FIREBASE_SERVICE_ACCOUNT (Render → Environment) bo‘lmasa — hech narsa yubormaydi.
Без FIREBASE_SERVICE_ACCOUNT ничего не отправляет.
Yuborish fon oqimida — so‘rov kutib qolmaydi / отправка в фоне — запрос не ждёт.
"""
import json
import logging
import os
import threading
import time
import urllib.request

import db

log = logging.getLogger("kengash.push")
_SA = None
_token = {"value": "", "exp": 0}
_lock = threading.Lock()
SENT = []  # testlar uchun / для тестов


def _account():
    global _SA
    if _SA is None:
        raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "").strip()
        try:
            _SA = json.loads(raw) if raw else {}
        except Exception:
            log.warning("FIREBASE_SERVICE_ACCOUNT is not valid JSON")
            _SA = {}
    return _SA


def enabled():
    return bool(_account().get("private_key"))


def _access_token():
    import jwt  # PyJWT
    sa = _account()
    with _lock:
        if _token["value"] and _token["exp"] - 60 > time.time():
            return _token["value"]
        now = int(time.time())
        assertion = jwt.encode({"iss": sa["client_email"], "scope": "https://www.googleapis.com/auth/firebase.messaging",
                                "aud": "https://oauth2.googleapis.com/token", "iat": now, "exp": now + 3600},
                               sa["private_key"], algorithm="RS256")
        body = f"grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion={assertion}".encode()
        req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body,
                                     headers={"Content-Type": "application/x-www-form-urlencoded"})
        with urllib.request.urlopen(req, timeout=15) as r:
            d = json.loads(r.read().decode())
        _token.update(value=d["access_token"], exp=now + int(d.get("expires_in", 3600)))
        return _token["value"]


def _send_one(token, title, body, data):
    sa = _account()
    msg = {"message": {"token": token, "notification": {"title": title[:120], "body": body[:240]},
                       "data": {k: str(v) for k, v in (data or {}).items()},
                       "android": {"priority": "high", "notification": {"channel_id": "kengash", "color": "#5B2DC9"}},
                       "webpush": {"fcm_options": {"link": os.environ.get("APP_URL", "/")}}}}
    req = urllib.request.Request(f"https://fcm.googleapis.com/v1/projects/{sa['project_id']}/messages:send",
                                 data=json.dumps(msg).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {_access_token()}"})
    try:
        with urllib.request.urlopen(req, timeout=15):
            return True
    except urllib.error.HTTPError as e:
        if e.code in (400, 404):  # eskirgan token / устаревший токен
            with db.tx() as c:
                c.x("DELETE FROM push_tokens WHERE token=?", (token,))
        else:
            log.warning("push failed %s", e.code)
    except Exception as e:
        log.warning("push failed: %s", e)
    return False


TG_MESSAGE_WINDOW = 600  # chat xabarlari: kanal boshiga 10 daqiqada 1 ta / 1 на канал за 10 минут


def _telegram(user_ids, title, body, data):
    import html

    import telegram
    data = data or {}
    with db.tx() as c:
        marks = ",".join("?" * len(user_ids))
        rows = c.q(f"SELECT id, tg_id FROM users WHERE id IN ({marks}) AND tg_id IS NOT NULL AND notify_tg=1 "
                   f"AND status='active'", list(user_ids))
        targets = []
        for r in rows:
            if data.get("type") == "message":
                window = db.now() // TG_MESSAGE_WINDOW
                if not once(c, f"tgmsg:{r['id']}:{data.get('channel_id')}:{window}"):
                    continue
            targets.append(r["tg_id"])
    if not targets:
        return
    text = f"<b>{html.escape(title)}</b>\n{html.escape(body)}"
    markup = {"inline_keyboard": [[{"text": "Ochish / Открыть", "url": telegram.APP_URL}]]}

    def run():
        for chat in targets:
            telegram.api("sendMessage", {"chat_id": chat, "text": text, "parse_mode": "HTML",
                                         "disable_web_page_preview": True, "reply_markup": markup})
            time.sleep(0.05)  # Telegram chegarasi / лимит Telegram (~30 в секунду)
    if TELEGRAM_SYNC:
        run()
    else:
        threading.Thread(target=run, daemon=True).start()


TELEGRAM_SYNC = False  # testlarda True / в тестах True


def send(user_ids, title, body, data=None):
    """Foydalanuvchilarga: Telegram + (bo‘lsa) Firebase / пользователям: Telegram + (если есть) Firebase."""
    user_ids = [u for u in set(user_ids) if u]
    if not user_ids:
        return
    SENT.append({"users": sorted(user_ids), "title": title, "body": body, "data": data or {}})
    try:
        _telegram(user_ids, title, body, data)
    except Exception as e:
        log.warning("telegram notify failed: %s", e)
    if not enabled():
        return
    with db.tx() as c:
        marks = ",".join("?" * len(user_ids))
        tokens = [r["token"] for r in c.q(f"SELECT token FROM push_tokens WHERE user_id IN ({marks})", user_ids)]
    if tokens:
        threading.Thread(target=lambda: [_send_one(t, title, body, data) for t in tokens], daemon=True).start()


def once(c, key):
    """Bir marta yuborish belgisi / отметка «отправить один раз». True — birinchi marta."""
    if c.one("SELECT k FROM sent_once WHERE k=?", (key,)):
        return False
    c.x("INSERT INTO sent_once (k, at) VALUES (?, ?)", (key, db.now()))
    return True
