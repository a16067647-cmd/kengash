"""Boshlang‘ich ma’lumotlar: Andijon viloyati va uning tuman/shaharlari.
Начальные данные: Андижанская область и её районы/города. Qayta ishga tushirish xavfsiz / повторный запуск безопасен.
"""

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


def run():
    with db.tx() as c:
        if not c.one("SELECT id FROM regions WHERE id=?", (REGION[0],)):
            c.x("INSERT INTO regions (id, name_uz, name_ru) VALUES (?, ?, ?)", REGION)
        for i, (did, uz, ru, kind) in enumerate(DISTRICTS):
            if not c.one("SELECT id FROM districts WHERE id=?", (did,)):
                c.x("INSERT INTO districts (id, region_id, name_uz, name_ru, kind, sort) VALUES (?, ?, ?, ?, ?, ?)",
                    (did, REGION[0], uz, ru, kind, i))
