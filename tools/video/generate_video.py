#!/usr/bin/env python3
"""Kengash taqdimot videosi: o‘zbekcha ovoz + o‘zbekcha subtitr → presentation_uz.mp4 (1920x1080, 30 fps).

Bitta buyruq / одна команда:
    pip install edge-tts playwright pillow && python -m playwright install chromium
    python tools/video/generate_video.py

Bosqichlar / этапы:
  1) SCENES — o‘zbekcha matn va har sahna uchun ekranlar (pastda).
  2) Playwright har bir «beat»ni 1920x1080 PNG qilib chizadi (ilovaning haqiqiy ekranlari, telefon ramkasida).
  3) edge-tts (uz-UZ-SardorNeural) ovoz + gaplar vaqti bo‘yicha .srt.
     Internetsiz: --tts mms (Meta MMS, kirillga o‘girib o‘qiydi; faqat sinov uchun, CC-BY-NC).
  4) FFmpeg: sekin zoom + silliq o‘tishlar, ovoz, yozib qo‘yilgan subtitr → presentation_uz.mp4.

Ekranlar test ma’lumotlaridan (haqiqiy o‘quvchilar yo‘q) / экраны из тестовых данных (реальных учеников нет).
"""
from __future__ import annotations

import argparse
import asyncio
import glob
import html
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCREENS = HERE / "screens"
W, H, FPS = 1920, 1080, 30
XFADE = 0.5          # o‘tish (s) / переход
PAD = 0.7            # sahna oxiridagi sukut (s) / пауза в конце сцены
VOICE = "uz-UZ-SardorNeural"

