# Taqdimot videosi / Презентационное видео

`presentation_uz.mp4` (1920×1080, 30 fps): tabiiy o‘zbekcha ovoz (edge-tts, `uz-UZ-SardorNeural`)
va videoga yozilgan chiroyli o‘zbekcha subtitr (`.ass` va `.srt` ham alohida).

```
pip install edge-tts playwright pillow
python -m playwright install chromium
# ffmpeg o‘rnatilgan bo‘lishi kerak / нужен ffmpeg
python tools/video/generate_video.py
```

### Eng tabiiy ovoz (ixtiyoriy) / самый естественный голос

Kalit bo‘lsa, skript o‘zi tanlaydi: **ElevenLabs → OpenAI → edge-tts**. Kalitni faqat muhit o‘zgaruvchisida saqlang
(repozitoriyga yozmang — u ochiq).

```
# Windows PowerShell:  $env:ELEVENLABS_API_KEY="..."      macOS/Linux:  export ELEVENLABS_API_KEY=...
export ELEVENLABS_VOICE_ID=...        # ixtiyoriy: Voice Library’dan tanlangan ovoz
export ELEVENLABS_MODEL=eleven_v3     # standart; o‘zbekcha shu modelda
python tools/video/generate_video.py
```

OpenAI: `OPENAI_API_KEY` (ixtiyoriy: `OPENAI_TTS_VOICE=ash`, `OPENAI_TTS_MODEL=gpt-4o-mini-tts`).
Majburan tanlash: `--tts elevenlabs | openai | edge`.

Variantlar / опции:

| Buyruq | Nima qiladi |
|---|---|
| `--voice uz-UZ-MadinaNeural` | Ayol ovozi (standart — Sardor) |
| `--rate -6%` | Nutq tezligi (sekinroq = tabiiyroq; `-10%`…`+5%`) |
| `--font Arial` | Subtitr shrifti: nom yoki `.ttf` yo‘li (standart — Inter; yo‘q bo‘lsa Arial Bold) |
| `--sub-opacity 0.85` | Subtitr qutisi qoraligi (0–1, standart 0.78) |
| `--reuse-audio` | Matnni o‘zgartirmasdan videoni qayta yig‘ish (ovoz qayta yozilmaydi) |
| `--script-only` | Faqat `ssenariy.md` |
| `--tts mms` | Internetsiz sinov ovozi (sifati past, faqat sinov) |

Tabiiy nutq qanday qilingan:
- Matnda vergul va qisqa gaplar; `[[350]]` — 350 ms pauza (subtitrda ko‘rinmaydi).
- Edge TTS endi `<break/>` SSML’ni qabul qilmaydi, shuning uchun har ibora alohida o‘qiladi va orasiga aniq pauza qo‘yiladi.
- Gap oxirida ~0.4 s nafas, ekran almashishi gap boshiga to‘g‘ri keladi.

Subtitr: har bir subtitr — bitta PNG (barcha qatorlar bitta yumaloq qora quti ichida), FFmpeg `overlay` bilan
aniq vaqtda qo‘yiladi. Bir vaqtda faqat bitta subtitr — ustma-ust tushish imkonsiz. Oq qalin shrift 46 px,
pastda markazda, yumshoq paydo bo‘lish/so‘nish.
