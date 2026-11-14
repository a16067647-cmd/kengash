"""Telegram bot: kirish (login) va raqamni tasdiqlash.
Telegram-бот: вход и подтверждение номера.

Oqim / поток:
  1. Ilova /api/auth/telegram/start → t.me/<bot>?start=login_<id>
  2. Foydalanuvchi botda Start bosadi → bot «Raqamni ulashish» tugmasini so‘raydi
     (agar odam avval raqam ulashgan bo‘lsa — darhol tayyor).
  3. Kontakt kelganda (contact.user_id == from.id) so‘rov "done" bo‘ladi → ilova tokenni oladi.
"""

import json
import logging
import os
import threading
import urllib.request

import db

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
BOT_USERNAME = os.environ.get("TELEGRAM_BOT_USERNAME", "KengashAppBot").strip().lstrip("@")
WEBHOOK_SECRET = os.environ.get("TELEGRAM_WEBHOOK_SECRET", "").strip()
PUBLIC_URL = os.environ.get("PUBLIC_URL", "").rstrip("/")
APP_URL = os.environ.get("APP_URL", "https://a16067647-cmd.github.io/kengash/")
LOGIN_TTL = 600

log = logging.getLogger("kengash.telegram")

TXT = {
    "ask": ("Kengash ilovasiga kirish uchun pastdagi «📱 Raqamni ulashish» tugmasini bosing.\n\n"
            "Для входа в Kengash нажмите кнопку «📱 Поделиться номером» ниже."),
    "share": "📱 Raqamni ulashish / Поделиться номером",
    "done": ("✅ Tayyor! Endi ilovaga qayting — siz kirdingiz.\n\n"
             "✅ Готово! Вернитесь в приложение — вы вошли."),
    "back": "↩️ Ilovaga qaytish / Вернуться",
    "expired": ("⌛ Kirish havolasi eskirgan. Ilovada «Telegram orqali kirish» ni qaytadan bosing.\n\n"
                "⌛ Ссылка для входа устарела. Нажмите «Войти через Telegram» в приложении ещё раз."),
    "not_yours": ("Iltimos, tugma orqali faqat O‘ZINGIZNING raqamingizni ulashing.\n\n"
                  "Пожалуйста, поделитесь только СВОИМ номером через кнопку."),
    "hello": ("Assalomu alaykum! Bu — Kengash ilovasining boti. Ilovani oching va «Telegram orqali kirish» ni bosing.\n\n"
              "Здравствуйте! Это бот приложения Kengash. Откройте приложение и нажмите «Войти через Telegram»."),
}


def start_link(rid):
    return f"https://t.me/{BOT_USERNAME}?start=login_{rid}"


def api(method, payload):
    """Telegram Bot API chaqiruvi / вызов Bot API. Token bo‘lmasa — hech narsa qilmaydi."""
    if not BOT_TOKEN:
        log.info("telegram %s (no token): %s", method, payload)
        return None
    req = urllib.request.Request(f"https://api.telegram.org/bot{BOT_TOKEN}/{method}",
                                 data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read().decode())
    except Exception as e:  # tarmoq xatosi kirishni to‘xtatmasin / сетевая ошибка не должна ломать вход
        log.warning("telegram %s failed: %s", method, e)
        return None


def send(chat_id, text, markup=None):
    p = {"chat_id": chat_id, "text": text, "disable_web_page_preview": True}
    if markup:
        p["reply_markup"] = markup
    return api("sendMessage", p)


def back_button():
    return {"inline_keyboard": [[{"text": TXT["back"], "url": APP_URL}]]}


def setup_webhook():
    if not (BOT_TOKEN and PUBLIC_URL and WEBHOOK_SECRET):
        return
    threading.Thread(target=lambda: api("setWebhook", {
        "url": f"{PUBLIC_URL}/api/telegram/webhook", "secret_token": WEBHOOK_SECRET,
        "allowed_updates": ["message"], "drop_pending_updates": True,
    }), daemon=True).start()


def _mark_done(c, rid, frm, phone):
    c.x("UPDATE login_requests SET status='done', tg_id=?, tg_username=?, first_name=?, last_name=?, phone=? "
        "WHERE id=?", (frm["id"], frm.get("username") or "", (frm.get("first_name") or "")[:60],
                       (frm.get("last_name") or "")[:60], phone, rid))


def handle_update(update):
    msg = update.get("message") or {}
    frm = msg.get("from") or {}
    chat = (msg.get("chat") or {}).get("id")
    if not frm.get("id") or not chat or (msg.get("chat") or {}).get("type") != "private" or frm.get("is_bot"):
        return
    text = (msg.get("text") or "").strip()
    contact = msg.get("contact")

    if text.startswith("/start"):
        payload = text[6:].strip()
        if not payload.startswith("login_"):
            send(chat, TXT["hello"], back_button())
            return
        rid = payload[6:]
        with db.tx() as c:
            req = c.one("SELECT * FROM login_requests WHERE id=?", (rid,))
            if not req or db.now() - req["created_at"] > LOGIN_TTL or req["status"] == "done":
                send(chat, TXT["expired"])
                return
            known = c.one("SELECT phone FROM users WHERE tg_id=? AND phone<>''", (frm["id"],))
            if known:
                _mark_done(c, rid, frm, known["phone"])
            else:
                c.x("UPDATE login_requests SET status='contact', tg_id=? WHERE id=?", (frm["id"], rid))
        if known:
            send(chat, TXT["done"], back_button())
        else:
            send(chat, TXT["ask"], {"keyboard": [[{"text": TXT["share"], "request_contact": True}]],
                                    "resize_keyboard": True, "one_time_keyboard": True})
        return

    if contact:
        if contact.get("user_id") != frm["id"]:
            send(chat, TXT["not_yours"])
            return
        phone = "".join(ch for ch in str(contact.get("phone_number") or "") if ch.isdigit() or ch == "+")
        if phone and not phone.startswith("+"):
            phone = "+" + phone
        with db.tx() as c:
            req = c.one("SELECT * FROM login_requests WHERE tg_id=? AND status='contact' AND created_at>? "
                        "ORDER BY created_at DESC LIMIT 1", (frm["id"], db.now() - LOGIN_TTL))
            if req:
                _mark_done(c, req["id"], frm, phone)
            else:
                c.x("UPDATE users SET phone=? WHERE tg_id=?", (phone, frm["id"]))
        send(chat, "👍", {"remove_keyboard": True})
        send(chat, TXT["done"] if req else TXT["hello"], back_button())
        return

    send(chat, TXT["hello"], back_button())
