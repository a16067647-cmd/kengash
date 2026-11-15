# KENGASH — app specification (the "prompt")

> **For Claude:** this is the full specification of **Kengash**, the app for the coordinators of
> **Kelajak O‘quvchilar Kengashi** in Andijan viloyati. It sits on top of the **Idrok App Blueprint**
> (`IDROK-APP-BLUEPRINT.md`, same folder). Everything the blueprint says about components, motion,
> languages, legal pages, security, working rules and the publishing pipeline **still applies**,
> except where this file says otherwise. Where they disagree, **this file wins**. The biggest
> difference: Kengash is **violet** (Kelajak Markazlari colours), so the blueprint's "no violet"
> rule does **not** apply here.

---

## ★ The first rule: simple and easy (owner's top priority)

Kengash exists to make coordinators' lives **easier**. Every screen must pass these checks:

1. **One main action per screen**, obvious at a glance. Secondary things go in a list row or a "…" sheet.
2. **Nothing that doesn't work yet**: no "coming soon" tabs, cards or buttons. A feature appears when it works.
3. **Smart defaults over choices.** Pre-select the most common option (e.g. channel members are suggested by the person's seat); advanced options hide behind "Boshqa…".
4. **The main tasks take ≤ 3 taps** (read new messages, write in a channel, give a key, create a channel).
5. **Plain words** in Uzbek and Russian, no jargon; short labels; one sentence of help at most.
6. **Calm screens**: no decoration that carries no information (no rotating tips, no filler cards, no duplicate links).
7. When in doubt, **remove** rather than add. Ask the owner before adding a new setting or option.

## 0. The app in one paragraph

**Kengash** replaces the many Telegram groups of Kelajak O‘quvchilar Kengashi with **one app**. Every
coordinator (a school student) signs in with Telegram, gets their place by a one-time **key** from
the coordinator above them, and then sees in one place: **what to do today**, their **channels**
(group chats and announcement channels), **tasks with deadlines and photo reports**, the **events
calendar**, and a **directory of all coordinators** with their Telegram links.

- **uz:** Kengash — Kelajak O‘quvchilar Kengashi koordinatorlari uchun yagona ilova: kanallar, vazifalar, tadbirlar va barcha koordinatorlar bir joyda. Endi o‘nlab Telegram guruhlari kerak emas.
- **ru:** Kengash — единое приложение для координаторов Совета учеников «Kelajak»: каналы, задачи, мероприятия и все координаторы в одном месте. Больше не нужны десятки Telegram-групп.
- **Short tagline:** `Hamma narsa bir joyda` / `Всё в одном месте`.

**Scope now: Andijan viloyati only.** The data model must already support more viloyats (a
`region` table), so the country-wide version later is only data, not a rewrite.

---

## 1. People and structure

### 1.1 Levels
`Maktab (school) → Tuman/shahar (district) → Viloyat (region)` plus the **Admin** (the creator, above everyone).

### 1.2 The 8 directions (yo‘nalishlar)

| Key | Uzbek | Russian |
|---|---|---|
| `lider` | Lider | Лидер |
| `talim` | Ta’lim | Образование |
| `ijtimoiy` | Ijtimoiy tashabbus | Социальная инициатива |
| `it` | IT va sun’iy intellekt | IT и искусственный интеллект |
| `media` | Media | Медиа |
| `ekologiya` | Ekologiya | Экология |
| `sport` | Sport | Спорт |
| `madaniyat` | Madaniyat | Культура |

The O‘quvchilar Kengashi logo has **8 dots** around the ring, one per direction. Use this in the
UI: each direction gets one fixed colour (§2.3), and the yellow top dot belongs to **Lider**.

### 1.3 Seats
A **seat** = level + place + direction. Examples: *School 59, Asaka, IT* · *Asaka tumani, IT* ·
*Andijon viloyati, Lider*. Every school, district and region has 8 seats.

- **One person per seat.** To replace someone, the coordinator above (or the admin) **frees the
  seat** first. The old holder's account stays, without a seat ("Sobiq koordinator"), until they
  get a new key or are deleted.
- A person holds **one seat** at a time.

### 1.4 Districts of Andijan viloyati (pre-filled)
Andijon shahri, Xonobod shahri, Andijon tumani, Asaka, Baliqchi, Bo‘ston, Buloqboshi, Izboskan,
Jalaquduq, Xo‘jaobod, Qo‘rg‘ontepa, Marhamat, Oltinko‘l, Paxtaobod, Shahrixon, Ulug‘nor
(16, with Russian names). The admin can edit or rename them.

### 1.5 Schools
There is **no official list**, so the admin panel must make adding schools fast:
- **Bulk add:** choose a district, type `1-62` or `1, 2, 5, 59` → creates "59-maktab" etc.
- Optional custom name per school (e.g. "Ixtisoslashtirilgan maktab").
- Edit, merge duplicates, hide. Schools with users can't be deleted, only hidden.

### 1.6 Who is "above" whom (one function, used everywhere)
`isAbove(A, B)` is true when:
1. A is **Admin**; or
2. A is a **viloyat** coordinator of the same region and (same direction **or** A is Lider), and B is district or school level; or
3. A is a **tuman** coordinator of B's district and (same direction **or** A is Lider), and B is school level.

This one rule controls: who can **give keys** for a seat, who sees a person's **phone number**, who
sees **task reports**, and who can **free a seat**. Put it in one server function with unit tests
for every case.

---

## 2. Design (Kelajak violet)

Everything in blueprint §2 applies (typography, spacing, radii, shadows, glass, components, motion,
live background), with **these colours instead of the blue ones**.

### 2.1 Light theme

| Token | Hex | Use |
|---|---|---|
| `bg` | `#F5F3FA` | Page background |
| `surface` / `elevated` | `#FFFFFF` | Cards, sheets |
| `surfaceAlt` | `#EEEAF6` | Inset areas, tracks, skeletons |
| `glass` / `glassEdge` | `#FFFFFF` @ 78 % / @ 90 % | Glass panels |
| `hairline` / `hairlineStrong` | `#1A0F3D` @ 8 % / 14 % | Borders |
| `text` | `#1A0F3D` | Main text (deep violet-navy) |
| `text2` | `#5F5878` | Secondary text |
| `text3` | `#A29CB6` | Hints, chevrons |
| `accent` | `#5B2DC9` | Primary violet (buttons, links, selection) |
| `accentHi` | `#8A63F2` | Light end of gradients |
| `accentText` | `#4A20B0` | Violet text on light backgrounds |
| `accentSoft` | `#EFE9FC` | Selected tab pill, soft badges |
| `success` | `#0795D9` (soft `#E1F5FF`) | Done states (kept sky-blue) |
| `danger` | `#D93A44` (soft `#FFE9EA`) | Errors, delete |
| `warning` | `#E59A00` (soft `#FFF4D6`) | Deadlines soon, overdue badges |

### 2.2 Dark theme

| Token | Hex |
|---|---|
| `bg` | `#0A0714` |
| `surface` / `surfaceAlt` / `elevated` | `#141022` / `#1C172E` / `#241E3A` |
| `glass` / `glassEdge` | `#141022` @ 65 % / `#FFFFFF` @ 14 % |
| `hairline` / `hairlineStrong` | `#FFFFFF` @ 8 % / 15 % |
| `text` / `text2` / `text3` | `#F4F1FA` / `#A9A2BE` / `#6B6482` |
| `accent` / `accentHi` / `accentText` / `accentSoft` | `#8B66FF` / `#B49BFF` / `#C3AEFF` / `#8B66FF` @ 18 % |
| `success` / `danger` / `warning` | `#0E93D6` / `#FF7A80` / `#FFC24A` |

### 2.3 Brand constants
- **Kelajak violet** `#3A1B78`: hero cards, splash background, app icon background.
- **Kengash blue** `#032BA5` and **Kengash sun** `#FFBB02`: the O‘quvchilar Kengashi logo colours. Sun is the warm accent (badges, "today", highlights), never a background.
- **Hero gradient:** `#6A3DE0 → #3A1B78` (dark: `#7A4FF0 → #2A115E`). Accent gradient: `accentHi → accent`.
- **Direction colours** (chips, avatars rings, channel icons): Lider `#FFBB02`, Ta’lim `#0A6CFF`, Ijtimoiy tashabbus `#FF5A6E`, IT `#5B2DC9`, Media `#FF9F0A`, Ekologiya `#34C759`, Sport `#00A89D`, Madaniyat `#D6409F`.
- **Live background** (blueprint §2.11): same behaviour, dots and lines in `accent` / `accentHi`.

### 2.4 Logos
- **App icon:** the Kelajak Markazlari logo (white "Kelajak" script on `#3A1B78`), rounded square. Source: Idrok repo `app/assets/team/kelajak.jpg` (480 px). Ask the owner for a bigger/SVG file before store release.
- **O‘quvchilar Kengashi logo** (redrawn as vector, `assets/brand/ok-mark.svg` + full lockup): on the **splash**, the **login screen** (above the app name), the **About page**, and as the **desktop sidebar** header mark. In dark mode the blue parts become white.
- **Idrok Corporation:** shown on the About page as **creator and partner**.

---

## 3. Sign-in, keys and profiles

### 3.1 Telegram login (free, no passwords, no SMS)
1. App: **Telegram orqali kirish / Войти через Telegram** button.
2. Server creates a login request (random id, 10 min life) and returns `https://t.me/<KengashBot>?start=login_<id>`.
3. The app opens Telegram. The bot asks the user to tap **"📱 Raqamni ulashish / Поделиться номером"** (Telegram's contact button).
4. The bot checks the shared contact belongs to the same Telegram user, then marks the request done with: Telegram id, username, first/last name, phone.
5. The app checks the request every 2 s and receives the login token. Then: "Telegram'ga qayting… / Вернитесь в приложение" screen with a big "Ilovaga qaytish" button (bot sends a button too).

Rules: bot token and webhook secret only on the server; webhook requests must carry Telegram's `X-Telegram-Bot-Api-Secret-Token`. Tokens as in blueprint §6.3. Works the same on Android, iPhone and website. If the person has **no Telegram username**, ask them to set one (show how) because private talk goes through Telegram links. Allow continuing, but show a reminder on their profile.

### 3.2 Registration — only in @KengashAppBot (step 4)
Keys are gone. The admin never hands out keys or free months.
1. Telegram login (above). A new user sees one screen: **Botni ochish / Открыть бота**.
2. In the bot the person **types only the full name** (2+ words). Everything else is buttons:
   role (O‘quvchi / Koordinator / Maslahatchi) → for coordinators the level → tuman → school (6 numbers per row) →
   class 1–11 + letter (students) or direction (coordinators) → summary with links to the rules → **Tasdiqlash**.
3. **One person per seat.** If the seat is taken (active or pending), the bot shows who to message instead
   (the approvers of that seat, with Telegram links).
4. **Approvals** (the bot sends ✅/❌ buttons to the approver; the app has *Arizalar* on Bugun):
   - students — none, active immediately;
   - school coordinators — their school's maslahatchi (fallback: tuman Lider);
   - maslahatchi — tuman Lider (fallback: viloyat Lider);
   - tuman coordinators — viloyat Lider;
   - viloyat coordinators — admin. Nobody found → admin.
5. While pending, the app shows *Tasdiq kutilmoqda* with the approvers' cards and opens by itself when approved.
   Rejected → back to registration.

### 3.3 Roles
- **Koordinator** — school / tuman / viloyat, one of 8 directions.
- **Maslahatchi** — teacher, one per school. Team chat with the school's 8 coordinators, gives tasks to them and to students,
  approves the school's coordinators.
- **O‘quvchi** — free. Gives name, school, class (e.g. 7-B). Sees only: *Kengash e’lonlari*, the school news channel
  (coordinators + maslahatchi post) and the school chat (everyone writes). Visible only to their school's coordinators and
  maslahatchi. **Tuman and viloyat never see students or student channels.**
- School coordinators give tasks to their school's students.
- *Kengash e’lonlari*: everyone reads; only the admin and the viloyat Lider post.
- **Payments:** 5 000 so‘m/month for coordinators (all levels) and maslahatchi; students free. Unpaid → the app is locked,
  opens right after paying. Switched off (`PAYMENTS_ENABLED`) until Click/Payme and a YaTT/MChJ exist.

### 3.3b Rating (coordinators only)
- **Tasks:** after the report (or after the deadline), the task giver may give **+1** or **−1** — or nothing.
  Not rating is normal; it keeps points precious. Tapping the chosen value again removes it.
- **Meetings:** after the start time, the organizer marks each guest **came (+1)** or **missed (−1)**, or leaves them unmarked.
- **Public leaderboard** (*Reyting*): everyone who is not a student can see it. Default group: your level in your area
  (school coordinators in the tuman, tuman coordinators in the viloyat, viloyat team). Filters: level, tuman, direction.
- Score **restarts every quarter** (Tashkent time); the history of points is kept.
- Students and maslahatchi are not rated. Students don't see the rating.

### 3.3d Oy kitobi (book of the month)
- One book per direction (8). The **admin** adds a cover, a PDF (≤ 50 MB), title, author, month and a short description.
  A new book **replaces** the old one (the old files and "read" marks are deleted).
- **Everyone** sees all 8 books on *Bugun* (students too): glass cards in the direction's colour and emoji
  (👑 Lider, 📚 Ta’lim, 🤝 Ijtimoiy, 🤖 IT, 🎬 Media, 🌿 Ekologiya, ⚽ Sport, 🎭 Madaniyat). Your own direction comes first.
  No books → the section is hidden.
- Reading happens **inside the app**: smooth scrolling, pinch/double-tap zoom, page slider, ◀ ▶ buttons, night mode,
  tap to hide the bars, and it remembers the page ("Davom etish · 34-bet").
- **O‘qidim** button and a counter ("O‘qidi: 124").

### 3.3e Adminga yozish (contact the admin)
- Everyone (students too) has **"Adminga yozish"** on *Bugun* and in *Profil*: topic (Shikoyat / Taklif / Savol), text,
  optional screenshot. Only the admin sees it, in **Admin → Shikoyatlar**, and gets a Telegram alert.
- The admin answers in the app; the answer reaches the person in Telegram via @KengashAppBot.

### 3.3f Long press to edit
- **Channels** (custom only): rename, description, mode, **photo**, delete. Auto channels can't be changed.
- **Books** (admin): fix title/author/description/cover/PDF — readers are kept; or replace with a new month's book.
- **Tasks** (giver) and **meetings** (organizer): edit title, description, time (place) or delete. Moving a meeting notifies guests.

### 3.3g Admin tools
- **E’lon tarqatish**: one message to everyone or filtered by role / tuman / direction, via Telegram.
- **Faollik**: task completion % per tuman (30 days), schools without coordinators, top 5 schools, people inactive 7+ days.
- **Tahrirlash**: fix anyone's name, role, school, class, direction; approves stuck applications.
- **Excel**: users, tasks and reports, quarter rating, book readers (.xlsx, link valid 10 minutes).

### 3.3c Safety
- Students in the school chat send **text and voice only** (no photos, videos, files). Coordinators and the maslahatchi can.
- Every message has a report button; the admin deletes and blocks. Nobody is anonymous.

### 3.4 Profiles and the directory
- **Koordinatorlar / Координаторы** screen: browse by tuman → school, filter by direction, search by name.
- Profile card: photo, name, seat, direction colour chip, **"Telegram'da yozish / Написать в Telegram"** button (`https://t.me/<username>`).
- **Phone number** visible only to people who are `isAbove` this person (and the admin), with a "Qo‘ng‘iroq qilish" button.
- **Empty seats** are shown as "Bo‘sh / Свободно". A school page has 9 seats (maslahatchi + 8) and, for its own staff,
  an *O‘quvchilar* card (list grouped by class). Students open their own school directly.

---

## 4. Channels (the chat)

**There are no private messages.** All talk happens in channels. For private talk, people use the
Telegram button on a profile.

### 4.1 Automatic channels (created and kept in sync by the server)
Members are added and removed automatically when seats change. Mode: everyone talks.
- **{School} jamoasi** — the 8 coordinators of one school.
- **{Tuman} · {Direction}** — the tuman coordinator of that direction plus every school coordinator of that direction in the tuman.
- **{Tuman} jamoasi** — the tuman's 8 coordinators.
- **{Viloyat} · {Direction}** — the viloyat coordinator plus every tuman coordinator of that direction.
- **{Viloyat} jamoasi** — the viloyat's 8 coordinators.
- **Kengash e’lonlari** — everyone; only the admin and viloyat coordinators post.

### 4.2 Channels people create
- Only **tuman and viloyat coordinators** (and the admin) can create channels.
- Before creating, they choose: **"Hamma yozadi / Пишут все"** (group) or **"Faqat men yozaman / Пишу только я"** (announcements). The mode can be changed later.
- Name, photo/emoji icon, short description.
- Add members one by one or **by groups** ("all IT coordinators of Asaka schools", "all school Liders of Asaka"). The creator can only add people they are `isAbove` of, or people at their own level.
- The creator can rename, change the mode, remove members, pin messages and delete the channel. Members can leave created channels (not automatic ones), and can **mute** any channel.

### 4.3 Messages
- Text (up to 4,000 characters, links clickable), **reply**, **edit** (15 min) and **delete** your own.
- **Photos** (resized to 1600 px, EXIF removed), **files** ≤ **20 MB**, **voice** ≤ **5 min**, **video** ≤ **50 MB**. Allowed file types: images, PDF, Office documents, audio, video. Never executables.
- Unread counters, "seen by N" for announcement channels, date separators, jump to the newest message.
- **Real time** (WebSocket), with **push notifications** (Firebase Cloud Messaging, free) that respect mute.
- **Report:** long-press → `Shikoyat qilish / Пожаловаться` → reason (haqorat, nomaqbul kontent, spam, boshqa) → goes to the admin queue.
- **Moderation:** the admin can delete any message, block a user (no sending; or full block), and see the reported message with context. The channel creator can delete messages in their own channel.
- Rate limit: 20 messages per minute per user, 30 uploads per hour.

---

## 5. Tasks (Vazifalar) and photo reports

- **Who gives tasks:** tuman coordinators → school coordinators in their tuman (their direction; Lider → any direction). **Viloyat coordinators → anyone below them** (tuman and school, their direction; viloyat Lider → everyone). Admin → anyone.
- **Task:** title, description, attachments, **deadline** (date + time), audience picker (same group picker as channels), **"Fotohisobot talab qilinadi"** toggle.
- **Assignee:** sees it on **Bugun** and **Vazifalar**, taps **"Bajarildi / Выполнено"**, adds photo(s) (up to 6) and a short comment if required.
- **Statuses:** Yangi → Topshirildi (submitted) → **Qabul qilindi** (accepted) or **Qaytarildi** (returned with a comment, the student can resubmit). Deadline passed and not submitted = **Muddati o‘tdi** (overdue).
- **The giver** sees progress (e.g. 41 / 62 done), a list by school with status chips, and can open each report, accept or return it, and send a reminder to everyone who hasn't done it.
- **Who sees reports:** the giver **and everyone `isAbove` the assignee**.
- Push: new task, 24 h and 2 h before the deadline, returned, accepted.

---

## 6. Events calendar (Taqvim)

- Created by tuman and viloyat coordinators and the admin, for the same audiences as tasks.
- Event: title, date and time (start–end), place (text + optional map link), description, cover photo, optional link to a channel.
- Month view + list view, filter by "Mening tadbirlarim" and direction.
- **RSVP:** `Boraman / Пойду` · `Bora olmayman / Не смогу`. The organiser sees the lists.
- Push reminders 1 day and 1 hour before.

---

## 7. Screens

### 7.1 Tabs (phone floating tab bar, desktop glass sidebar as in the blueprint)
1. **Bugun / Сегодня** — greeting with name and seat; tasks due today and overdue; today's and this week's events; new announcements; unread channels. Sun-yellow "Bugun" accents.
2. **Kanallar / Каналы** — list with unread counts, search, "+" for those allowed.
3. **Vazifalar / Задачи** — "Menga" (to me) and "Men bergan" (given by me) segments.
4. **Taqvim / Календарь**.
5. **Profil / Профиль** — iOS grouped list like the blueprint §3.3.

Desktop sidebar extra section **VOSITALAR / ИНСТРУМЕНТЫ**: Koordinatorlar,
Admin panel (admin only). On phone these are reached from Profil.

### 7.2 Admin panel (admin only, desktop-first, works on phone)
- **Users:** search, filter by tuman/school/direction, open profile, move to another seat, free seat, block, **delete**.
- **Schools and districts:** bulk add, edit, hide.
- **Seats:** see every seat (filled/empty), set a Telegram contact for empty seats.
- **Keys:** all keys, create any, revoke.
- **Reports queue:** reported messages, actions: delete message, warn, block, dismiss.
- **Channels:** see/edit/delete any channel.
- **Subscriptions** (phase 4): give free months to anyone, create promo codes, see who paid.
- **Stats:** users per tuman, filled seats %, active this week, tasks done %.

### 7.3 Every screen
Loading skeleton, empty state, error with retry, offline banner (blueprint §3.4). Enter sends a
message on desktop (Shift+Enter = new line) and confirms dialogs.

---

## 8. Payments (phase 4 — build the rest first)

- **10,000 so‘m per month** for everyone **except the admin**.
- **Promo code:** 3 free months, printed as **QR codes on invitation cards**. Scanning opens the website / app with the code filled in. One use per person.
- The admin can **give free months** to anyone.
- Provider: **Click or Payme** (needs a registered business, YaTT or MChJ, which the owner doesn't have yet).
- **Until payments launch, everything is free.** But from day one every user has a `paid_until` date and the server has a `PAYMENTS_ENABLED` flag (off), so turning it on later is easy.
- When it's on and someone's time runs out: they can still log in, read the **Bugun** screen and pay, but channels, tasks and calendar show a friendly "Obunani yangilang" screen.

---

## 9. Legal pages (blueprint §5 with these changes)

- **About (Biz haqimizda):** what Kengash is (§0 text), goal (`Kengash koordinatorlarining ishini osonlashtirish — barcha muloqot, vazifa va tadbirlar bir joyda.`), the O‘quvchilar Kengashi logo, **team** (same 3 founders and photos), **Yaratuvchi va hamkor: Idrok Corporation**, **Kelajak Markazlari** block with its logo, contact line.
- **Privacy:** what we store, exactly: Telegram id and username, phone number, full name, photo, seat (school, district, direction), messages and files in channels, task reports, event answers, login tokens, consent record. What we **don't**: location, contacts, ads ids, card data (payments go through Click/Payme, we never see card numbers). Who sees what: name, photo, seat and Telegram link are visible to all Kengash users; **phone only to coordinators above you and the admin**; messages only to channel members; reports to the task giver and those above. Services: Render (server), Supabase (database and files), Firebase (push), Telegram (login). Remove the "parental consent" paragraph; write instead: `Ilova Kelajak O‘quvchilar Kengashi koordinatorlari (maktab o‘quvchilari) uchun.`
- **Terms:** add rules for channels (respectful talk, no other people's photos without permission, no spam, the admin may delete content and block accounts), tasks (reports must be real), and the subscription (once enabled).
- **Delete account:** no password (Telegram login), so confirm by typing **`O‘CHIRISH` / `УДАЛИТЬ`**. Deletes the profile, photo, phone, tokens, consents, the user's messages and files, and their reports. Their seat becomes free. Tasks/channels they created are handed to the admin.
- **Sign-up:** the one tick from §3.2.
- **Note for the owner (flag before launch):** Uzbekistan's personal-data law may require storing citizens' data on servers in Uzbekistan.

---

## 10. Technology

- **App:** Flutter (Android, iPhone, website from one code). Same structure as Idrok Academy.
- **Server:** Python (FastAPI) on **Render Starter (~$7/month, never sleeps)**, WebSockets for live chat. Health check `/api/ping`.
- **Database:** **Supabase Postgres** (a real database, because chat needs it). Only the server talks to it (`service_role` key on the server only).
- **Files:** Supabase Storage, **private** bucket, short-lived signed links. Free tier is 1 GB. When files grow past that, Supabase Pro is ~**$25/month** (warn the owner before).
- **Push:** Firebase Cloud Messaging (free).
- **Telegram bot:** created by the owner in @BotFather; the token goes into Render's environment.
- **Publishing:** GitHub Actions → APK + website on GitHub Pages (`https://a16067647-cmd.github.io/kengash/`), as in blueprint §8.
- **iPhone note:** putting the app in the App Store needs an **Apple Developer account ($99/year)**. Until then iPhone users use the website (it can be added to the home screen). Google Play needs a one-time $25 account.

All security rules from blueprint §6 apply. Plus: `isAbove` checks on every server route; members-only
access to channel messages and files; EXIF stripping; file-type allowlist; Telegram webhook secret;
key attempt limits; message rate limits; a **second-account test** proving a school coordinator can't
read another school's channel, reports or phone numbers.

---

## 11. Build order (each phase = working app published)

1. **Foundation:** design system (violet), splash, Telegram login, keys, profiles, directory, admin: schools/users/seats/keys, legal pages, APK + website.
2. **Channels:** automatic + created channels, real-time messages, media, report and moderation, push.
3. **Tasks and calendar:** tasks with photo reports, events with RSVP, the **Bugun** screen.
4. **Payments:** Click/Payme, promo codes with QR, free months (when the business is registered).

---

## 12. What the owner must do (Claude can't)

- [ ] Install the **Claude GitHub App** on the `kengash` repo so Claude can push.
- [ ] Create the **Telegram bot** in @BotFather (Claude gives exact steps) and paste the token into Render.
- [ ] Create **Render** and **Supabase** projects (or let Claude use the connected accounts) and add a payment card to Render for the $7 plan.
- [ ] **Firebase** project for push (Claude gives steps).
- [ ] Later: Apple Developer, Google Play, a YaTT/MChJ for Click/Payme.
- [ ] A bigger Kelajak Markazlari logo file (SVG or ≥ 1024 px) before store release.

---

## 13. Definition of done

Blueprint §9 plus:
- [ ] Telegram login works on Android, iPhone (website) and desktop.
- [ ] Keys: creation limited by `isAbove`, one-time, 7-day expiry, seat bound; sign-up without a key shows who to contact.
- [ ] Phone numbers hidden from everyone who is not above (tested).
- [ ] Automatic channels follow seat changes; created channels with both modes; media limits enforced; report → admin queue → delete/block works.
- [ ] Tasks: audiences, deadlines, photo reports, accept/return, overdue, reminders; reports visible only to giver and those above.
- [ ] Calendar with RSVP and reminders.
- [ ] Admin panel: bulk add schools, manage users/seats/keys/reports.
- [ ] `PAYMENTS_ENABLED=false` and `paid_until` in place.
