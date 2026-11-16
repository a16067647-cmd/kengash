"""Muqovani avtomatik yaxshilash / автоматическое улучшение обложки.

1. Fon (oq stol, oq fon) va kitob qirrasi (umurtqa, soya) kesiladi — faqat old yuz qoladi.
   Обрезается фон и края книги (корешок, тень) — остаётся только лицевая сторона.
2. Kichik rasm sun’iy intellekt bilan 4 marta kattalashtiriladi (FSRCNN, ~40 KB, ~0.05 s).
   Маленькая картинка увеличивается нейросетью в 4 раза (FSRCNN, ~40 КБ, ~0.05 с).
3. 1000×1500 gacha, yengil keskinlik, JPEG 90.
   До 1000×1500, лёгкая резкость, JPEG 90.
OpenCV bo‘lmasa — oddiy kattalashtirish (Lanczos) / без OpenCV — обычное увеличение (Lanczos).
"""
import io
import os

MAX_W, MAX_H = 1000, 1500
SR_BELOW = 700  # bundan kichik tomonli rasmlar AI bilan kattalashtiriladi / меньше — увеличиваем нейросетью
MODEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models", "FSRCNN_x4.pb")
_sr = None


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


def _upscale_ai(im):
    global _sr
    import cv2
    import numpy as np
    if _sr is None:
        sr = cv2.dnn_superres.DnnSuperResImpl_create()
        sr.readModel(MODEL)
        sr.setModel("fsrcnn", 4)
        _sr = sr
    from PIL import Image
    src = cv2.cvtColor(np.asarray(im), cv2.COLOR_RGB2BGR)
    # JPEG «kvadratcha» shovqinini avval tozalaymiz, aks holda u ham kattalashadi
    # сначала убираем JPEG-шум, иначе он тоже увеличится
    src = cv2.fastNlMeansDenoisingColored(src, None, 4, 4, 5, 15)
    out = _sr.upsample(src)
    return Image.fromarray(cv2.cvtColor(out, cv2.COLOR_BGR2RGB))


def enhance(data: bytes) -> bytes:
    from PIL import Image, ImageFilter, ImageOps
    im = Image.open(io.BytesIO(data))
    im = ImageOps.exif_transpose(im).convert("RGB")
    im.thumbnail((2400, 3600), Image.LANCZOS)  # juda katta rasm — xotira uchun / очень большие — ради памяти
    im, photo = trim(im)
    if photo:
        im = clean_edges(im)
    ai = False
    if max(im.size) < SR_BELOW:
        try:
            im = _upscale_ai(im)
            ai = True
        except Exception:
            pass
    scale = min(MAX_W / im.width, MAX_H / im.height)
    if scale < 1:
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    elif scale > 1:
        # telefon ekranida tiniq bo‘lishi uchun (3x zichlik) / для чёткости на экране телефона (3x)
        f = min(scale, 3)
        im = im.resize((round(im.width * f), round(im.height * f)), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=1.6, percent=55 if ai else 80, threshold=2))
    out = io.BytesIO()
    im.save(out, "JPEG", quality=90, optimize=True, progressive=True)
    return out.getvalue()
