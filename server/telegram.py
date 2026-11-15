"""Telegram bot: kirish, ro‘yxatdan o‘tish va tasdiqlash.
Telegram-бот: вход, регистрация и подтверждение.

Ro‘yxatdan o‘tish (faqat ism yoziladi, qolgani — tugmalar) / регистрация (пишется только имя, остальное — кнопки):
  raqam → ism-familiya → rol (o‘quvchi / koordinator / maslahatchi) → [daraja] → tuman → maktab →
  sinf (o‘quvchi) yoki yo‘nalish (koordinator) → tasdiqlash.
  O‘quvchi darhol kiradi. Koordinator va maslahatchi tasdiq kutadi: tasdiqlovchiga bot ✅/❌ tugmalari bilan yozadi.
  O‘rin band bo‘lsa — kim bilan bog‘lanishni ko‘rsatadi.

Ilova bilan bog‘lanish / связь с приложением: ilova /api/auth/telegram/start → t.me/<bot>?start=login_<id>;
ro‘yxat tugagach (yoki odam avval ro‘yxatdan o‘tgan bo‘lsa) so‘rov "done" bo‘ladi → ilova tokenni oladi.
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
LOGIN_TTL = 1800

log = logging.getLogger("kengash.telegram")

TXT = {
    "ask_phone": ("Kengash’ga xush kelibsiz! Avval pastdagi «📱 Raqamni ulashish» tugmasini bosing.\n\n"
                  "Добро пожаловать в Kengash! Сначала нажмите кнопку «📱 Поделиться номером» ниже."),
    "share": "📱 Raqamni ulashish / Поделиться номером",
    "done": "✅ Tayyor! Ilovaga qayting — siz kirdingiz.\n\n✅ Готово! Вернитесь в приложение — вы вошли.",
    "back": "↩️ Ilovani ochish / Открыть приложение",
    "expired": ("⌛ Kirish havolasi eskirgan. Ilovada «Telegram orqali kirish» ni qaytadan bosing.\n\n"
                "⌛ Ссылка для входа устарела. Нажмите «Войти через Telegram» в приложении ещё раз."),
    "not_yours": ("Iltimos, tugma orqali faqat O‘ZINGIZNING raqamingizni ulashing.\n\n"
                  "Пожалуйста, поделитесь только СВОИМ номером через кнопку."),
    "hello": ("Assalomu alaykum! Bu — Kengash boti. Ilovani ochish uchun pastdagi tugmani bosing.\n\n"
              "Здравствуйте! Это бот Kengash. Нажмите кнопку ниже, чтобы открыть приложение."),
    "ask_name": ("Ism va familiyangizni to‘liq yozing.\nMasalan: <b>Aliyev Vali</b>\n\n"
                 "Напишите имя и фамилию полностью.\nНапример: <b>Алиев Вали</b>"),
    "bad_name": ("Iltimos, ism va familiyani to‘liq, faqat harflar bilan yozing. Masalan: Aliyev Vali\n\n"
                 "Пожалуйста, напишите имя и фамилию полностью, только буквами."),
    "ask_role": "Siz kimsiz? / Кто вы?",
    "ask_level": "Qaysi darajadagi koordinatorsiz? / Координатор какого уровня?",
    "ask_district": "Tuman yoki shaharni tanlang / Выберите район или город:",
    "ask_school": ("Maktabingizni tanlang (raqami). Ro‘yxatda bo‘lmasa — «Maktabim yo‘q» tugmasi orqali adminga yozing.\n\n"
                   "Выберите школу (номер). Если её нет в списке — напишите админу кнопкой «Моей школы нет»."),
    "no_schools": ("Bu tumanda maktablar hali qo‘shilmagan. Adminga yozing yoki boshqa tumanni tanlang.\n\n"
                   "В этом районе школы ещё не добавлены. Напишите админу или выберите другой район."),
    "ask_grade": "Nechanchi sinfda o‘qiysiz? / В каком классе вы учитесь?",
    "ask_letter": "Sinf harfi / Буква класса:",
    "ask_direction": "Yo‘nalishingiz / Ваше направление:",
    "taken": ("⚠️ Bu o‘rin band: <b>{holder}</b>.\nAgar bu siz bo‘lsangiz yoki xato bo‘lsa, yozing: {contact}\n\n"
              "⚠️ Это место занято: <b>{holder}</b>.\nЕсли это вы или ошибка, напишите: {contact}"),
    "confirm": ("Tekshiring / Проверьте:\n\n{summary}\n\n"
                "«Tasdiqlash» tugmasini bosib, <a href=\"{terms}\">foydalanish shartlari</a> va "
                "<a href=\"{privacy}\">maxfiylik siyosati</a>ga rozilik bildirasiz.\n"
                "Нажимая «Подтвердить», вы соглашаетесь с условиями и политикой конфиденциальности."),
    "student_ok": "🎉 Tayyor! Ilovani oching.\n\n🎉 Готово! Откройте приложение.",
    "pending": ("📨 Arizangiz yuborildi: {who}.\nTasdiqlangach shu yerda xabar beramiz.\n\n"
                "📨 Заявка отправлена: {who}.\nКогда её подтвердят, мы сообщим здесь."),
    "already_pending": ("⏳ Arizangiz ko‘rib chiqilmoqda: {who}.\n\n⏳ Ваша заявка рассматривается: {who}."),
    "approved": "✅ Arizangiz tasdiqlandi! Kengash ilovasini oching.\n\n✅ Заявка подтверждена! Откройте Kengash.",
    "rejected": ("❌ Arizangiz rad etildi. Ma’lumotlarni tekshirib, qaytadan /start bosing.\n\n"
                 "❌ Заявка отклонена. Проверьте данные и нажмите /start ещё раз."),
    "new_request": "🆕 Yangi ariza / Новая заявка:\n\n{summary}",
    "use_buttons": "Iltimos, tugmalardan birini bosing. / Пожалуйста, нажмите одну из кнопок.",
    "error": "Xatolik. /start bosing. / Ошибка. Нажмите /start.",
}
ROLE_LABELS = {"student": "🎓 O‘quvchi / Ученик", "coordinator": "🧭 Koordinator", "maslahatchi": "👩‍🏫 Maslahatchi"}
LEVEL_LABELS = {"school": "🏫 Maktab / Школа", "district": "🗺 Tuman / Район", "region": "🏛 Viloyat / Область"}
LETTERS = ["A", "B", "V", "G", "D", "E"]


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
    p = {"chat_id": chat_id, "text": text, "disable_web_page_preview": True, "parse_mode": "HTML"}
    if markup:
        p["reply_markup"] = markup
    return api("sendMessage", p)


def edit(chat_id, message_id, text, markup=None):
    p = {"chat_id": chat_id, "message_id": message_id, "text": text, "parse_mode": "HTML", "disable_web_page_preview": True}
    if markup:
        p["reply_markup"] = markup
    return api("editMessageText", p)


def back_button():
    return {"inline_keyboard": [[{"text": TXT["back"], "url": APP_URL}]]}


def setup_webhook():
    if not (BOT_TOKEN and PUBLIC_URL and WEBHOOK_SECRET):
        return
    threading.Thread(target=lambda: api("setWebhook", {
        "url": f"{PUBLIC_URL}/api/telegram/webhook", "secret_token": WEBHOOK_SECRET,
        "allowed_updates": ["message", "callback_query"], "drop_pending_updates": True,
    }), daemon=True).start()


def _esc(s):
    import html
    return html.escape(str(s or ""))


def tg_link(u):
    if u and u.get("tg_username"):
        return f"@{u['tg_username']}"
    return _esc(u["name"]) if u else "admin"


# ------------------------------------------------------------------ sessiya / сессия
def _session(c, tg_id):
    r = c.one("SELECT * FROM reg_sessions WHERE tg_id=?", (tg_id,))
    return (r["step"], json.loads(r["data"] or "{}")) if r else (None, {})


def _save(c, tg_id, step, data):
    c.x("DELETE FROM reg_sessions WHERE tg_id=?", (tg_id,))
    c.x("INSERT INTO reg_sessions (tg_id, step, data, updated_at) VALUES (?, ?, ?, ?)", (tg_id, step, json.dumps(data), db.now()))


def _clear(c, tg_id):
    c.x("DELETE FROM reg_sessions WHERE tg_id=?", (tg_id,))


def _ensure_user(c, frm, phone):
    """Telegram foydalanuvchisi uchun hisob (bo‘lmasa yaratadi) / аккаунт для пользователя Telegram."""
    import app as core
    u = c.one("SELECT * FROM users WHERE tg_id=?", (frm["id"],))
    if u:
        c.x("UPDATE users SET tg_username=? WHERE id=?", (frm.get("username") or "", u["id"]))
        if phone:
            c.x("UPDATE users SET phone=? WHERE id=?", (phone, u["id"]))
        return c.one("SELECT * FROM users WHERE id=?", (u["id"],))
    admin = frm["id"] in core.ADMIN_TG_IDS
    uid = core.new_id()
    name = core.clean(f"{frm.get('first_name') or ''} {frm.get('last_name') or ''}", 60)
    c.x("INSERT INTO users (id, tg_id, tg_username, phone, name, role, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (uid, frm["id"], frm.get("username") or "", phone, name, "admin" if admin else "user",
         "active" if admin else "new", db.now()))
    return c.one("SELECT * FROM users WHERE id=?", (uid,))


def _mark_done(c, rid, frm, phone):
    c.x("UPDATE login_requests SET status='done', tg_id=?, tg_username=?, first_name=?, last_name=?, phone=? "
        "WHERE id=?", (frm["id"], frm.get("username") or "", (frm.get("first_name") or "")[:60],
                       (frm.get("last_name") or "")[:60], phone, rid))


def _finish_logins(c, frm, phone, data):
    """Ilovadagi kutib turgan kirish so‘rovlarini yakunlash / завершить ожидающие входы в приложении."""
    rid = data.get("login")
    if rid:
        req = c.one("SELECT * FROM login_requests WHERE id=?", (rid,))
        if req and db.now() - req["created_at"] <= LOGIN_TTL and req["status"] != "done":
            _mark_done(c, rid, frm, phone)
            return True
    return False


# ------------------------------------------------------------------ klaviaturalar / клавиатуры
def _kb(rows):
    return {"inline_keyboard": rows}


def _grid(items, per_row):
    return [items[i:i + per_row] for i in range(0, len(items), per_row)]


def _btn(text, data):
    return {"text": text, "callback_data": data}


def _role_kb():
    return _kb([[_btn(ROLE_LABELS[k], f"r:role:{k}")] for k in ("student", "coordinator", "maslahatchi")])


def _level_kb():
    return _kb([[_btn(LEVEL_LABELS[k], f"r:lvl:{k}")] for k in ("school", "district", "region")])


def _district_kb(c):
    rows = c.q("SELECT id, name_uz FROM districts WHERE hidden=0 ORDER BY sort, name_uz")
    return _kb(_grid([_btn(r["name_uz"], f"r:d:{r['id']}") for r in rows], 2))


ADMIN_CONTACT = os.environ.get("ADMIN_CONTACT", "behruz_sk")  # zaxira / запасной


def admin_url(c):
    """Admin Telegram havolasi / ссылка на Telegram админа."""
    a = c.one("SELECT tg_username FROM users WHERE role='admin' AND status='active' AND tg_username<>'' "
              "ORDER BY created_at LIMIT 1")
    return f"https://t.me/{(a and a['tg_username']) or ADMIN_CONTACT}"


def _no_school_btn(c):
    return {"text": "🆘 Maktabim yo‘q — adminga yozish / Моей школы нет — написать админу", "url": admin_url(c)}


def _school_kb(c, district_id):
    import app as core
    rows = c.q("SELECT * FROM schools WHERE district_id=? AND hidden=0 ORDER BY number, name LIMIT 200", (district_id,))
    if not rows:
        return None
    btns = [_btn(str(r["number"]) if r["number"] else core.school_names(r)[0][:20], f"r:s:{r['id']}") for r in rows]
    numbered = [b for b, r in zip(btns, rows) if r["number"]]
    named = [b for b, r in zip(btns, rows) if not r["number"]]
    return _kb(_grid(numbered, 6) + [[b] for b in named] + [[_no_school_btn(c)], [_btn("⬅️ Tuman / Район", "r:back:district")]])


def _grade_kb():
    return _kb(_grid([_btn(str(g), f"r:g:{g}") for g in range(1, 12)], 6))


def _letter_kb():
    return _kb(_grid([_btn(x, f"r:l:{x}") for x in LETTERS], 6) + [[_btn("Harfsiz / Без буквы", "r:l:-")]])


def _direction_kb():
    import model
    return _kb(_grid([_btn(uz, f"r:dir:{k}") for k, uz, _ in model.DIRECTIONS], 2))


def _confirm_kb():
    return _kb([[_btn("✅ Tasdiqlash / Подтвердить", "r:ok")], [_btn("✏️ Qaytadan / Заново", "r:redo")]])


def _summary(c, d):
    import app as core
    import model
    lines = [f"👤 <b>{_esc(d.get('name'))}</b>", f"• {_esc(ROLE_LABELS.get(d.get('kind'), ''))}"]
    if d.get("kind") == "coordinator":
        lines.append(f"• {_esc(LEVEL_LABELS.get(d.get('level'), ''))}")
        dn = dict((k, uz) for k, uz, _ in model.DIRECTIONS).get(d.get("direction"), "")
        if dn:
            lines.append(f"• {_esc(dn)}")
    if d.get("district_id"):
        p = core.place_info(c, "district", d["district_id"])
        lines.append(f"• {_esc(p['name_uz'] if p else '')}")
    if d.get("school_id"):
        p = core.place_info(c, "school", d["school_id"])
        lines.append(f"• {_esc(p['name_uz'] if p else '')}")
    if d.get("class_name"):
        lines.append(f"• {_esc(d['class_name'])}-sinf / класс")
    return "\n".join(lines)


def _confirm_text(c, d):
    return TXT["confirm"].format(summary=_summary(c, d), terms=f"{APP_URL}terms.html", privacy=f"{APP_URL}privacy.html")


# ------------------------------------------------------------------ yangilanishlar / обновления
def handle_update(update):
    if update.get("callback_query"):
        return handle_callback(update["callback_query"])
    msg = update.get("message") or {}
    frm = msg.get("from") or {}
    chat = (msg.get("chat") or {}).get("id")
    if not frm.get("id") or not chat or (msg.get("chat") or {}).get("type") != "private" or frm.get("is_bot"):
        return
    text = (msg.get("text") or "").strip()
    contact = msg.get("contact")
    out = []  # (chat, text, markup) — tranzaksiyadan keyin yuboriladi / отправляется после транзакции

    with db.tx() as c:
        step, data = _session(c, frm["id"])
        if text.startswith("/start"):
            payload = text[6:].strip()
            data = {}
            if payload.startswith("login_"):
                rid = payload[6:]
                req = c.one("SELECT * FROM login_requests WHERE id=?", (rid,))
                if not req or db.now() - req["created_at"] > LOGIN_TTL or req["status"] == "done":
                    out.append((chat, TXT["expired"], None))
                    payload = ""
                else:
                    data["login"] = rid
                    c.x("UPDATE login_requests SET status='bot', tg_id=? WHERE id=?", (frm["id"], rid))
            u = c.one("SELECT * FROM users WHERE tg_id=?", (frm["id"],))
            if not u or not u["phone"]:
                _save(c, frm["id"], "contact", data)
                out.append((chat, TXT["ask_phone"], {"keyboard": [[{"text": TXT["share"], "request_contact": True}]],
                                                     "resize_keyboard": True, "one_time_keyboard": True}))
            else:
                out += _after_phone(c, frm, u, data, chat)
        elif contact:
            if contact.get("user_id") != frm["id"]:
                out.append((chat, TXT["not_yours"], None))
            else:
                phone = "".join(ch for ch in str(contact.get("phone_number") or "") if ch.isdigit() or ch == "+")
                if phone and not phone.startswith("+"):
                    phone = "+" + phone
                u = _ensure_user(c, frm, phone)
                out.append((chat, "👍", {"remove_keyboard": True}))
                out += _after_phone(c, frm, u, data, chat)
        elif step == "name" and text:
            import register as reg
            try:
                data["name"] = reg.clean_name(text)
            except reg.RegError:
                out.append((chat, TXT["bad_name"], None))
            else:
                _save(c, frm["id"], "role", data)
                out.append((chat, TXT["ask_role"], _role_kb()))
        elif step in ("role", "level", "district", "school", "grade", "letter", "direction", "confirm"):
            out.append((chat, TXT["use_buttons"], None))
        else:
            u = c.one("SELECT * FROM users WHERE tg_id=?", (frm["id"],))
            if not u or u["status"] in ("new", "rejected"):
                out.append((chat, "👋 /start", None))
            else:
                out.append((chat, TXT["hello"], back_button()))
    for chat_id, t, m in out:
        send(chat_id, t, m)


def _after_phone(c, frm, u, data, chat):
    """Raqam bor: ro‘yxatdan o‘tganmi yoki yo‘qmi / номер есть: зарегистрирован или нет."""
    import model
    if u["status"] in ("active", "pending") and (u["role"] == "admin" or u["level"]):
        _finish_logins(c, frm, u["phone"], data)
        _clear(c, frm["id"])
        if u["status"] == "pending":
            who = ", ".join(tg_link(a) for a in model.approvers(c, u)[:3])
            return [(chat, TXT["already_pending"].format(who=who), back_button())]
        return [(chat, TXT["done"] if data.get("login") else TXT["hello"], back_button())]
    if u["status"] == "blocked":
        _clear(c, frm["id"])
        return [(chat, "⛔", None)]
    _save(c, frm["id"], "name", data)
    return [(chat, TXT["ask_name"], None)]


def handle_callback(q):
    frm = q.get("from") or {}
    data_s = q.get("data") or ""
    msg = q.get("message") or {}
    chat = (msg.get("chat") or {}).get("id")
    mid = msg.get("message_id")
    api("answerCallbackQuery", {"callback_query_id": q.get("id")})
    if not frm.get("id") or not chat:
        return
    if data_s.startswith(("ap:", "rj:")):
        return _decision(frm, data_s, chat, mid)
    out_edit, out_send = None, []
    with db.tx() as c:
        step, d = _session(c, frm["id"])
        if step is None:
            out_edit = (TXT["error"], None)
        else:
            out_edit, out_send = _reg_step(c, frm, step, d, data_s, chat)
    if out_edit:
        edit(chat, mid, out_edit[0], out_edit[1])
    for chat_id, t, m in out_send:
        send(chat_id, t, m)


def _reg_step(c, frm, step, d, data_s, chat):
    """Bitta tugma bosilishi → (tahrirlangan xabar, yangi xabarlar) / одно нажатие → (правка, новые сообщения)."""
    import app as core
    import model
    import register as reg
    parts = data_s.split(":")
    if parts[0] != "r":
        return (TXT["error"], None), []
    act, val = parts[1], (parts[2] if len(parts) > 2 else "")
    tg = frm["id"]

    def go(next_step, text, kb):
        _save(c, tg, next_step, d)
        return (text, kb), []

    if act == "redo":
        d = {k: v for k, v in d.items() if k == "login"}
        return go("name", TXT["ask_name"], None)
    if act == "back" and val == "district":
        return go("district", TXT["ask_district"], _district_kb(c))
    if act == "role" and val in model.KINDS:
        d["kind"] = val
        if val == "coordinator":
            return go("level", TXT["ask_level"], _level_kb())
        d["level"] = "school"
        return go("district", TXT["ask_district"], _district_kb(c))
    if act == "lvl" and val in model.LEVELS:
        d["level"] = val
        if val == "region":
            d["region_id"] = "andijon"
            return go("direction", TXT["ask_direction"], _direction_kb())
        return go("district", TXT["ask_district"], _district_kb(c))
    if act == "d":
        if not c.one("SELECT id FROM districts WHERE id=?", (val,)):
            return (TXT["error"], None), []
        d["district_id"] = val
        if d.get("kind") == "coordinator" and d.get("level") == "district":
            return go("direction", TXT["ask_direction"], _direction_kb())
        kb = _school_kb(c, val)
        if not kb:
            kb = _district_kb(c)
            kb["inline_keyboard"].insert(0, [_no_school_btn(c)])
            return go("district", TXT["no_schools"] + "\n\n" + TXT["ask_district"], kb)
        return go("school", TXT["ask_school"], kb)
    if act == "s":
        s = c.one("SELECT * FROM schools WHERE id=? AND district_id=?", (val, d.get("district_id")))
        if not s:
            return (TXT["error"], None), []
        d["school_id"] = val
        if d.get("kind") == "student":
            return go("grade", TXT["ask_grade"], _grade_kb())
        if d.get("kind") == "maslahatchi":
            holder = reg.seat_holder(c, "school", val, model.MASLAHATCHI, exclude=_uid(c, tg))
            if holder:
                contact = ", ".join(tg_link(a) for a in model.approvers(c, holder)[:2])
                return go("school", TXT["taken"].format(holder=_esc(holder["name"]), contact=contact) + "\n\n" +
                          TXT["ask_school"], _school_kb(c, d["district_id"]))
            return go("confirm", _confirm_text(c, d), _confirm_kb())
        return go("direction", TXT["ask_direction"], _direction_kb())
    if act == "g" and val.isdigit() and 1 <= int(val) <= 11:
        d["grade"] = val
        return go("letter", TXT["ask_letter"], _letter_kb())
    if act == "l":
        d["class_name"] = d.get("grade", "") + ("" if val == "-" else f"-{val}")
        return go("confirm", _confirm_text(c, d), _confirm_kb())
    if act == "dir" and val in model.DIRECTION_KEYS:
        d["direction"] = val
        try:
            lvl, pid, dd = reg.seat_for(d)
        except reg.RegError:
            return (TXT["error"], None), []
        holder = reg.seat_holder(c, lvl, pid, dd, exclude=_uid(c, tg))
        if holder:
            contact = ", ".join(tg_link(a) for a in model.approvers(c, holder)[:2])
            d.pop("direction", None)
            return go("direction", TXT["taken"].format(holder=_esc(holder["name"]), contact=contact) + "\n\n" +
                      TXT["ask_direction"], _direction_kb())
        return go("confirm", _confirm_text(c, d), _confirm_kb())
    if act == "ok" and step == "confirm":
        uid = _uid(c, tg)
        try:
            u = reg.register(c, uid, d, core.LEGAL_VERSION)
        except reg.RegError as e:
            if e.code == "seat_taken":
                h = e.extra["holder"]
                return go("name", TXT["taken"].format(holder=_esc(h["name"]), contact="admin") + "\n\n" + TXT["ask_name"], None)
            return go("name", TXT["error"], None)
        core.seat_changed(c, uid)
        _finish_logins(c, frm, u["phone"], d)
        _clear(c, tg)
        if u["status"] == "active":
            return (TXT["student_ok"], back_button()), []
        apps = model.approvers(c, u)
        who = ", ".join(tg_link(a) for a in apps[:3])
        summary = _summary(c, d) + (f"\n📞 {_esc(u['phone'])}" if u["phone"] else "") + \
            (f"\n💬 @{_esc(u['tg_username'])}" if u["tg_username"] else "")
        notes = [(a["tg_id"], TXT["new_request"].format(summary=summary),
                  _kb([[_btn("✅ Tasdiqlash", f"ap:{uid}"), _btn("❌ Rad etish", f"rj:{uid}")]]))
                 for a in apps if a.get("tg_id")]
        return (TXT["pending"].format(who=who), back_button()), notes
    return (TXT["use_buttons"], None), []


def _uid(c, tg_id):
    u = c.one("SELECT id FROM users WHERE tg_id=?", (tg_id,))
    return u["id"] if u else None


def _decision(frm, data_s, chat, mid):
    """Tasdiqlovchi tugmani bosdi / подтверждающий нажал кнопку."""
    import app as core
    import register as reg
    approve = data_s.startswith("ap:")
    uid = data_s[3:]
    with db.tx() as c:
        actor = c.one("SELECT * FROM users WHERE tg_id=?", (frm["id"],))
        if not actor:
            return
        try:
            u = reg.decide(c, actor, uid, approve)
        except reg.RegError as e:
            edit(chat, mid, {"not_pending": "ℹ️ Bu ariza allaqachon ko‘rib chiqilgan. / Заявка уже рассмотрена.",
                             "forbidden": "⛔ Ruxsat yo‘q. / Нет прав."}.get(e.code, TXT["error"]))
            return
        core.seat_changed(c, uid)
        name, tg_id = u["name"], u["tg_id"]
    edit(chat, mid, f"{'✅' if approve else '❌'} {_esc(name)} — {'tasdiqlandi / подтверждено' if approve else 'rad etildi / отклонено'}")
    notify_decision(tg_id, approve)


def notify_decision(tg_id, approved):
    if tg_id:
        send(tg_id, TXT["approved"] if approved else TXT["rejected"], back_button() if approved else None)
