# Taqdimot videosi / Презентационное видео

`presentation_uz.mp4` (1920×1080, 30 fps) yasaydi: o‘zbekcha ovoz (edge-tts, `uz-UZ-SardorNeural`)
va videoga yozilgan o‘zbekcha subtitr (`.srt` ham alohida).

```
pip install edge-tts playwright pillow
python -m playwright install chromium
# ffmpeg o‘rnatilgan bo‘lishi kerak / нужен ffmpeg
python tools/video/generate_video.py            # → presentation_uz.mp4 + presentation_uz.srt
python tools/video/generate_video.py --script-only   # faqat ssenariy.md
```

- Ssenariy va sahnalar: `generate_video.py` ichidagi `SCENES` (matnni o‘zgartirsangiz, video o‘zi moslashadi).
- Ekranlar: `screens/` — ilovaning test ma’lumotlari bilan olingan haqiqiy ekranlari (haqiqiy o‘quvchilar yo‘q).
- Internetsiz sinov: `--tts mms` (Meta MMS, `pip install torch transformers soundfile`; litsenziya CC-BY-NC — faqat sinov).