# ------------------------------------------------------------------------------------------------ 1. SSENARIY
# Har sahna: sarlavha, qisqa nuqtalar, ekranlar (har biri bitta «beat»), o‘qiladigan matn.
# beats: har bir beat — ko‘rsatiladigan telefonlar ro‘yxati; ajratilgani — oxirgisi.
SCENES = [
    {
        "id": "hook", "kind": "problem", "chip": "Muammo",
        "title": "Ish ko‘p, tartib yo‘q",
        "points": ["Vazifalar Telegram guruhlarida yo‘qoladi", "Hisobotlar qog‘ozda qoladi",
                   "Kim nima qilgani noma’lum"],
        "beats": [[]],
        "text": 'Andijon viloyatida, yuzlab maktab va minglab faol o‘quvchilar bor. [[350]] Ammo vazifalar, Telegram guruhlarida yo‘qolib ketadi. Hisobotlar, qog‘ozda qoladi. [[250]] Kim nima qilgani esa, hech kimga ma’lum emas.',
    },
    {
        "id": "solution", "chip": "Yechim", "title": "Kengash — hamma narsa bir joyda",
        "points": ["Kanallar, vazifalar, tadbirlar, reyting", "Android, iPhone, sayt va Telegram"],
        "beats": [["today"], ["today", "channels"]],
        "text": 'Shuning uchun, biz Kengashni yaratdik. [[300]] Bu — Kelajak O‘quvchilar Kengashi uchun yagona ilova. Kanallar, vazifalar, tadbirlar va reyting, hammasi bir joyda. [[250]] Ilova Androidda, iPhoneda, saytda, va hatto Telegram ichida ishlaydi.',
    },
    {
        "id": "login", "chip": "Kirish", "title": "Parolsiz, bir bosishda",
        "points": ["Telegram orqali kirish", "Bot ro‘yxatdan o‘tishda yordam beradi",
                   "Maktab havolasi — maktab o‘zi tanlanadi"],
        "beats": [["login"], ["login", "register"]],
        "text": 'Kirish juda oddiy. [[250]] Parol ham, SMS ham kerak emas. Telegram orqali, bir bosishda kirasiz. [[300]] Bot ro‘yxatdan o‘tishga yordam beradi. Maktab havolasi bilan kelgan o‘quvchi esa, maktabini tanlab ham o‘tirmaydi.',
    },
    {
        "id": "today", "chip": "Bugun", "title": "Kunning eng muhimi",
        "points": ["Yangi vazifalar", "Yaqin tadbirlar", "O‘qilmagan xabarlar"],
        "beats": [["today_student"], ["today_student", "today_plan"]],
        "text": '«Bugun» sahifasi, kunning eng muhim ishlarini ko‘rsatadi: [[200]] yangi vazifalar, yaqin tadbirlar, va o‘qilmagan xabarlar. [[300]] Internet sekin bo‘lsa ham, ilova darhol ochiladi.',
    },
    {
        "id": "channels", "chip": "Kanallar", "title": "Jamoa bilan aloqa",
        "points": ["Maktab, tuman, viloyat kanallari avtomatik", "Xabar, ovoz, fayl, so‘rovnoma",
                   "«Ko‘rdi: 9 / 12» va bitta eslatma"],
        "beats": [["channels"], ["channels", "chat"], ["chat", "poll"], ["poll", "remind"]],
        "text": 'Kanallarda, maktab, tuman va viloyat jamoalari avtomatik tuziladi. [[250]] Bu yerda xabar, ovozli xabar, fayl va so‘rovnoma yuborish mumkin. [[300]] E’lon muallifi esa, uni necha kishi ko‘rganini biladi, va ko‘rmaganlarga, faqat bir marta eslatadi.',
    },
    {
        "id": "tasks", "chip": "Vazifalar", "title": "Vazifa → hisobot → baho",
        "points": ["Muddat va guruh o‘zi tanlanadi", "Hisobot: rasm yoki ovoz", "Bitta tugma: «Qabul qilish»"],
        "beats": [["task"], ["task", "report_voice"], ["report_voice", "review"]],
        "text": 'Vazifa berish uchun, uning nomini yozish kifoya. Muddat va guruh, o‘zi tanlanadi. [[300]] O‘quvchi hisobotni rasm yoki ovoz bilan yuboradi. [[200]] Masalan: “O‘n besh o‘quvchi keldi”. [[300]] Rahbar esa, bitta tugma bilan qabul qiladi, va ball beradi.',
    },
    {
        "id": "events", "chip": "Tadbirlar", "title": "QR bilan davomat",
        "points": ["Taqvimda barcha tadbirlar", "Tadbir kuni — QR kod", "Kim kelgani darhol ko‘rinadi"],
        "beats": [["calendar"], ["calendar", "event"], ["event", "qr"], ["qr", "checkin"]],
        "text": 'Barcha tadbirlar, taqvimda turadi. [[250]] Tadbir kuni, davomat QR kod orqali olinadi. O‘quvchi kodni skanerlaydi, [[150]] tashkilotchi esa, kim kelganini shu zahoti ko‘radi.',
    },
    {
        "id": "motivation", "chip": "Reyting", "title": "Har bir ish qadrlanadi",
        "points": ["Chorak reytingi", "G‘oliblarga sertifikat", "«Mening yo‘lim» — portfolio"],
        "beats": [["rating"], ["rating", "cert_banner"], ["cert_banner", "portfolio"], ["@certificate"]],
        "text": 'Har bir bajarilgan ish, ball keltiradi. [[250]] Chorak oxirida reyting g‘oliblari aniqlanadi, va ular avtomatik ravishda sertifikat oladi. [[300]] «Mening yo‘lim» sahifasi esa, o‘quvchining barcha yutuqlarini, bitta portfolioda jamlaydi.',
    },
    {
        "id": "growth", "chip": "Rivojlanish", "title": "Kitob va tashabbuslar",
        "points": ["Har oy — bitta kitob", "O‘quvchilar g‘oyasi", "Eng yaxshisini qo‘llab-quvvatlash"],
        "beats": [["books"], ["books", "book"], ["book", "ideas"]],
        "text": 'Har oy, bitta foydali kitob tavsiya qilinadi. [[300]] «Tashabbuslar» bo‘limida esa, o‘quvchilar o‘z g‘oyalarini yozadi, va eng yaxshilarini birgalikda qo‘llab-quvvatlaydi.',
    },
    {
        "id": "admin", "chip": "Boshqaruv", "title": "Rahbarlar uchun",
        "points": ["Statistika va maktablar", "Arizalarni tasdiqlash", "Oylik hisobot, dushanba dayjesti"],
        "beats": [["admin"], ["admin", "approvals"], ["approvals", "staff"]],
        "text": 'Admin panelida, statistika, maktablar, foydalanuvchilar va xodimlar boshqariladi. [[300]] Rahbarlarga esa, har oy hisobot, har dushanba esa qisqa dayjest, Telegram orqali keladi.',
    },
    {
        "id": "tech", "kind": "architecture", "chip": "Texnologiya", "title": "Qanday ishlaydi",
        "points": [], "beats": [[]],
        "text": 'Endi, texnik tomoni haqida. [[300]] Ilova Flutterda yozilgan, va bitta koddan Android, iOS va veb uchun yig‘iladi. Server, Python FastAPI’da ishlaydi. Ma’lumotlar bazasi, Supabase’dagi PostgreSQL. [[250]] Telegram bot esa, kirish va bildirishnomalarni boshqaradi. [[300]] O‘quvchilar ma’lumoti himoyalangan: har kim, faqat o‘ziga kerakli narsani ko‘radi.',
    },
    {
        "id": "close", "kind": "close", "chip": "", "title": "Kengash",
        "points": ["Odamlar hayotini osonlashtirish uchun"], "beats": [[]],
        "text": 'Kengash. [[400]] O‘quvchilar hayotini osonlashtirish uchun. [[300]] Bugunoq qo‘shiling!',
    },
]

