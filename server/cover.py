"""Muqovani avtomatik yaxshilash / автоматическое улучшение обложки.

1. Rasm kichik bo‘lsa — internetdan (Open Library) shu kitobning asl, tiniq muqovasi qidiriladi.
   Nom va muallif mos, rasm esa yuklanganiga o‘xshash bo‘lsagina olinadi (boshqa kitob chiqib qolmasin).
   Если картинка маленькая — ищем оригинальную чёткую обложку в Open Library. Берём только если
   совпадают название и автор и картинка похожа на загруженную (чтобы не подставить чужую).
2. Fon (oq stol) va kitob qirrasi (umurtqa, soya) kesiladi — faqat old yuz qoladi.
   Обрезается фон и края книги (корешок, тень) — остаётся только лицевая сторона.
3. Silliq kattalashtirish (Lanczos), «AI dog‘lari»siz; 1000×1500 gacha, JPEG 90.
   Плавное увеличение (Lanczos) без «пятен» нейросети; до 1000×1500, JPEG 90.
"""
import io
import re

MAX_W, MAX_H = 1000, 1500
SMALL = 600  # bundan kichik — internetdan asl muqova qidiriladi / меньше — ищем оригинал в сети
UA = {"User-Agent": "KengashApp/1.0 (book covers)"}


def _np(im):
    import numpy as np
    return np.asarray(im).astype("int16")


