# Taqdimot videosi / Презентационное видео

`presentation_uz.mp4` (1920×1080, 30 fps): tabiiy o‘zbekcha ovoz (edge-tts, `uz-UZ-SardorNeural`)
va videoga yozilgan chiroyli o‘zbekcha subtitr (`.ass` va `.srt` ham alohida).

```
pip install edge-tts playwright pillow
python -m playwright install chromium
# ffmpeg o‘rnatilgan bo‘lishi kerak / нужен ffmpeg
python tools/video/generate_video.py
```

Variantlar / опции:

| Buyruq | Nima qiladi |
|---|---|
| `--voice uz-UZ-MadinaNeural` | Ayol ovozi (standart — Sardor) |
| `--rate -6%` | Nutq tezligi (sekinroq = tabiiyroq; `-10%`…`+5%`) |
| `--font Arial` | Subtitr shrifti (standart — Inter; yo‘q bo‘lsa Arial) |
| `--reuse-audio` | Matnni o‘zgartirmasdan videoni qayta yig‘ish (ovoz qayta yozilmaydi) |
| `--script-only` | Faqat `ssenariy.md` |
| `--tts mms` | Internetsiz sinov ovozi (sifati past, faqat sinov) |

Tabiiy nutq qanday qilingan:
- Matnda vergul va qisqa gaplar; `[[350]]` — 350 ms pauza (subtitrda ko‘rinmaydi).
- Edge TTS endi `<break/>` SSML’ni qabul qilmaydi, shuning uchun har ibora alohida o‘qiladi va orasiga aniq pauza qo‘yiladi.
- Gap oxirida ~0.4 s nafas, ekran almashishi gap boshiga to‘g‘ri keladi.

Subtitr: oq qalin shrift, 50% shaffof qora fon, pastda markazda, chetlardan 260 px, pastdan 64 px.