# Faqat ovoz uchun talaffuz (subtitrda asl yozuv qoladi) / только для озвучки (в субтитрах — как написано)
SPOKEN = {"SMS": "es-em-es", "QR": "kyu-ar", "FastAPI": "Fast-API", "iOS": "ay-o-es", "PostgreSQL": "Postgres",
          "iPhone": "ayfon", "iPhoneda": "ayfonda", "Supabase’dagi": "Supabeysdagi", "FastAPI’da": "Fast-API-da", "Flutterda": "Flatterda"}


def spoken(text: str) -> str:
    for k, v in SPOKEN.items():
        text = re.sub(rf"(?<![\w’]){re.escape(k)}(?![\w’])", v, text)
    return text


PAUSE_SENTENCE = 380   # gap oxiridagi tabiiy nafas (ms) / естественный вдох после предложения
PAUSE_MARK = re.compile(r"\[\[(\d+)\]\]")


def display(text: str) -> str:
    """Subtitr uchun: pauza belgilarisiz / для субтитров: без меток пауз."""
    return re.sub(r"\s+", " ", PAUSE_MARK.sub(" ", text)).strip()


def sentences(text: str) -> list[str]:
    return [x.strip() for x in re.split(r"(?<=[.!?])\s+", display(text)) if x.strip()]


def phrases(text: str) -> list[tuple[str, int]]:
    """Matn → (ibora, keyingi pauza ms). Gap oxiri va [[ms]] belgisi — ibora chegarasi.
    Edge TTS endi o‘z SSML’ini (<break/>) qabul qilmaydi, shuning uchun pauzani o‘zimiz qo‘yamiz.
    Edge TTS больше не принимает свой SSML (<break/>), поэтому паузы вставляем сами."""
    out: list[tuple[str, int]] = []
    pos = 0
    for m in list(PAUSE_MARK.finditer(text)) + [None]:
        chunk = text[pos:m.start() if m else len(text)]
        pause = int(m.group(1)) if m else 0
        parts = [x.strip() for x in re.split(r"(?<=[.!?…])\s+", chunk) if x.strip()]
        for i, ph in enumerate(parts):
            last = i == len(parts) - 1
            gap = pause if last and m else (PAUSE_SENTENCE if re.search(r"[.!?…]$", ph) else 120)
            out.append((ph, gap))
        if m:
            pos = m.end()
    if out:
        out[-1] = (out[-1][0], 0)
    return out


# ------------------------------------------------------------------------------------------------ 3. OVOZ
SR = 24000  # barcha ovoz bir xil formatda (mono 16-bit) / весь звук в одном формате


def ffprobe_dur(p: Path) -> float:
    out = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(p)])
    return float(out.strip())


def to_pcm(src: Path) -> bytes:
    """Har qanday ovoz → 24 kHz mono 16-bit PCM, boshi/oxiridagi sukut kesilgan.
    Любой звук → PCM 24 кГц моно, тишина по краям обрезана (паузы задаём сами)."""
    trim = ("silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.03,"
            "areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.06,areverse")
    return subprocess.run(["ffmpeg", "-v", "error", "-i", str(src), "-af", trim, "-ac", "1", "-ar", str(SR),
                           "-f", "s16le", "-"], check=True, capture_output=True).stdout


