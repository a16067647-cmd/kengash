"""Tuzilma: rollar, darajalar, yo‘nalishlar va «kim kimdan yuqori» qoidasi.
Структура: роли, уровни, направления и правило «кто над кем».

Rollar / роли (users.kind):
  coordinator — maktab, tuman yoki viloyat koordinatori (8 yo‘nalishdan biri)
  maslahatchi — maktab maslahatchisi (o‘qituvchi), maktabda bitta: direction='maslahatchi'
  student     — oddiy o‘quvchi (bepul), level='school', direction=NULL
Holat / статус (users.status): new → pending → active | rejected; blocked.
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
MASLAHATCHI = "maslahatchi"
KINDS = ("coordinator", "maslahatchi", "student")
SEAT_DIRECTIONS = DIRECTION_KEYS + [MASLAHATCHI]


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


def kind_of(direction, level):
    if direction == MASLAHATCHI:
        return "maslahatchi"
    if level == "school" and not direction:
        return "student"
    return "coordinator"


def is_above(c, actor, level, place_id, direction):
    """`actor` shu o‘rindan (yoki o‘quvchidan, direction=None) yuqorimi? / выше ли `actor` этого места/ученика?

    1. Admin — hammadan.
    2. Viloyat koordinatori: viloyatdagi tuman va maktab koordinatorlari, o‘z yo‘nalishi (Lider — hammasi,
       maslahatchilar ham). O‘quvchilar — YO‘Q.
    3. Tuman koordinatori: tumandagi maktab koordinatorlari, o‘z yo‘nalishi (Lider — hammasi + maslahatchilar).
       O‘quvchilar — YO‘Q.
    4. Maslahatchi: o‘z maktabining koordinatorlari va o‘quvchilari.
    5. Maktab koordinatori: o‘z maktabining o‘quvchilari.
    """
    if not actor:
        return False
    if actor.get("role") == "admin":
        return True
    if actor.get("status") != "active" or not actor.get("level"):
        return False
    chain = place_chain(c, level, place_id)
    if not chain:
        return False
    target = kind_of(direction, level)
    a_dir, a_lvl, a_pid = actor["direction"], actor["level"], actor["place_id"]

    if a_dir == MASLAHATCHI:
        return level == "school" and chain.get("school") == a_pid and target in ("coordinator", "student")
    if a_lvl == "school":
        return target == "student" and chain.get("school") == a_pid
    if target == "student":
        return False  # tuman va viloyat o‘quvchilarni ko‘rmaydi / район и область учеников не видят
    if target == "maslahatchi":
        ok_dir = a_dir == LIDER
    else:
        ok_dir = a_dir == direction or a_dir == LIDER
    if not ok_dir:
        return False
    if a_lvl == "region":
        return level in ("district", "school") and chain.get("region") == a_pid
    if a_lvl == "district":
        return level == "school" and chain.get("district") == a_pid
    return False


def approvers(c, u):
    """Kim tasdiqlaydi (birinchi topilgan bo‘g‘in) / кто подтверждает (первое найденное звено).
    Maktab koordinatori → maslahatchi; maslahatchi → tuman Lideri; tuman koordinatori → viloyat Lideri;
    viloyat koordinatori → admin. Hech kim bo‘lmasa → admin."""
    level, pid, d = u.get("level"), u.get("place_id"), u.get("direction")
    chain = place_chain(c, level, pid) if level else None
    want = []
    if chain and level == "school" and d in DIRECTION_KEYS:
        want = [("school", chain["school"], MASLAHATCHI), ("district", chain["district"], LIDER)]
    elif chain and level == "school" and d == MASLAHATCHI:
        want = [("district", chain["district"], LIDER), ("region", chain["region"], LIDER)]
    elif chain and level == "district":
        want = [("region", chain["region"], LIDER)]
    for lv, p, dd in want:
        rows = c.q("SELECT * FROM users WHERE level=? AND place_id=? AND direction=? AND status='active'", (lv, p, dd))
        if rows:
            return rows
    return c.q("SELECT * FROM users WHERE role='admin' AND status='active' ORDER BY created_at")


def can_approve(c, actor, u):
    if actor.get("role") == "admin":
        return True
    return any(a["id"] == actor["id"] for a in approvers(c, u))


def pays(u):
    """Oylik to‘lov kimdan: koordinator va maslahatchi; o‘quvchi va admin — bepul.
    Кто платит: координаторы и маслахатчи; ученики и админ — бесплатно."""
    return u.get("role") != "admin" and u.get("kind") in ("coordinator", "maslahatchi")
