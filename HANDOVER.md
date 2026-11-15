# Kengash — topshirish hujjati / документ передачи

**Kengash** — Kelajak O‘quvchilar Kengashi koordinatorlari uchun yagona ilova (Android, iPhone, sayt).
To‘liq talablar: [`KENGASH-PROMPT.md`](KENGASH-PROMPT.md). Dizayn asosi: [`IDROK-APP-BLUEPRINT.md`](IDROK-APP-BLUEPRINT.md).

## Holat / статус
| Bosqich | Nima | Holat |
|---|---|---|
| 1 | Telegram orqali kirish, kalitlar, profil, koordinatorlar, admin paneli, huquqiy sahifalar, ochilish animatsiyasi | ✅ ishlamoqda |
| 2 | Kanallar: avtomatik + yaratiladigan, matn, surat, video, fayl, ovozli xabar, javob, tahrir, mahkamlash, shikoyat, jonli yangilanish | ✅ |
| 2b | Bildirishnomalar — **Telegram bot orqali** (sozlash shart emas); Firebase ixtiyoriy, keyin | ✅ |
| 3 | Vazifalar + fotohisobot (qabul/qaytarish), taqvim + «Boraman», «Bugun» xulosasi, eslatmalar | ✅ |
| 4 | To‘lov (Click/Payme), promo-kod, QR | ⏳ (YaTT/MChJ kerak) |

## Kod xaritasi / карта кода
```
app/                      Flutter ilova (Android, iOS, web)
  lib/main.dart           ekranlar tartibi, tab bar (telefon), yon menyu (kompyuter)
  lib/theme.dart          dizayn tokenlari (binafsha Kelajak ranglari), yo‘nalish ranglari
  lib/widgets.dart        umumiy komponentlar (Idrok’dan)
  lib/brand.dart          O‘quvchilar Kengashi belgisi (kod bilan chizilgan), logotiplar
  lib/state.dart          holat, sozlamalar, sessiya
  lib/api.dart            server bilan aloqa
  lib/i18n.dart           uz + ru matnlar (kalitlar bir xil — test tekshiradi)
  lib/chat.dart           kanallar holati, yuborish/yuklash, WebSocket (uzilsa — 20 soniyada yangilash)
  lib/screens/            auth, onboarding, intro, today, channels, audience, media, directory, keys, profile, admin, legal
  assets/legal.json       Biz haqimizda, Maxfiylik, Shartlar, Cookie, Hisobni o‘chirish (ilova VA sayt uchun yagona manba)
  test/                   ekran testlari (soxta server bilan), skrinshotlar
  tool/setup_platforms.py android/ios papkalarini yaratadi
server/                   Python (FastAPI) + Postgres (Supabase) / SQLite (lokal)
  app.py                  API
  model.py                yo‘nalishlar, «kim kimdan yuqori» (is_above) — kalit, telefon, o‘rin bo‘shatish shu qoidaga tayanadi
  telegram.py             bot: kirish va raqamni tasdiqlash
  channels.py             kanallar: avtomatik kanallar (sync_user), auditoriya, xabarlar, fayllar, shikoyatlar, WebSocket
  storage.py              Supabase Storage, yopiq «kengash-media» bucket, imzolangan havolalar
  realtime.py             jonli ulanishlar (xotirada, bitta server)
  plan.py                 vazifalar, tadbirlar, /api/today, push ro‘yxati, eslatmalar (har 5 daqiqa)
  push.py                 bildirishnomalar: @KengashAppBot orqali (asosiy, chat — kanal boshiga 10 daqiqada 1 ta) + Firebase (ixtiyoriy)
  core_limits.py          chegaralar: video 50 MB, fayl 20 MB, ovoz 5 daqiqa, 20 xabar/daqiqa
  seed.py                 Andijon viloyati va 16 tuman/shahar
  legal.py                ochiq huquqiy sahifalar (GitHub Pages)
  tests/                  server testlari
render.yaml               Render sozlamasi (Starter, ~7$/oy)
.github/workflows/        avtomatik tekshirish, APK, sayt
```

## Asosiy qoidalar / главные правила
- ★ **Soddalik birinchi o‘rinda** (egasining asosiy talabi): har ekranda bitta asosiy amal; ishlamaydigan narsa ko‘rinmaydi; aqlli tanlov oldindan belgilangan; asosiy ishlar ≤ 3 bosish; shubha bo‘lsa — olib tashlang. Batafsil: `KENGASH-PROMPT.md` boshida.
- **Kim kimdan yuqori** (`server/model.py → is_above`): admin → hammasi; viloyat koordinatori → o‘z viloyatidagi tuman va maktablar, o‘z yo‘nalishi (Lider — hammasi); tuman koordinatori → o‘z tumanidagi maktablar, o‘z yo‘nalishi (Lider — hammasi).
- Kalit: bir martalik, 7 kun, bitta o‘ringa; bazada faqat xeshi. Admin tasdig‘i kerak emas.
- Telefon raqami faqat yuqoridagilarga va adminga ko‘rinadi.
- Admin: `ADMIN_TG_IDS` dagi Telegram ID bilan kirgan odam.
- Har bir matn uz + ru. Ranglar faqat `theme.dart` dan.

## Ishga tushirish / запуск
```bash
# server
cd server && pip install -r requirements.txt pytest && python -m pytest -q
DEV_LOGIN=1 ADMIN_TG_IDS=1 uvicorn app:app --port 8787
# ilova
cd app && flutter pub get && flutter test
flutter run -d chrome --dart-define=SERVER=http://localhost:8787
```

## Hozirgi o‘rnatish / текущая установка
- Server: Render **kengash-api** (bepul, Singapur) — https://kengash-api.onrender.com
- Baza: mavjud Supabase loyihasi (ap-south-1), alohida **kengash** sxemasi va **kengash_app** foydalanuvchisi — Idrok jadvallaridan ajratilgan.
- Bot: **@KengashAppBot**; admin Telegram ID `ADMIN_TG_IDS` da.
- Fayllar: o‘sha Supabase loyihasidagi yopiq **kengash-media** bucket (bepul 1 GB — Idrok bilan umumiy). Render’da `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`.
- Shaxsiy xabar yo‘q (egasining qarori): faqat kanallar; shaxsiy gap — profildagi Telegram havolasi orqali.
- Bepul server 15 daqiqadan keyin uxlaydi: birinchi ochilish 30–60 soniya. Investitsiyadan keyin Render’da Starter’ga o‘ting (~7$/oy).

## Ishga tushirishdan oldin (egasi qiladi) / до запуска (делает владелец)
1. **Telegram bot**: @BotFather → `/newbot` → nom `Kengash`, username masalan `KengashAppBot` → tokenni Render’ga.
2. **Supabase**: yangi loyiha → Database → Connection string (URI, «Transaction pooler») → Render `DATABASE_URL`.
3. **Render**: New → Blueprint → `kengash` repo → qiymatlarni kiriting (Starter ~7$/oy).
4. `ADMIN_TG_IDS`: Telegram’da @userinfobot ga yozing → ID raqamingiz.
5. GitHub → Settings → Pages → Source: **GitHub Actions**.
6. Eslatma: O‘zbekiston shaxsiy ma’lumotlar qonuni fuqarolar ma’lumotini O‘zbekistondagi serverda saqlashni talab qilishi mumkin — ishga tushirishdan oldin tekshiring.