def silence(ms: int) -> bytes:
    return b"\x00\x00" * int(SR * ms / 1000)


async def _edge_phrase(text: str, out: Path, voice: str, rate: str, pitch: str) -> None:
    import edge_tts
    for attempt in range(4):
        try:
            await edge_tts.Communicate(spoken(text), voice, rate=rate, pitch=pitch).save(str(out))
            if out.stat().st_size > 0:
                return
        except Exception as e:  # tarmoq uzilishi — qayta urinish / сбой сети — повтор
            if attempt == 3:
                raise
            print(f"   edge-tts qayta urinish ({e.__class__.__name__})")
        await asyncio.sleep(1.5 * (attempt + 1))


_LAT2CYR = [("o‘", "ў"), ("O‘", "Ў"), ("g‘", "ғ"), ("G‘", "Ғ"), ("sh", "ш"), ("Sh", "Ш"), ("ch", "ч"), ("Ch", "Ч"),
            ("yo", "ё"), ("Yo", "Ё"), ("yu", "ю"), ("Yu", "Ю"), ("ya", "я"), ("Ya", "Я"), ("’", "ъ")]
_CYR = dict(zip("abdefghijklmnopqrstuvxyzABDEFGHIJKLMNOPQRSTUVXYZ", "абдефгҳижклмнопқрстувхйзАБДЕФГҲИЖКЛМНОПҚРСТУВХЙЗ"))


def lat2cyr(t: str) -> str:
    t = re.sub(r"\b([Ee])", lambda m: "Э" if m.group(1) == "E" else "э", t)  # so‘z boshidagi e → э
    for a, b in _LAT2CYR:
        t = t.replace(a, b)
    return "".join(_CYR.get(c, c) for c in t)


_mms = None


def _mms_phrase(text: str, out: Path) -> None:
    """Internetsiz zaxira (faqat sinov): Meta MMS, kirill / офлайн-запасной вариант (только тест)."""
    global _mms
    import soundfile as sf
    import torch
    from transformers import AutoTokenizer, VitsModel
    if _mms is None:
        name = "facebook/mms-tts-uzb-script_cyrillic"
        _mms = (VitsModel.from_pretrained(name), AutoTokenizer.from_pretrained(name))
        torch.manual_seed(7)
    model, tok = _mms
    with torch.no_grad():
        wav = model(**tok(lat2cyr(spoken(text)), return_tensors="pt")).waveform[0].numpy()
    sf.write(out, wav, model.config.sampling_rate)


def synth_scene(sc: dict, work: Path, args) -> tuple[Path, list[tuple[float, float, str]]]:
    """Sahna ovozi iboralardan yig‘iladi: ibora + aniq pauza. Natija: wav va (boshlanish, tugash, gap) ro‘yxati.
    Озвучка сцены собирается из фраз с точными паузами. Возвращает wav и тайминги предложений."""
    pcm, t, spans = b"", 0.0, []
    for i, (ph, gap) in enumerate(phrases(sc["text"])):
        raw = work / f"{sc['id']}_p{i:02d}.{'mp3' if args.tts == 'edge' else 'wav'}"
        if not (args.reuse_audio and raw.exists() and raw.stat().st_size > 0):
            if args.tts == "edge":
                asyncio.run(_edge_phrase(ph, raw, args.voice, args.rate, args.pitch))
            else:
                _mms_phrase(ph, raw)
        seg = to_pcm(raw)
        d = len(seg) / 2 / SR
        spans.append((t, t + d, ph))
        pcm += seg + silence(gap)
        t += d + gap / 1000
    out = work / f"{sc['id']}.wav"
    import wave
    with wave.open(str(out), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm)
    return out, spans


# ------------------------------------------------------------------------------------------------ SUBTITR
def ass_time(t: float) -> str:
    cs = int(round(t * 100))
    return f"{cs // 360000}:{cs // 6000 % 60:02d}:{cs // 100 % 60:02d}.{cs % 100:02d}"


def srt_time(t: float) -> str:
    ms = int(round(t * 1000))
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"


