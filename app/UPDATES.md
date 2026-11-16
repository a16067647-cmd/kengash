# Ilova yangilanishi / обновление приложения

- Har `main` chiqishida CI saytga `version.json` yozadi: `{"build": N, "min": M, "apk": "Kengash.apk"}`.
  Eski APK ochilganda yuqorida «Yangi versiya bor — Yangilash» banneri chiqadi.
- **Majburiy yangilanish:** `app/update_min_build.txt` ga raqam yozing (masalan, `52`).
  Shundan kichik APK’lar ishlamaydi — faqat «Ilovani yangilang» ekrani ko‘rinadi.
  `0` — majburiy yangilanish yo‘q.
- Sayt (brauzer) o‘zi yangilanadi, unga banner kerak emas.

---

- При каждом выпуске в `main` CI пишет на сайт `version.json`. Старый APK показывает баннер «Есть новая версия».
- **Обязательное обновление:** впишите номер сборки в `app/update_min_build.txt`; более старые APK
  покажут только экран «Обновите приложение». `0` — без обязательного обновления.