def trim(im, tol=26):
    """Bir xil rangli fonni kesadi (burchaklar rangi) / обрезает однотонный фон (цвет углов)."""
    import numpy as np
    a = _np(im)
    h, w, _ = a.shape
    if h < 24 or w < 24:
        return im, False
    k = max(2, min(h, w) // 40)
    corners = np.concatenate([a[:k, :k].reshape(-1, 3), a[:k, -k:].reshape(-1, 3),
                              a[-k:, :k].reshape(-1, 3), a[-k:, -k:].reshape(-1, 3)])
    bg = np.median(corners, axis=0)
    # burchaklar bir xil emas — bu tayyor tekis muqova / углы разные — это уже плоская обложка
    if (np.abs(corners - bg).max(axis=1) > tol).mean() > 0.25:
        return im, False
    diff = np.abs(a - bg).max(axis=2) > tol
    rows = np.where(diff.mean(axis=1) > 0.05)[0]
    cols = np.where(diff.mean(axis=0) > 0.05)[0]
    if len(rows) < h * 0.2 or len(cols) < w * 0.2:
        return im, False
    t, b, l, r = int(rows[0]), int(rows[-1]) + 1, int(cols[0]), int(cols[-1]) + 1
    if (b - t) * (r - l) > 0.96 * h * w:
        return im, False
    return im.crop((l, t, r, b)), True


def clean_edges(im, tol=16, share=0.12):
    """Kitob rasmidan umurtqa va soya chiziqlarini olib tashlaydi (har tomondan ≤12%).
    Убирает полосы корешка и тени с фото книги (с каждой стороны ≤12%)."""
    import numpy as np
    a = _np(im).mean(axis=2)
    h, w = a.shape
    face = float(np.median(a[h // 4:3 * h // 4, w // 4:3 * w // 4]))

    def cut(lines, limit):
        d = [abs(float(np.median(v)) - face) for v in lines[:limit]]
        # umurtqa bukilishi — keskin qorong‘i chiziq; undan keyingi soya ham / сгиб корешка и тень за ним
        crease = [i for i, x in enumerate(d) if x > 35]
        n = crease[-1] + 1 if crease else 0
        while n < len(d) and d[n] > tol:
            n += 1
        return n

    l = cut([a[:, x] for x in range(w)], int(w * share))
    r = cut([a[:, x] for x in range(w - 1, -1, -1)], int(w * share))
    t = cut([a[y] for y in range(h)], int(h * share))
    b = cut([a[y] for y in range(h - 1, -1, -1)], int(h * share))
    # yumaloq burchak va yorug‘lik qirrasi uchun yana ~1% / ещё ~1% на скругление и блик края
    px, py = max(1, round(w * 0.01)), max(1, round(h * 0.01))
    box = (l + px, t + py, w - r - px, h - b - py)
    if box[2] - box[0] < w * 0.6 or box[3] - box[1] < h * 0.6:
        return im
    return im.crop(box)


def _norm(t):
    return re.sub(r"[^0-9a-zа-яёўқғҳ]+", " ", str(t or "").lower()).strip()


def _signature(im):
    """Xira kulrang 12×16 «izi» / размытый серый «отпечаток» 12×16."""
    import numpy as np
    from PIL import Image, ImageFilter
    g = im.convert("L").filter(ImageFilter.GaussianBlur(max(im.size) / 60)).resize((12, 16), Image.BILINEAR)
    a = np.asarray(g, dtype="float64")
    return (a - a.mean()) / (a.std() + 1e-6)


def similar(a, b):
    """Ikki muqova bitta dizaynmi: shakl (korrelyatsiya) va rang / один ли дизайн: форма и цвет."""
    import numpy as np
    from PIL import Image
    shape = float((_signature(a) * _signature(b)).mean())
    ca = np.asarray(a.convert("RGB").resize((6, 8), Image.BILINEAR), dtype="float64")
    cb = np.asarray(b.convert("RGB").resize((6, 8), Image.BILINEAR), dtype="float64")
    return shape > 0.3 and float(np.abs(ca - cb).mean()) < 40


def find_online(title, author, uploaded, timeout=8.0):
    """Open Library’dan asl muqova (yoki None) / оригинальная обложка из Open Library (или None)."""
    import httpx
    from PIL import Image
    t, a = _norm(title), _norm(author)
    if len(t) < 2:
        return None
    try:
        with httpx.Client(timeout=timeout, headers=UA, follow_redirects=True) as h:
            params = {"title": title, "fields": "cover_i,title,author_name", "limit": 8}
            if a:
                params["author"] = author
            docs = h.get("https://openlibrary.org/search.json", params=params).json().get("docs") or []
            for d in docs:
                if not d.get("cover_i") or _norm(d.get("title")) != t:
                    continue
                if a and not any(set(a.split()) & set(_norm(x).split()) for x in d.get("author_name") or []):
                    continue
                r = h.get(f"https://covers.openlibrary.org/b/id/{d['cover_i']}-L.jpg", params={"default": "false"})
                if r.status_code != 200:
                    continue
                im = Image.open(io.BytesIO(r.content)).convert("RGB")
                if max(im.size) > max(uploaded.size) and min(im.size) >= 250 and similar(uploaded, im):
                    return im
    except Exception:
        return None
    return None


def enhance(data: bytes, title: str = "", author: str = "") -> bytes:
    from PIL import Image, ImageFilter, ImageOps
    im = Image.open(io.BytesIO(data))
    im = ImageOps.exif_transpose(im).convert("RGB")
    im.thumbnail((2400, 3600), Image.LANCZOS)  # juda katta rasm — xotira uchun / очень большие — ради памяти
    orig = im
    im, photo = trim(im)
    if photo:
        im = clean_edges(im)
    if max(im.size) < SMALL and title:
        better = find_online(title, author, orig)
        if better is not None:
            im = better
    scale = min(MAX_W / im.width, MAX_H / im.height)
    if scale < 1:
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    elif scale > 1:
        # silliq kattalashtirish, dog‘larsiz / плавное увеличение без пятен
        f = min(scale, 2.5)
        im = im.resize((round(im.width * f), round(im.height * f)), Image.BICUBIC)
        im = im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=35, threshold=3))
    out = io.BytesIO()
    im.save(out, "JPEG", quality=90, optimize=True, progressive=True)
    return out.getvalue()