def wrap(s: str, n: int = 44) -> list[str]:
    lines, cur = [], ""
    for w in s.split():
        if len(cur) + len(w) + 1 > n and cur:
            lines.append(cur)
            cur = w
        else:
            cur = f"{cur} {w}".strip()
    return lines + ([cur] if cur else [])


def cues_from(spans: list[tuple[float, float, str]]) -> list[tuple[float, float, str]]:
    """Har ibora → 1–2 qatorli subtitr; uzunlari teng bo‘laklarga, vaqt harf soniga mos.
    Каждая фраза → субтитр в 1–2 строки; длинные делятся, время пропорционально длине."""
    cues = []
    for a, b, ph in spans:
        lines = wrap(display(ph))
        chunks = [lines[i:i + 2] for i in range(0, len(lines), 2)]
        total = sum(len(" ".join(c)) for c in chunks)
        t = a
        for c in chunks:
            d = (b - a) * len(" ".join(c)) / total
            cues.append((t, t + d, c))
            t += d
    # yaqin subtitrlar orasida miltillash bo‘lmasin / без мигания между близкими субтитрами
    for i in range(len(cues) - 1):
        a, b, c = cues[i]
        if cues[i + 1][0] - b < 0.5:
            cues[i] = (a, cues[i + 1][0], c)
    return cues


def write_ass(path: Path, cues, font: str) -> None:
    """Professional subtitr: oq qalin shrift, 50% shaffof qora fon, pastda markazda, interfeysdan uzoqda.
    Профессиональные субтитры: белый жирный шрифт, полупрозрачный тёмный фон, по центру внизу."""
    # &HAABBGGRR: AA=80 → ~50% shaffof. BorderStyle=3 — har qator orqasida quti (libass OutlineColour’ni quti rangi qiladi)
    style = (f"Style: Default,{font},50,&H00FFFFFF,&H00FFFFFF,&H80000000,&H80000000,"
             "-1,0,0,0,100,100,0.2,0,3,14,0,2,260,260,64,1")
    head = ("[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\nWrapStyle: 2\n"
            "ScaledBorderAndShadow: yes\nYCbCr Matrix: TV.709\n\n"
            "[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, "
            "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, "
            f"Alignment, MarginL, MarginR, MarginV, Encoding\n{style}\n\n"
            "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")
    nl = "\\N"  # ASS qator uzilishi / перенос строки ASS (Python 3.8+ mos)
    ev = "".join("Dialogue: 0,{},{},Default,,0,0,0,,{{\\fad(120,120)}}{}\n".format(ass_time(a), ass_time(b), nl.join(c))
                 for a, b, c in cues)
    path.write_text(head + ev, encoding="utf-8")


def write_srt(path: Path, cues) -> None:
    path.write_text("".join(f"{i}\n{srt_time(a)} --> {srt_time(b)}\n{chr(10).join(c)}\n\n"
                            for i, (a, b, c) in enumerate(cues, 1)), encoding="utf-8")


