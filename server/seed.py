"""Boshlang‘ich ma’lumotlar: Andijon viloyati va uning tuman/shaharlari.
Начальные данные: Андижанская область и её районы/города. Qayta ishga tushirish xavfsiz / повторный запуск безопасен.
"""

import secrets

import db

REGION = ("andijon", "Andijon viloyati", "Андижанская область")

# (id, uz, ru, tur / тип)
DISTRICTS = [
    ("and-shahar", "Andijon shahri", "г. Андижан", "shahar"),
    ("xonobod", "Xonobod shahri", "г. Ханабад", "shahar"),
    ("and-tuman", "Andijon tumani", "Андижанский район", "tuman"),
    ("asaka", "Asaka tumani", "Асакинский район", "tuman"),
    ("baliqchi", "Baliqchi tumani", "Балыкчинский район", "tuman"),
    ("boston", "Bo‘ston tumani", "Бустонский район", "tuman"),
    ("buloqboshi", "Buloqboshi tumani", "Булакбашинский район", "tuman"),
    ("izboskan", "Izboskan tumani", "Избасканский район", "tuman"),
    ("jalaquduq", "Jalaquduq tumani", "Джалакудукский район", "tuman"),
    ("xojaobod", "Xo‘jaobod tumani", "Ходжаабадский район", "tuman"),
    ("qorgontepa", "Qo‘rg‘ontepa tumani", "Кургантепинский район", "tuman"),
    ("marhamat", "Marhamat tumani", "Мархаматский район", "tuman"),
    ("oltinkol", "Oltinko‘l tumani", "Алтынкульский район", "tuman"),
    ("paxtaobod", "Paxtaobod tumani", "Пахтаабадский район", "tuman"),
    ("shahrixon", "Shahrixon tumani", "Шахриханский район", "tuman"),
    ("ulugnor", "Ulug‘nor tumani", "Улугнорский район", "tuman"),
]

# Davlat maktablari soni (2025/2026 o‘quv yili boshi, Andijon viloyati statistika boshqarmasi, 25.03.2026).
# Число государственных школ (начало 2025/2026 уч. года, Андижанский облстат, 25.03.2026).
# Nomma-nom ro‘yxat yo‘q — 1..N raqamlar qo‘shiladi; yo‘q maktabni admin qo‘shadi, ortiqchasini yashiradi.
# Поимённого списка нет — добавляются номера 1..N; недостающие добавляет админ, лишние скрывает.
SCHOOL_COUNTS = {
    "and-shahar": 62, "xonobod": 8, "oltinkol": 55, "and-tuman": 59, "baliqchi": 62, "boston": 29,
    "buloqboshi": 35, "jalaquduq": 57, "izboskan": 55, "ulugnor": 27, "qorgontepa": 63, "asaka": 69,
    "marhamat": 47, "shahrixon": 77, "paxtaobod": 52, "xojaobod": 40,
}
SCHOOLS_KEY = "seed:schools:2025-2026"  # bir marta / один раз (admin o‘chirgani qaytmaydi / удалённое админом не вернётся)


def seed_schools(c):
    if c.one("SELECT k FROM sent_once WHERE k=?", (SCHOOLS_KEY,)):
        return 0
    added = 0
    for did, n in SCHOOL_COUNTS.items():
        have = {r["number"] for r in c.q("SELECT number FROM schools WHERE district_id=? AND number IS NOT NULL", (did,))}
        for num in range(1, n + 1):
            if num not in have:
                c.x("INSERT INTO schools (id, district_id, number, name, created_at) VALUES (?, ?, ?, '', ?)",
                    (secrets.token_hex(8), did, num, db.now()))
                added += 1
    c.x("INSERT INTO sent_once (k, at) VALUES (?, ?)", (SCHOOLS_KEY, db.now()))
    return added


def run():
    with db.tx() as c:
        if not c.one("SELECT id FROM regions WHERE id=?", (REGION[0],)):
            c.x("INSERT INTO regions (id, name_uz, name_ru) VALUES (?, ?, ?)", REGION)
        for i, (did, uz, ru, kind) in enumerate(DISTRICTS):
            if not c.one("SELECT id FROM districts WHERE id=?", (did,)):
                c.x("INSERT INTO districts (id, region_id, name_uz, name_ru, kind, sort) VALUES (?, ?, ?, ?, ?, ?)",
                    (did, REGION[0], uz, ru, kind, i))
        seed_schools(c)
