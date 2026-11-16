"""Fayllar: Supabase Storage, YOPIQ bucket / файлы: Supabase Storage, ЗАКРЫТЫЙ bucket.

Surat — server orqali (o‘lchami kichraytiriladi, EXIF/joylashuv o‘chiriladi).
Fayl, ovozli xabar, video — ilova to‘g‘ridan-to‘g‘ri imzolangan havola orqali yuklaydi (bepul server xotirasini tejash).
Ko‘rish — faqat kanal a’zolariga, 1 soatlik imzolangan havola.

Фото — через сервер (уменьшается, EXIF/геолокация удаляется).
Файлы, голосовые, видео — приложение загружает напрямую по подписанной ссылке.
Просмотр — только участникам канала, подписанная ссылка на 1 час.
"""
import json
import logging
import os
import urllib.parse
import urllib.request

URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
KEY = os.environ.get("SUPABASE_SERVICE_KEY", "").strip()
BUCKET = os.environ.get("MEDIA_BUCKET", "kengash-media")
SIGN_SECONDS = 3600
log = logging.getLogger("kengash.storage")


def enabled():
    return bool(URL and KEY)


def _req(method, path, body=None, raw=None, content_type="application/json"):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(f"{URL}/storage/v1{path}", data=data, method=method, headers={
        "apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": content_type})
    with urllib.request.urlopen(req, timeout=30) as r:
        txt = r.read().decode() or "{}"
        return json.loads(txt)


def q(path):
    return urllib.parse.quote(path, safe="/")


def ensure_bucket():
    if not enabled():
        return
    try:
        _req("GET", f"/bucket/{BUCKET}")
    except Exception:
        try:
            _req("POST", "/bucket", {"id": BUCKET, "name": BUCKET, "public": False, "file_size_limit": 52_428_800})
        except Exception as e:
            log.warning("bucket create failed: %s", e)


def put(path, data: bytes, mime):
    _req("POST", f"/object/{BUCKET}/{q(path)}", raw=data, content_type=mime)


def upload_url(path):
    """Ilova shu manzilga PUT qiladi / приложение делает PUT на этот адрес."""
    r = _req("POST", f"/object/upload/sign/{BUCKET}/{q(path)}", {})
    return f"{URL}/storage/v1{r['url']}"


def info(path):
    """Fayl hajmi yoki None / размер файла или None."""
    try:
        r = _req("GET", f"/object/info/{BUCKET}/{q(path)}")
        return int(r.get("size") or (r.get("metadata") or {}).get("size") or 0)
    except Exception:
        return None


def sign(paths, seconds=SIGN_SECONDS):
    if not paths:
        return {}
    r = _req("POST", f"/object/sign/{BUCKET}", {"expiresIn": seconds, "paths": list(paths)})
    out = {}
    for x in r if isinstance(r, list) else []:
        if x.get("signedURL"):
            out[x["path"]] = f"{URL}/storage/v1{x['signedURL']}"
    return out


def get(path):
    """Fayl baytlari / байты файла (yopiq bucket — service kalit bilan)."""
    req = urllib.request.Request(f"{URL}/storage/v1/object/authenticated/{BUCKET}/{q(path)}",
                                 headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def remove(paths):
    if paths and enabled():
        try:
            _req("DELETE", f"/object/{BUCKET}", {"prefixes": list(paths)})
        except Exception as e:
            log.warning("remove failed: %s", e)