# ------------------------------------------------------------------------------------------------ 2. VIZUAL
CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{width:1920px;height:1080px;overflow:hidden;font-family:Inter,'Inter Display',system-ui,sans-serif;color:#fff;
 background:radial-gradient(1200px 800px at 85% 20%,#6d3fe0 0%,transparent 60%),
 radial-gradient(900px 700px at 0% 100%,#2a1260 0%,transparent 60%),linear-gradient(135deg,#24104f,#3A1B78 55%,#4b23a3)}
.left{position:absolute;left:120px;top:150px;width:720px}
.chip{display:inline-block;padding:10px 22px;border-radius:999px;background:rgba(255,255,255,.14);
 font-weight:700;font-size:26px;letter-spacing:.5px;color:#e9ddff}
h1{font-size:76px;line-height:1.08;font-weight:800;margin-top:28px;letter-spacing:-1.5px}
ul{list-style:none;margin-top:44px}
li{font-size:34px;line-height:1.35;margin:18px 0;padding-left:46px;position:relative;color:#efe8ff}
li:before{content:'';position:absolute;left:4px;top:15px;width:18px;height:18px;border-radius:50%;background:#E8B628}
.brand{position:absolute;left:120px;top:64px;display:flex;align-items:center;gap:14px;font-weight:700;font-size:28px;opacity:.9}
.brand img{width:44px;height:44px;border-radius:12px}
.phones{position:absolute;right:120px;top:96px;height:740px;display:flex;gap:44px;align-items:center}
.phone{height:740px;border-radius:52px;padding:14px;background:#0d0820;box-shadow:0 40px 90px rgba(0,0,0,.45);
 transition:none}
.phone img{height:100%;border-radius:40px;display:block}
.phone.dim{opacity:.45;transform:scale(.9)}
.wide{position:absolute;right:110px;top:150px;width:960px;border-radius:24px;box-shadow:0 40px 90px rgba(0,0,0,.45)}
.center{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center}
.center img{width:180px;height:180px;border-radius:44px;box-shadow:0 30px 80px rgba(0,0,0,.4)}
.center h1{font-size:120px;margin-top:36px}
.center p{font-size:40px;margin-top:18px;color:#e9ddff}
.center .url{margin-top:40px;font-size:30px;padding:14px 30px;border-radius:999px;background:rgba(255,255,255,.12)}
.grid{position:absolute;right:110px;top:160px;width:980px;display:grid;grid-template-columns:1fr 1fr;gap:28px}
.box{background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.18);border-radius:24px;padding:28px 30px}
.box b{display:block;font-size:34px;margin-bottom:8px}.box span{font-size:25px;color:#e2d6ff;line-height:1.35}
.pain{position:absolute;right:120px;top:190px;width:900px}
.pain .box{margin-bottom:26px;display:flex;gap:26px;align-items:center;font-size:34px}
.pain .x{font-size:44px}
"""


def page(scene: dict, beat: list[str], idx: int) -> str:
    logo = (SCREENS / "logo.png").as_uri()
    pts = "".join(f"<li>{html.escape(p)}</li>" for p in scene["points"][: idx + 2 if scene["beats"][0] else 9])
    brand = f'<div class="brand"><img src="{logo}">Kengash</div>'
    left = (f'{brand}<div class="left"><span class="chip">{html.escape(scene["chip"])}</span>'
            f'<h1>{html.escape(scene["title"])}</h1><ul>{pts}</ul></div>')
    kind = scene.get("kind")
    if kind == "close":
        body = (f'<div class="center"><img src="{logo}"><h1>Kengash</h1><p>{html.escape(scene["points"][0])}</p>'
                f'<div class="url">a16067647-cmd.github.io/kengash · @KengashAppBot</div></div>')
    elif kind == "problem":
        icons = ["💬", "📄", "❓"]
        boxes = "".join(f'<div class="box"><span class="x">{i}</span>{html.escape(p)}</div>'
                        for i, p in zip(icons, scene["points"]))
        body = (f'{brand}<div class="left"><span class="chip">{scene["chip"]}</span><h1>{html.escape(scene["title"])}</h1>'
                f'</div><div class="pain">{boxes}</div>')
    elif kind == "architecture":
        items = [("📱 Flutter", "Bitta kod: Android, iOS, veb (GitHub Pages)"),
                 ("⚡ FastAPI", "Python server (Render)"),
                 ("🗄️ PostgreSQL", "Supabase · fayllar xavfsiz saqlanadi"),
                 ("🤖 Telegram bot", "Kirish, ro‘yxat, bildirishnomalar"),
                 ("🔒 Xavfsizlik", "Har kim faqat o‘ziga kerakini ko‘radi"),
                 ("🚀 Tezlik", "Sekin internetda ham darhol ochiladi")]
        boxes = "".join(f'<div class="box"><b>{a}</b><span>{html.escape(b)}</span></div>' for a, b in items)
        body = (f'{brand}<div class="left"><span class="chip">{scene["chip"]}</span><h1>{html.escape(scene["title"])}</h1>'
                f'<ul><li>Bitta koddan 3 platforma</li><li>Tez va arzon serverlar</li></ul></div><div class="grid">{boxes}</div>')
    elif beat and beat[0].startswith("@"):
        img = (SCREENS / f"{beat[0][1:]}.jpg").as_uri()
        body = f'{left}<img class="wide" src="{img}">'
    else:
        phones = "".join(
            f'<div class="phone{" dim" if (len(beat) > 1 and i < len(beat) - 1) else ""}">'
            f'<img src="{(SCREENS / (n + ".jpg")).as_uri()}"></div>' for i, n in enumerate(beat))
        body = f'{left}<div class="phones">{phones}</div>'
    return f"<!doctype html><html><head><meta charset='utf-8'><style>{CSS}</style></head><body>{body}</body></html>"


def chromium_path() -> str | None:
    env = os.environ.get("CHROMIUM_PATH")
    if env:
        return env
    c = sorted(glob.glob("/opt/pw-browsers/chromium-*/chrome-linux*/chrome"))
    return c[-1] if c else None


def render_beats(work: Path) -> dict[str, list[Path]]:
    from playwright.sync_api import sync_playwright
    out: dict[str, list[Path]] = {}
    with sync_playwright() as p:
        try:
            b = p.chromium.launch()
        except Exception:
            b = p.chromium.launch(executable_path=chromium_path())
        pg = b.new_page(viewport={"width": W, "height": H}, device_scale_factor=1)
        for sc in SCENES:
            out[sc["id"]] = []
            for i, beat in enumerate(sc["beats"]):
                f = work / f"{sc['id']}_{i}.html"
                f.write_text(page(sc, beat, i), encoding="utf-8")
                pg.goto(f.as_uri())
                pg.wait_for_load_state("networkidle")
                png = work / f"{sc['id']}_{i}.png"
                pg.screenshot(path=str(png))
                out[sc["id"]].append(png)
        b.close()
    return out


# ------------------------------------------------------------------------------------------------ 4. YIG‘ISH
def beat_times(n: int, spans, dur: float) -> list[float]:
    """Ekran almashishi gap boshiga to‘g‘ri keladi (ovoz bilan sinxron) / смена экрана — на начале предложения."""
    starts = [a for a, _, _ in spans]
    cuts = [0.0]
    for i in range(1, n):
        want = dur * i / n
        best = min(starts[1:] or [want], key=lambda x: abs(x - want))
        cuts.append(best if best > cuts[-1] + 1.2 else want)
    return [cuts[i + 1] - cuts[i] if i + 1 < n else dur - cuts[i] for i in range(n)]


def build(args) -> None:
    work = Path(args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    print("2/4 Playwright: sahnalar chizilmoqda…")
    beats = render_beats(work)

    print(f"3/4 Ovoz ({args.tts}: {args.voice if args.tts == 'edge' else 'MMS'}) va subtitr…")
    lead = 0.35                     # har sahna boshida qisqa nafas / короткий вдох в начале сцены
    starts, t, cues, plan, audio = {}, 0.0, [], [], {}
    for sc in SCENES:
        wav, spans = synth_scene(sc, work, args)
        audio[sc["id"]] = wav
        d = lead + ffprobe_dur(wav) + PAD
        starts[sc["id"]] = t
        cues += [(t + lead + a, t + lead + b, c) for a, b, c in cues_from(spans)]
        shifted = [(lead + a, lead + b, ph) for a, b, ph in spans]
        for png, bd in zip(beats[sc["id"]], beat_times(len(beats[sc["id"]]), shifted, d)):
            plan.append((png, bd))
        t += d
    total = t

    ass, srt = work / "presentation_uz.ass", work / "presentation_uz.srt"
    write_ass(ass, cues, args.font)
    write_srt(srt, cues)

    # Har beat — sekin zoom bilan klip / каждый beat — клип с медленным зумом
    clips = []
    for i, (png, d) in enumerate(plan):
        dd = d + (XFADE if i < len(plan) - 1 else 0)
        frames = int(round(dd * FPS))
        clip = work / f"clip_{i:03d}.mp4"
        z = "1+0.035*on/{}".format(max(frames, 1))
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-loop", "1", "-i", str(png), "-vf",
                        f"scale={W*2}:{H*2},zoompan=z='{z}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d={frames}:s={W}x{H}:fps={FPS},format=yuv420p",
                        "-frames:v", str(frames), "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", str(clip)], check=True)
        clips.append((clip, dd))

    # Klip ketma-ketligi xfade bilan / цепочка xfade
    inputs, fc, off, last = [], [], 0.0, "0:v"
    for c, _ in clips:
        inputs += ["-i", str(c)]
    for i in range(1, len(clips)):
        off += clips[i - 1][1] - XFADE
        fc.append(f"[{last}][{i}:v]xfade=transition=fade:duration={XFADE}:offset={off:.3f}[v{i}]")
        last = f"v{i}"
    video = work / "video_noaudio.mp4"
    subprocess.run(["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", ";".join(fc), "-map", f"[{last}]",
                    "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-r", str(FPS), str(video)], check=True)

    # Ovoz: har sahna o‘z vaqtida, yumshoq EQ va bir xil balandlik / звук: по сценам, мягкий EQ, ровная громкость
    ain, amix = [], []
    for i, sc in enumerate(SCENES):
        ain += ["-i", str(audio[sc["id"]])]
        ms = int((starts[sc["id"]] + lead) * 1000)
        amix.append(f"[{i}:a]adelay={ms}|{ms}[a{i}]")
    voice = work / "voice_uz.m4a"
    subprocess.run(["ffmpeg", "-y", "-v", "error", *ain, "-filter_complex",
                    ";".join(amix) + ";" + "".join(f"[a{i}]" for i in range(len(SCENES))) +
                    f"amix=inputs={len(SCENES)}:normalize=0,highpass=f=70,"
                    "equalizer=f=3200:t=q:w=1.2:g=2,acompressor=threshold=-20dB:ratio=2.5:attack=8:release=120,"
                    f"apad,atrim=0:{total:.3f},loudnorm=I=-16:TP=-1.5:LRA=9[a]",
                    "-map", "[a]", "-ar", "48000", "-c:a", "aac", "-b:a", "192k", str(voice)], check=True)

    print("4/4 FFmpeg: yakuniy video (ASS subtitr)…")
    final = Path(args.out).resolve()
    esc = lambda p: str(p).replace("\\", "/").replace(":", "\\:").replace("'", "\\'")  # noqa: E731
    vf = f"ass='{esc(ass)}'" + (f":fontsdir='{esc(args.fonts_dir)}'" if args.fonts_dir else "")
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(video), "-i", str(voice), "-vf", vf,
                    "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                    "-pix_fmt", "yuv420p", "-r", str(FPS), "-c:a", "copy", "-shortest",
                    "-movflags", "+faststart", str(final)], check=True)
    shutil.copy(srt, final.with_suffix(".srt"))
    shutil.copy(ass, final.with_suffix(".ass"))
    print(f"Tayyor: {final} ({total:.1f} s), {final.with_suffix('.srt').name}, {final.with_suffix('.ass').name}")


def write_script_md(path: Path) -> None:
    """Ssenariyni o‘qish uchun / сценарий для чтения."""
    lines = ["# Kengash — taqdimot ssenariysi (o‘zbekcha)\n"]
    for i, sc in enumerate(SCENES, 1):
        shots = " → ".join("+".join(b) or "(slayd)" for b in sc["beats"])
        lines.append(f"## {i}. {sc['chip'] or 'Yakun'} — {sc['title']}\n\n**Ekranda:** {shots}\n\n**Ovoz:** {display(sc['text'])}\n")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description="Kengash taqdimot videosi (o‘zbekcha)")
    ap.add_argument("--tts", choices=["edge", "mms"], default="edge", help="edge = Sardor (internet), mms = internetsiz sinov")
    ap.add_argument("--voice", default=VOICE, help="uz-UZ-SardorNeural (erkak) yoki uz-UZ-MadinaNeural (ayol)")
    ap.add_argument("--rate", default="-6%", help="nutq tezligi, masalan -6%% (sekinroq, tabiiyroq)")
    ap.add_argument("--pitch", default="+0Hz")
    ap.add_argument("--font", default="Inter", help="subtitr shrifti (yo‘q bo‘lsa: Arial)")
    ap.add_argument("--fonts-dir", default="", help="shrift fayllari papkasi (ixtiyoriy)")
    ap.add_argument("--reuse-audio", action="store_true", help="avval yozilgan iboralarni qayta ishlatish")
    ap.add_argument("--work", default=str(HERE / "build"))
    ap.add_argument("--out", default="presentation_uz.mp4")
    ap.add_argument("--script-only", action="store_true", help="faqat ssenariy.md yozish")
    args = ap.parse_args()
    print("1/4 Ssenariy…")
    write_script_md(HERE / "ssenariy.md")
    if not args.script_only:
        build(args)


if __name__ == "__main__":
    sys.exit(main())
