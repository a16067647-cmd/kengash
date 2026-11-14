"""Tuzilma: darajalar, yo‘nalishlar va «kim kimdan yuqori» qoidasi.
Структура: уровни, направления и правило «кто над кем».
"""

LEVELS = ("school", "district", "region")

# (kalit, uz, ru) — tartib muhim (logotipdagi 8 nuqta) / порядок важен (8 точек логотипа)
DIRECTIONS = [
    ("lider", "Lider", "Лидер"),
    ("talim", "Ta’lim", "Образование"),
    ("ijtimoiy", "Ijtimoiy tashabbus", "Социальная инициатива"),
    ("it", "IT va sun’iy intellekt", "IT и искусственный интеллект"),
    ("media", "Media", "Медиа"),
    ("ekologiya", "Ekologiya", "Экология"),
    ("sport", "Sport", "Спорт"),
    ("madaniyat", "Madaniyat", "Культура"),
]
DIRECTION_KEYS = [d[0] for d in DIRECTIONS]
LIDER = "lider"


def place_chain(c, level, place_id):
    """Joyning yuqori zanjiri / цепочка мест вверх: {'school':..., 'district':..., 'region':...}.
    Joy topilmasa None / None, если места нет."""
    if level == "region":
        r = c.one("SELECT id FROM regions WHERE id=?", (place_id,))
        return {"region": r["id"]} if r else None
    if level == "district":
        d = c.one("SELECT id, region_id FROM districts WHERE id=?", (place_id,))
        return {"district": d["id"], "region": d["region_id"]} if d else None
    if level == "school":
        s = c.one("SELECT s.id, s.district_id, d.region_id FROM schools s JOIN districts d ON d.id=s.district_id "
                  "WHERE s.id=?", (place_id,))
        return {"school": s["id"], "district": s["district_id"], "region": s["region_id"]} if s else None
    return None


def is_above(c, actor, level, place_id, direction):
    """`actor` (users qatori) shu o‘rindan yuqorimi? / выше ли `actor` этого места?

    1. Admin — hammadan yuqori.
    2. Viloyat koordinatori: o‘z viloyatidagi tuman va maktab o‘rinlari, o‘z yo‘nalishi (Lider — hammasi).
    3. Tuman koordinatori: o‘z tumanidagi maktab o‘rinlari, o‘z yo‘nalishi (Lider — hammasi).
    """
    if not actor:
        return False
    if actor.get("role") == "admin":
        return True
    if actor.get("status") != "active" or not actor.get("level"):
        return False
    same_dir = actor["direction"] == direction or actor["direction"] == LIDER
    if not same_dir:
        return False
    chain = place_chain(c, level, place_id)
    if not chain:
        return False
    if actor["level"] == "region":
        return level in ("district", "school") and chain.get("region") == actor["place_id"]
    if actor["level"] == "district":
        return level == "school" and chain.get("district") == actor["place_id"]
    return False


def holders_above(c, level, place_id, direction):
    """Shu o‘rin uchun kalit bera oladiganlar (yaqinidan boshlab) / кто может выдать ключ (ближайшие первыми)."""
    chain = place_chain(c, level, place_id)
    if not chain:
        return []
    out = []
    ups = []
    if level == "school":
        ups.append(("district", chain["district"]))
    if level in ("school", "district"):
        ups.append(("region", chain["region"]))
    for lv, pid in ups:
        for d in (direction, LIDER) if direction != LIDER else (LIDER,):
            u = c.one("SELECT * FROM users WHERE level=? AND place_id=? AND direction=? AND status='active'", (lv, pid, d))
            if u:
                out.append(("user", u))
            else:
                sc = c.one("SELECT tg_username FROM seat_contacts WHERE level=? AND place_id=? AND direction=?",
                           (lv, pid, d))
                if sc and sc["tg_username"]:
                    out.append(("contact", {"level": lv, "place_id": pid, "direction": d,
                                            "tg_username": sc["tg_username"]}))
    return out
