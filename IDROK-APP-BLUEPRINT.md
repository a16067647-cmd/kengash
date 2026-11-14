# IDROK App Blueprint — build a new app that looks and works like Idrok Academy

> **For Claude:** this file is a complete specification taken from a finished, published app, **Idrok Academy**. The owner will tell you, **after** you read this file, what the *new* app is about. Your job: build that new app so that it **looks, feels and is protected exactly like Idrok Academy**: same design system, screens structure, About page, legal pages, security and publishing pipeline. Only the **name, purpose and features** change.
>
> Read the whole file first. Then look at the screenshots in `reference/`. Then ask the owner the questions in **§0.3** (only the ones this file does not already answer). Then build.

---

## 0. How to use this blueprint

### 0.1 What is in the package
| Folder | What it is |
|---|---|
| `IDROK-APP-BLUEPRINT.md` | This specification (the "prompt"). |
| `assets/team/` | Founder photos: `bexruz.jpg`, `vazzohbek.jpg`, `abdurahmon.jpg` (480×480 JPEG). For the About page. |
| `assets/fonts/` | Fonts used by Idrok: **Manrope** (400/600/700/800), **JetBrains Mono** (400/700), **Unbounded** (800). All free under the SIL Open Font License (licence files included; keep them in the repo). |
| `reference/phone/` | Phone screenshots of Idrok Academy (light + dark). |
| `reference/desktop/` | Desktop/website screenshots: collapsible glass sidebar, profile card, dark mode, login with the live background. |
| `reference/about/` | The About page (desktop + phone). |

**Link version (no ZIP attached?)** — download the files yourself:
```bash
mkdir -p assets/team assets/fonts
for f in bexruz vazzohbek abdurahmon; do curl -fsSL -o assets/team/$f.jpg https://a16067647-cmd.github.io/idrok/team/$f.jpg; done
```
Fonts are free on Google Fonts: **Manrope** (400, 600, 700, 800), **JetBrains Mono** (400, 700), **Unbounded** (800) — add them as local font files, not a runtime CDN link. To see the look, open the live Idrok Academy: https://a16067647-cmd.github.io/idrok/ (login screen, live background, glass) and its About page https://a16067647-cmd.github.io/idrok/about.html . The reference screenshots and team photos are on this page and published next to it as `img/*.jpg` (team photos: `img/team-bexruz.jpg`, `img/team-vazzohbek.jpg`, `img/team-abdurahmon.jpg`).

Screenshots show Academy's **learning** content (lessons, XP). That content is **not** part of the new app. Copy the **look** (colours, spacing, cards, glass, navigation, typography), not the learning features.

### 0.2 What stays the same and what changes
**Stays the same (do not ask, just do it):**
- Brand look: Idrok **blue** palette, fonts, glass/iOS style, light + dark themes (§2).
- Team, roles, contacts on the About page (§5.1).
- Two languages for every visible text: **Uzbek (Latin)** and **Russian** (§4).
- Legal set: About, Privacy, Terms, Delete account, Cookies & storage, sign-up consent ticks (§5).
- Security rules (§6), working rules and publishing pipeline (§7, §8).

**Changes (the owner will tell you in the chat):** app name, one-line description, purpose, features, audience (children or adults), which data the app collects, which screens it needs.

**Not included on purpose:** Academy's game system (XP, leagues, streaks, daily quests, shop, certificates). Do not add gamification unless the owner asks for it.

**Technology is your decision.** Idrok Academy uses **Flutter** (one codebase for Android, iPhone and website) + a small **Python** server on **Render** + **GitHub Actions** + **GitHub Pages**. Choose what fits the new app after you hear it. If it needs Android + iPhone + website, the Academy stack is proven and recommended. If it is web-only, a web framework is fine. Whatever you choose, reproduce the design tokens exactly (§2 gives hex values, sizes and timings; §2.12 gives a CSS-variables version).

### 0.3 Questions to ask the owner (only those not answered in the chat)
1. App **name** (Latin) and a **one-sentence description** in Uzbek and Russian.
2. **Who uses it**: children/school students (needs parent consent and stricter privacy) or adults only?
3. **Main features / screens** (list).
4. **Accounts**: does it need login? Roles (user/admin/teacher…)? 
5. **Data**: what personal data is stored (name, photo, phone, school, location…)? Any payments? (If payments: stop and agree on a provider first.)
6. Platforms: Android, iPhone, website? Does a website link need to work in Uzbekistan without VPN? (GitHub Pages does.)
7. Any partner/supporter logo to show on the About page? (Academy shows Kelajak Markazlari; **do not copy it** unless the owner confirms the partner supports the new app too.)
8. Server/AI: any AI features (which provider; keys stay on the server)?

Ask them in **one** message, short and numbered. Use defaults from this file for anything else.

---

## 1. Product principles (the "Idrok feel")
1. **Premium, calm, iOS-like.** Clean surfaces, soft shadows, glass where it helps, rounded corners everywhere, big clear titles. No visual noise.
2. **Not "AI-made" looking.** **No violet/purple/indigo UI colours, no purple gradients**, no sparkle emoji everywhere, no neon. Blues + neutrals + one warm accent (amber) only for rewards/highlights.
3. **Bilingual by default.** Uzbek (Latin) is the default language, Russian is one tap away everywhere (login screen, settings, legal pages).
4. **Phone first, desktop first-class.** Phone: floating bottom tab bar. Desktop (≥ 1000 px): collapsible glass sidebar. Same app, two intentional layouts (§3).
5. **Fast and forgiving.** Instant feedback on tap (press-scale), skeletons while loading, friendly errors, works on cheap Android phones.
6. **Honest and safe.** Clear legal pages, delete-account in the app, minimum data, no ads, no trackers.

---

## 2. Design system (exact values)

### 2.1 Colours — light theme
| Token | Hex | Use |
|---|---|---|
| `bg` | `#F2F5FA` | Page background |
| `surface` | `#FFFFFF` | Cards |
| `surfaceAlt` | `#EAEFF6` | Inset areas, segmented control track, skeletons |
| `elevated` | `#FFFFFF` | Sheets, menus |
| `glass` | `#FFFFFF` @ 78 % (`#C7FFFFFF`) | Glass panels (with blur) |
| `glassEdge` | `#FFFFFF` @ 90 % | 1 px border of glass |
| `hairline` | `#0A1226` @ 8 % | Thin borders, dividers |
| `hairlineStrong` | `#0A1226` @ 14 % | Input borders, list dividers |
| `text` | `#0A1226` | Main text (logo navy) |
| `text2` | `#586178` | Secondary text |
| `text3` | `#9AA3B5` | Hints, captions, chevrons |
| `accent` | `#0A6CFF` | Primary blue (buttons, links, selection) |
| `accentHi` | `#3FA9FF` | Light end of blue gradients |
| `accentText` | `#0058E6` | Blue text on light backgrounds |
| `accentSoft` | `#E8F1FF` | Selected tab pill, soft badges |
| `success` | `#0795D9` (hi `#4FCBFF`, text `#03628F`, soft `#E1F5FF`) | "Done/correct" states. Success is **sky-blue**, not green |
| `danger` | `#D93A44` (soft `#FFE9EA`) | Errors, destructive actions |
| `shadow` | `#0A1226` @ 10 % | Shadow colour |
| `scrim` | `#0A1226` @ 40 % | Behind sheets/dialogs |
| `codeBg / codeBar / codeFg / codeMuted` | `#0B1220 / #131C2E / #E8F0FF / #7D8AA3` | Code or monospace blocks, if any |

### 2.2 Colours — dark theme (designed separately, not inverted)
| Token | Hex |
|---|---|
| `bg` | `#05070D` |
| `surface` | `#0F131C` |
| `surfaceAlt` | `#161B26` |
| `elevated` | `#1C2230` |
| `glass` | `#0F131C` @ 65 % |
| `glassEdge` | `#FFFFFF` @ 14 % |
| `hairline` / `hairlineStrong` | `#FFFFFF` @ 8 % / 15 % |
| `text` / `text2` / `text3` | `#F2F5FA` / `#9AA4B8` / `#5E6779` |
| `accent` / `accentHi` / `accentText` / `accentSoft` | `#2F80FF` / `#5CC2FF` / `#7DB5FF` / `#2F80FF` @ 18 % |
| `success` (hi, text, soft) | `#0E93D6` (`#5CD6FF`, `#7FD8FF`, `#38C8FF` @ 15 %) |
| `danger` / `dangerSoft` | `#FF7A80` / `#FF4D57` @ 16 % |
| `shadow` / `scrim` | `#000000` @ 50 % / 60 % |

Dark cards get a **1 px top highlight** (horizontal gradient transparent → white 14 % → transparent) along the top edge.

### 2.3 Brand constants and gradients
- `navy #0A1226`, `blue #0A6CFF`, `sky #38C8FF`, `white #FFFFFF`.
- **Accent gradient** (primary buttons, selected profile card): top-left `accentHi` → bottom-right `accent`.
- **Hero gradient** (big top card): light `#2EA6FF → #0058F0`, dark `#2FA8FF → #0047D6`.
- **Gloss** (iOS shine on hero cards, selected items): vertical gradient white 22 % → white 4 % at 50 % → transparent at 51 %. **Always give the gloss layer the same corner radius as its card**, otherwise square corners show.
- **Warm accent**: amber `#FFB300` / `#FFC21A` for stars, badges and highlights only. Never as a background colour.
- Small icon tiles in settings lists use iOS system colours: green `#34C759`, red `#FF3B30`, grey `#8E8E93`, blue `#0A6CFF`, ocean `#0A84D6`. **Never** iOS indigo/purple (`#5856D6`, `#AF52DE`).

### 2.4 Typography
Body font **Manrope**. Monospace **JetBrains Mono**. **Unbounded 800** only for the brand wordmark if needed.
| Style | Size / line-height | Weight | Letter-spacing |
|---|---|---|---|
| largeTitle | 32 / 1.18 | 800 | −0.9 |
| title1 | 26 / 1.2 | 800 | −0.6 |
| title2 | 21 / 1.25 | 800 | −0.4 |
| title3 | 18 / 1.3 | 800 | −0.3 |
| headline | 16 / 1.35 | 700 | −0.2 |
| body | 16 / 1.55 | 400 | −0.1 |
| bodyStrong | 16 / 1.45 | 600 | −0.1 |
| callout | 15 / 1.4 | 600 | −0.1 |
| subhead | 14 / 1.4 | 600 | 0 |
| footnote | 13 / 1.35 | 600 | 0 |
| caption | 12 / 1.3 | 700 | +0.1 |
| overline (UPPERCASE section labels) | 11 / 1.2 | 800 | +1.1 |
| button | 16 / 1.2 | 800 | −0.1 |
| number (stats) | 22 / 1.1 | 800 | −0.5 |
| mono | 14 / 1.55 | 400 | 0 |

Never hard-code a font size in a screen: always use these styles.

### 2.5 Spacing, radii, layout
- **4 px grid**: 4, 8, 12, 16, 20, 24, 28, 32, 40, 48.
- Page side padding **20 px**. Space under content for the floating tab bar: **112 px**.
- **Radii**: xs 8 · sm 12 · md 16 · lg 20 · xl 24 · xxl 28 · pill 999. Cards = 24, list groups = 20, buttons 18 (small 14), inputs 14, sheets top 30, chips/pills = 999.
- Content max width: **640 px** for app pages on phone/tablet, **720 px** for reading pages (legal, about). Desktop content area is centred next to the sidebar.
- **Breakpoint**: `width ≥ 1000 px` = desktop layout.

### 2.6 Shadows
- **Card** (light): `0 12px 30px -8px navy@8%` + `0 1px 2px black@4%`. Dark: `0 14px 30px -10px black@40%`.
- **Soft** (icon buttons, pills): light `0 6px 16px -6px navy@9%`; dark `0 6px 16px -6px black@30%`.
- **Glow** (primary button, selected items): `0 10px 26px -8px <colour>@36%` (dark 50 %) + `0 2px 8px -2px <colour>@18%`. Reduce glow by half while pressed.
- White text on coloured buttons gets a tiny text shadow: `0 1px 4px black@30%`.

### 2.7 Glass (glassmorphism)
- Background blur **σ = 20–30** (cards 24, tab bar 28, sidebar 30), fill = `glass` token, 1 px border `glassEdge`, card shadow.
- A 30 px tall **top shine** inside: vertical gradient white 50 % (dark: white 7 %) → transparent.
- Use glass for: desktop sidebar, phone floating tab bar, settings groups on desktop, course/item cards over the live background. Do **not** blur huge areas or nest blurs (performance).
- Cheaper "glass card" variant without blur (for long lists): surface + pastel tint of the item colour (15 % light / 19 % dark) + two soft radial colour blobs behind + white 60 %→28 % overlay + white 1.2 px border.

### 2.8 Components (build these once, reuse everywhere)
| Component | Spec |
|---|---|
| **Button** | Height 54 (56 for main actions), radius 18 (14 for buttons under 50 px), label `button` style, optional leading icon 18–20 px. Kinds: **primary** (accent gradient + glow), **success** (success gradient), **dark** (`#1B2740 → #0A1226`, white 12 % border), **secondary** (surface + `hairlineStrong` border + soft shadow), **ghost** (transparent, accentText), **danger** (dangerSoft fill, danger text, danger 22 % border). States: pressed (scale 0.97, darker overlay), disabled (40 % opacity), loading (spinner replaces label), keyboard focus ring (accent 40 %, 3 px spread). Top 40 % white sheen on gradient buttons. |
| **Icon button** | 44×44 circle/rounded square, surface + soft shadow, icon 22 px `text2`, tooltip on desktop. |
| **Card** | Kinds: **solid** (surface, hairline border, card shadow), **inset** (surfaceAlt, no shadow), **tinted** (accentSoft fill, accent 19 % border), **glass** (§2.7). Padding 20, radius 24. Tappable cards press-scale 0.98. |
| **Pill / chip** | Height 28 (small 24), radius 999, caption/footnote text, optional 14 px icon. Tones: neutral, accent, success, danger, onColor (white 20 % on coloured backgrounds). |
| **Grouped list** (iOS settings) | Rounded group (radius 20) of rows; row = 30×30 coloured icon tile (radius 8, white 18 px icon) + title (body) + optional value (callout, text2) + chevron (text3). Dividers 0.5 px `hairlineStrong`, indented 58 px. On desktop the group is glass. |
| **Large title header** | Page title in `largeTitle` + optional subtitle in `subhead text2`, top-left, 16 px below the top bar. |
| **Segmented control** | Height 42, track surfaceAlt radius 13, selected segment = surface radius 10 with soft shadow, animated slide 280 ms. Used for Login/Register, filters. |
| **Text field** | ≈52 px tall (vertical padding 15), radius 14, surface fill, `hairlineStrong` 1 px border → accent 1.6 px on focus, leading 20 px icon (text3), label above in `footnote text2`, error text below in danger. Password field has an eye toggle. |
| **Progress bar** | Height 6–8, radius 999, track `surfaceAlt`, fill accent (or item colour), animated. |
| **Avatar** | Circle, photo `cover`; fallback = accent gradient + first letter (white, headline). Optional ring 2 px. |
| **Toast** | Slides down from top (360 ms), glass pill (blur 26), icon + one line, auto-hide after 2.6 s. |
| **Bottom sheet** | Glass, radius 30 at the top, drag handle 38×5 (`hairlineStrong`), scrim behind. |
| **Skeleton** | surfaceAlt blocks with a soft shimmer (1.4 s loop). |
| **Empty state** | 64 px icon tile, title3, one line of text2, optional button. |
| **Tooltip** | navy (dark: elevated) bubble, radius 12, white footnote. |

### 2.9 Icons and images
- **Material Symbols Rounded** (or Flutter `Icons.*_rounded`) everywhere: one consistent rounded family.
- **Pixel-art icons** (optional, signature Idrok detail) for the main items/categories: 16×16 grids drawn in code with a fixed palette (navy outline `#0A1226`, white, ice `#DCE8FA`, sky `#38C8FF`, blue `#0A6CFF`, deep blue `#0047D6`, teal `#00A89D`, light teal `#7FE3D8`, amber `#FFC94A`, orange `#FF9F0A`, coral `#FF5A6E`, green `#34C759`). Draw without anti-aliasing so edges stay crisp; keep them still (no floating). In dark mode the outline becomes `#2B3A63`.
- **App icon**: rounded square, blue gradient (`#7FE3FF` top-left → `#0A6CFF` → `#0047D6`), navy glyph. Make a new glyph for the new app; keep the same style.

### 2.10 Motion
- Durations: press 110 ms · fast 180 ms · base 280 ms · slow 420 ms · page 380 ms.
- Main curve: `cubic-bezier(0.22, 1, 0.36, 1)` (iOS-like ease-out). In/out: ease-in-out cubic. "Pop": ease-out-back.
- **Press**: everything tappable scales to 0.97 (cards 0.98) with a light haptic tick on phones.
- **Appear**: content blocks fade in and rise 14 px over 520 ms, each next block 80 ms later (max +400 ms).
- Page transitions: iOS-style horizontal slide on Android and iOS.
- **Respect "reduce motion"** (OS setting / `prefers-reduced-motion`): all durations become 0 and loops stop.

### 2.11 Live background — "IDROK Motion Lab" (signature detail)
A calm network of small dots and thin lines behind selected screens.
- **Look**: dots radius 1–2.4 px in 3 depth layers (sizes ×0.75 / 1 / 1.3, opacity ×0.45 / 0.7 / 1); ~10 % "accent" dots slightly bigger with a faint halo (3.2× radius, 28 % opacity). Thin 1 px lines between dots closer than **118 px**, max **3 lines per dot**, line opacity ≤ 0.30 fading with distance. Light theme: dots `accent`, accent dots `accentHi`, lines `accent`, dot opacity 0.42. Dark theme: dots ice-blue (accentHi mixed 55 % with white), accent dots `sky`, lines `accentHi`, dot opacity 0.6.
- **Motion**: slow drift 9 px/s with gentle organic sway (±14 px); mouse/finger **softly pushes** dots within 150 px (spring returns them when the pointer leaves); scrolling makes the network drift a little (max 90 px/s); never fast, never flashy.
- **Budget**: ≤ 44 dots on phones, ≤ 90 on desktop (by screen area); auto-lower quality if frames are slow; pause when the screen is hidden; one static frame with reduced motion.
- **Where**: main screens and login. **Off** during focused tasks (forms, tests, checkout), admin tables, legal pages.
- **Switches**: global config flag + user setting "Jonli fon / Живой фон" (on by default).
- It is a decoration layer: never captures taps, never covers content, no per-frame UI rebuilds (draw on a canvas).

### 2.12 CSS variables (if the new app is a website)
```css
:root{
  --bg:#F2F5FA; --surface:#FFFFFF; --surface-alt:#EAEFF6; --glass:rgba(255,255,255,.78); --glass-edge:rgba(255,255,255,.9);
  --hairline:rgba(10,18,38,.08); --hairline-strong:rgba(10,18,38,.14);
  --text:#0A1226; --text2:#586178; --text3:#9AA3B5;
  --accent:#0A6CFF; --accent-hi:#3FA9FF; --accent-text:#0058E6; --accent-soft:#E8F1FF;
  --success:#0795D9; --success-soft:#E1F5FF; --danger:#D93A44; --danger-soft:#FFE9EA; --amber:#FFB300;
  --r-xs:8px; --r-sm:12px; --r-md:16px; --r-lg:20px; --r-xl:24px; --r-xxl:28px;
  --shadow-card:0 12px 30px -8px rgba(10,18,38,.08),0 1px 2px rgba(0,0,0,.04);
  --ease:cubic-bezier(.22,1,.36,1);
  --font:'Manrope',system-ui,sans-serif; --mono:'JetBrains Mono',monospace;
}
@media (prefers-color-scheme:dark){:root{
  --bg:#05070D; --surface:#0F131C; --surface-alt:#161B26; --glass:rgba(15,19,28,.65); --glass-edge:rgba(255,255,255,.14);
  --hairline:rgba(255,255,255,.08); --hairline-strong:rgba(255,255,255,.15);
  --text:#F2F5FA; --text2:#9AA4B8; --text3:#5E6779;
  --accent:#2F80FF; --accent-hi:#5CC2FF; --accent-text:#7DB5FF; --accent-soft:rgba(47,128,255,.18);
  --success:#0E93D6; --danger:#FF7A80; --shadow-card:0 14px 30px -10px rgba(0,0,0,.4);
}}
```
The user's own theme choice (System / Light / Dark) must override the system setting.

---

## 3. App structure and screens

### 3.1 Start flow
1. **Splash**: app icon 96 px, app name (title1), small spinner. If loading takes > 5 s show `Server uyg‘onmoqda… bu 1 daqiqagacha cho‘zilishi mumkin.` / `Сервер просыпается… это может занять до минуты.` (free servers sleep; §6.10).
2. **Intro video** (optional, first launch only, max ~9 s, skippable, then smooth fade into the app). On desktop show the video with soft faded edges, **not** inside a phone frame.
3. **Auth** (if the app has accounts): language chip (UZ/RU) + theme button top-right; app icon, name, one-line subtitle; a rotating "tip" pill; glass card with **segmented control Kirish / Ro‘yxatdan o‘tish** (Login / Register); fields with icons; primary button; small links at the bottom: **Biz haqimizda · Maxfiylik siyosati · Foydalanish shartlari**.
4. **Register** extra: profile fields the app needs + **two consent ticks** (§5.6) that must be checked before the button activates.

### 3.2 Main shell
- **Phone (< 1000 px)**: content column max 640 px; **floating glass tab bar** at the bottom: 14 px from the sides, height 58, radius 28, blur 28, white 85 % (dark `#141416` @ 76 %); 3–5 tabs; the selected tab sits on an `accentSoft` pill (radius 22) with `accentText` icon + label; icons 23 px, labels caption.
- **Desktop (≥ 1000 px)**: **left glass sidebar**, 256 px open / 84 px collapsed, radius 28, blur 30, animated 260 ms, collapse with one tap (`«` button next to the logo). Sections: main tabs; **VOSITALAR / ИНСТРУМЕНТЫ** (tools); **SOZLAMALAR / НАСТРОЙКИ** (settings: Language with a "UZ/RU" chip, Appearance with "Yorug‘ / Qorong‘i / Tizim" chip). At the bottom a **profile card**: 40 px avatar + name + one-line status + chevron; selected state = accent gradient with glow. Every gloss/shine layer inside uses the same radius as its container.
- Top-right of pages: small status chips if needed. Large title at top-left.
- Horizontal chip rows must scroll with the **mouse wheel and mouse drag** on desktop (Flutter web ignores both by default).
- Keyboard: **Enter** confirms the main action of a screen/dialog (not inside multi-line text fields); Esc closes sheets.

### 3.3 Profile / Settings screen (iOS grouped style)
- Avatar 110 px with ring + edit badge, name (title2), one line of details, link "Profilni tahrirlash / Изменить профиль".
- Group 1, **Settings**: Appearance (System/Light/Dark), Language (O‘zbekcha / Русский), Live background (Yoniq / O‘chiq), notifications if any.
- Group 2, **Info**: Biz haqimizda (green `info` icon), Maxfiylik siyosati (blue shield), Foydalanish shartlari (grey document), Cookie va saqlash (grey cookie icon).
- Group 3, **Account**: Chiqish / Выйти (log out), **Hisobni o‘chirish / Удалить аккаунт** (red, asks for the password; §5.5).

### 3.4 States every screen needs
Loading (skeleton), empty state, error with retry, offline message, success toast. Long lists paginate or lazy-load.

---

## 4. Languages (Uzbek + Russian)
- Two dictionaries with **identical keys** (`uz`, `ru`); a test must fail if a key is missing in one language. Default `uz`, user can switch any time; the choice is saved.
- Uzbek Latin uses the **‘ (U+2018)** sign: `o‘`, `g‘`, and **’ (U+2019)** for the tutuq belgisi: `sun’iy`, `ma’lumot`. Never a plain `'`.
- Content that comes from data uses a pair type `Tr(uz, ru)`.
- Useful ready keys: `on: Yoniq / Вкл.`, `off: O‘chiq / Выкл.`, `back: Orqaga / Назад`, `save: Saqlash / Сохранить`, `cancel: Bekor qilish / Отмена`, `retry: Qayta urinish / Повторить`, `copied: Nusxa olindi / Скопировано`, `language: Til / Язык`, `theme: Mavzu / Тема`, `light: Yorug‘ / Светлая`, `dark: Qorong‘i / Тёмная`, `system: Tizim / Системная`, `bg_motion: Jonli fon / Живой фон`, `waking` (see §3.1), `err_conn: Serverga ulanib bo‘lmadi. Server uyg‘onayotgan bo‘lishi mumkin — 1 daqiqadan so‘ng qayta urinib ko‘ring. / Не удалось подключиться к серверу. Возможно, он ещё просыпается — попробуйте снова через минуту.`

---

## 5. About, legal pages and consent (texts included)

All pages exist **inside the app** (readable offline) **and** as **public web pages** (`/about`, `/privacy`, `/terms`, `/cookies`, `/delete-account`, each also in Russian `?lang=ru` or `-ru.html`), because app stores require public URLs. Layout of every page: top bar (app name left, `Русский` / `O‘zbekcha` switch right) → white card (radius 20, padding 28/24, max width 720, soft shadow) with **h1** title (28 px), grey "Updated: date" line, sections with **h2** (18 px) + paragraphs (16/1.6) → small links to the other legal pages under the card. In the app: same content on a `surface` card under a large title, with a link at the bottom that copies the public URL.

Replace `{APP}` with the new app name, `{DESC_UZ}` / `{DESC_RU}` with its description, `{DATE_UZ}` / `{DATE_RU}` with the publishing date (e.g. `14-noyabr, 2026` / `14 ноября 2026`). Sentences in **[brackets]** are conditional: keep them only if they apply.

**Contact line (both languages, clickable):** `Telegram: @behruz_sk (https://t.me/behruz_sk), email: behryzmamajon@gmail.com`

### 5.1 About us — `Biz haqimizda` / `О нас`
Sections in this order:
1. **{APP} nima** / **Что такое {APP}**: `{DESC_UZ}` / `{DESC_RU}` (2–3 sentences, written from the owner's explanation).
2. **Maqsadimiz** / **Наша цель**: one sentence about the goal.
3. **Jamoa** / **Команда**: photo grid, no paragraph. 3 columns on desktop, 2 on phone; square photos (`cover`), radius 18; bold name; grey role under it:

| Photo | Name | Role (uz) | Role (ru) |
|---|---|---|---|
| `assets/team/bexruz.jpg` | Mamajonov Bexruz | Asoschi | Основатель |
| `assets/team/vazzohbek.jpg` | Satvaldiyev Vazzohbek | Hammuassis | Сооснователь |
| `assets/team/abdurahmon.jpg` | Rahimjonov Abdurahmon | Hammuassis | Сооснователь |

4. *(Only if the owner names a partner)* **Qo‘llab-quvvatlovchi** / **При поддержке**: one sentence + partner logo 180 px, radius 18. Keep it behind one on/off constant.
5. **Aloqa** / **Контакты**: contact line.

Reference: `reference/about/`. (The Academy screenshot shows a Kelajak Markazlari block: leave it out unless confirmed for the new app.)

### 5.2 Privacy policy — `Maxfiylik siyosati` / `Политика конфиденциальности`
**Uzbek**
- **Kim biz**: {APP} — {short description} (mobil ilova va veb-sayt). Ushbu siyosat qanday ma’lumot yig‘ilishi, nima uchun ishlatilishi va uni qanday o‘chirish mumkinligini tushuntiradi. Savollar uchun: {CONTACT}.
- **Qanday ma’lumot yig‘amiz**: Hisob: login, ism, parol (faqat shifrlangan xesh ko‘rinishida saqlanadi — parolingizni hech kim ko‘ra olmaydi). [Profil surati…] [other data the app really stores, one line each]. Biz telefon raqami, joylashuv (GPS), kontaktlar, reklama identifikatori yoki to‘lov kartasi ma’lumotlarini yig‘maymiz. Ilovada reklama va kuzatuv (tracking) xizmatlari yo‘q. *(Edit this list to match the new app exactly; never claim you don't collect something you do.)*
- **Nima uchun ishlatamiz**: Hisobingizga kirish va ilova ishlashi uchun [list]. Ma’lumotlaringizni sotmaymiz va reklama uchun bermaymiz.
- **Kimlar ko‘radi**: [who sees what inside the app]. Texnik xizmatlar: [server provider, backup provider] (serverlar O‘zbekistondan tashqarida bo‘lishi mumkin). [If AI: qaysi matn qaysi AI xizmatiga yuboriladi; shaxsiy ma’lumotlar AI ga yuborilmaydi.]
- **[Bolalar]**: Ilova maktab o‘quvchilari uchun. 18 yoshga to‘lmagan foydalanuvchi ota-onasi yoki vasiysining roziligi bilan ro‘yxatdan o‘tadi — bu ro‘yxatdan o‘tishda tasdiqlanadi. Ota-ona istalgan vaqtda farzandining ma’lumotlarini ko‘rishni yoki o‘chirishni so‘rashi mumkin. *(Adults-only app: replace with "Ilova 18 yoshdan katta foydalanuvchilar uchun.")*
- **Qancha saqlaymiz**: Hisob mavjud bo‘lguncha. Hisobni o‘chirsangiz, ma’lumotlar darhol bazadan o‘chiriladi; zaxira nusxalardan esa qisqa vaqt ichida yo‘qoladi.
- **Sizning huquqlaringiz**: Ma’lumotlaringizni ko‘rish, tuzatish (profilda) va to‘liq o‘chirish (Profil → «Hisobni o‘chirish»). Boshqa so‘rovlar uchun: {CONTACT}.
- **Xavfsizlik**: Ulanish HTTPS orqali shifrlanadi, parollar xesh ko‘rinishida saqlanadi. Hech qanday tizim 100% xavfsiz emas, lekin biz ma’lumotlaringizni himoya qilish uchun oqilona choralar ko‘ramiz.
- **O‘zgarishlar**: Siyosat o‘zgarsa, yangi sanani shu sahifada e’lon qilamiz.

**Russian**
- **Кто мы**: {APP} — {краткое описание} (мобильное приложение и сайт). Эта политика объясняет, какие данные собираются, зачем они нужны и как их удалить. Вопросы: {CONTACT}.
- **Какие данные мы собираем**: Аккаунт: логин, имя, пароль (хранится только в виде зашифрованного хеша — никто не видит ваш пароль). [Остальные реальные данные, по одной строке.] Мы не собираем номер телефона, геолокацию (GPS), контакты, рекламный идентификатор или данные банковских карт. В приложении нет рекламы и сервисов слежения (трекинга).
- **Зачем мы их используем**: Чтобы вы могли войти в аккаунт и пользоваться приложением [список]. Мы не продаём ваши данные и не передаём их для рекламы.
- **Кто видит данные**: [кто что видит]. Технические сервисы: [сервер, резервная копия] (серверы могут находиться за пределами Узбекистана). [AI: что отправляется; личные данные в AI не отправляются.]
- **[Дети]**: Приложение предназначено для школьников. Пользователь младше 18 лет регистрируется с согласия родителя или опекуна — это подтверждается при регистрации. Родитель в любой момент может запросить просмотр или удаление данных ребёнка. *(Для взрослых: «Приложение предназначено для пользователей старше 18 лет.»)*
- **Сколько храним**: Пока существует аккаунт. Если вы удалите аккаунт, данные сразу удаляются из базы, а из резервных копий — в течение короткого времени.
- **Ваши права**: Просматривать данные, исправлять их (в профиле) и полностью удалить (Профиль → «Удалить аккаунт»). Другие запросы: {CONTACT}.
- **Безопасность**: Соединение шифруется через HTTPS, пароли хранятся в виде хеша. Ни одна система не защищена на 100%, но мы принимаем разумные меры для защиты ваших данных.
- **Изменения**: Если политика изменится, мы опубликуем новую дату на этой странице.

### 5.3 Terms of use — `Foydalanish shartlari` / `Условия использования`
**Uzbek**
- **Umumiy**: {APP} dan foydalanish orqali siz ushbu shartlarga va Maxfiylik siyosatiga rozilik bildirasiz. [18 yoshga to‘lmagan bo‘lsangiz, ota-onangiz yoki vasiyingiz ham rozi bo‘lishi kerak.]
- **Hisob**: Haqiqiy ismingizni kiriting va parolingizni hech kimga bermang. Hisobingizdagi harakatlar uchun o‘zingiz javobgarsiz. Boshqa odam nomidan hisob ochish taqiqlanadi.
- **Taqiqlanadi**: Haqoratli, odobsiz yoki boshqalarga zarar yetkazuvchi kontent joylash; boshqalarning suratini ruxsatsiz yuklash; boshqa birovning mualliflik huquqi bilan himoyalangan materialini ruxsatsiz yuklash; tizimni buzishga yoki natijalarni soxtalashtirishga urinish; zararli kod ishga tushirish.
- **[App-specific section]**: rules for the app's own features (e.g. content authors are responsible for what they upload; AI answers may be wrong).
- **Xizmat**: Ilova «boricha» taqdim etiladi. Biz uni doimiy ishlashini ta’minlashga harakat qilamiz, lekin uzilishlar bo‘lishi mumkin. Qoidalarni buzgan hisoblarni cheklash yoki o‘chirish huquqini saqlab qolamiz.
- **Hisobni o‘chirish**: Hisobingizni istalgan vaqtda Profil → «Hisobni o‘chirish» orqali o‘chirishingiz mumkin.
- **Aloqa**: {CONTACT}. Shartlar o‘zgarsa, yangi sanani shu sahifada e’lon qilamiz.

**Russian**
- **Общее**: Пользуясь {APP}, вы соглашаетесь с этими условиями и Политикой конфиденциальности. [Если вам нет 18 лет, согласие должен дать и ваш родитель или опекун.]
- **Аккаунт**: Указывайте настоящее имя и никому не сообщайте пароль. Вы отвечаете за действия в своём аккаунте. Запрещено создавать аккаунт от имени другого человека.
- **Запрещено**: Размещать оскорбительный, непристойный или вредный для других контент; загружать чужие фото без разрешения; загружать без разрешения материалы, защищённые чужим авторским правом; пытаться взломать систему или подделать результаты; запускать вредоносный код.
- **[Раздел о функциях приложения]**.
- **Сервис**: Приложение предоставляется «как есть». Мы стараемся, чтобы оно работало постоянно, но возможны перебои. Мы оставляем за собой право ограничить или удалить аккаунты, нарушающие правила.
- **Удаление аккаунта**: Вы можете удалить аккаунт в любой момент: Профиль → «Удалить аккаунт».
- **Контакты**: {CONTACT}. Если условия изменятся, мы опубликуем новую дату на этой странице.

### 5.4 Cookies and storage — `Cookie va ma’lumotlarni saqlash` / `Cookie и хранение данных` (new page)
**Uzbek**
- **Nima saqlanadi**: {APP} faqat ishlashi uchun zarur bo‘lgan ma’lumotlarni qurilmangizda saqlaydi: kirish kaliti (siz chiqmaguningizcha hisobingizda qolishingiz uchun), til, mavzu (yorug‘/qorong‘i) va ilova sozlamalari.
- **Reklama va kuzatuv yo‘q**: Biz reklama, analitika yoki kuzatuv cookie-fayllaridan foydalanmaymiz va ma’lumotlaringizni uchinchi tomonlarga reklama uchun bermaymiz.
- **Qanday o‘chirish mumkin**: Hisobdan chiqing (Profil → «Chiqish») yoki brauzer sozlamalarida ushbu sayt ma’lumotlarini tozalang. Ilovada esa ilovani o‘chirib qayta o‘rnatish kifoya.
- **Aloqa**: {CONTACT}.

**Russian**
- **Что хранится**: {APP} хранит на вашем устройстве только то, что нужно для работы: ключ входа (чтобы вы оставались в аккаунте, пока не выйдете), язык, тему (светлая/тёмная) и настройки приложения.
- **Без рекламы и слежения**: Мы не используем рекламные, аналитические или следящие cookie и не передаём ваши данные третьим лицам для рекламы.
- **Как удалить**: Выйдите из аккаунта (Профиль → «Выйти») или очистите данные этого сайта в настройках браузера. В приложении достаточно удалить и заново установить приложение.
- **Контакты**: {CONTACT}.

**First-visit notice on the website** (small glass bar at the bottom, one button, shown once, remembered locally):
`{APP} faqat ishlashi uchun zarur ma’lumotlarni qurilmangizda saqlaydi. Reklama va kuzatuv yo‘q. Batafsil` → button **Tushunarli** / `{APP} хранит на устройстве только данные, нужные для работы. Без рекламы и слежения. Подробнее` → **Понятно**. If you ever add analytics or ads, the notice must become a real opt-in consent **before** anything loads.

### 5.5 Delete account — `Hisobni o‘chirish` / `Удаление аккаунта`
In-app flow: Profile → red row → sheet with warning `Hisobingiz va barcha ma’lumotlaringiz butunlay o‘chiriladi. Buni qaytarib bo‘lmaydi.` / `Аккаунт и все ваши данные будут удалены навсегда. Это нельзя отменить.` → password field → danger button **Butunlay o‘chirish / Удалить навсегда** → errors `Parol noto‘g‘ri / Неверный пароль` → toast `Hisob o‘chirildi / Аккаунт удалён` → back to login. The server deletes everything immediately (also photos/files and backup copies on the next backup).

Public page text:
- **Ilova ichida / В приложении**: 1. {APP} ilovasini yoki veb-saytini oching va hisobingizga kiring. 2. «Profil» bo‘limi → «Hisobni o‘chirish» ni bosing. 3. Parolingizni kiriting va tasdiqlang. Hisob darhol o‘chiriladi. / 1. Откройте приложение или сайт {APP} и войдите в аккаунт. 2. Раздел «Профиль» → нажмите «Удалить аккаунт». 3. Введите пароль и подтвердите. Аккаунт удаляется сразу.
- **Ilovaga kira olmasangiz / Если не можете войти**: {CONTACT} ga loginingizni yozib yuboring. Hisobni egasi ekaningizni tekshirib, 30 kun ichida o‘chiramiz. / Напишите свой логин: {CONTACT}. Мы проверим, что аккаунт ваш, и удалим его в течение 30 дней.
- **Nima o‘chiriladi / Что удаляется**: list every kind of data the new app stores.

### 5.6 Sign-up consent ticks
Both must be ticked before **Register** activates; links open the pages in the app; the server stores each consent with the legal **version** (date string) and timestamp.
- `Foydalanish shartlari va maxfiylik siyosatini o‘qidim va roziman` / `Я прочитал(а) условия использования и политику конфиденциальности и согласен(на)`
- *(children apps only)* `18 yoshga to‘lmagan bo‘lsam, ota-onam (vasiyim) ro‘yxatdan o‘tishimga rozi` / `Если мне нет 18 лет, мои родители (опекун) согласны на мою регистрацию`

---

## 6. Security (non-negotiable)
1. **The app never talks to the database directly.** All data goes through your own server API. Database keys (for example a Supabase `service_role` key) exist **only** on the server, in environment variables. If you ever do use a client-side database SDK (Supabase/Firebase), every table must have **Row Level Security** policies so a user can only read/write their own rows; test this with a second account.
2. **Passwords**: PBKDF2-HMAC-SHA256, **200 000** iterations, 16-byte random salt per user (or Argon2/bcrypt). Compare hashes with a constant-time function. Minimum length enforced on the server.
3. **Login tokens**: 32 random bytes (URL-safe). Store only **SHA-256(token)** in the database; expire after 120 days; delete on logout and on account deletion. Send as `Authorization: Bearer …` (no cookies → no CSRF).
4. **Brute-force limits**: max 15 login/register attempts per 10 minutes **per IP and per username** (the `X-Forwarded-For` header can be faked, so the per-username limit is required). Return `429`.
5. **Authorization on the server**: every request loads the user from the token; every query is scoped to that user (or their school/team); roles (user/teacher/admin) are checked on the server for every admin route. Never trust role or ownership fields sent by the app.
6. **Input limits**: max JSON body size (e.g. 64 KB; uploads separately limited), validate types and lengths, trim strings, reject unknown values.
7. **Public pages** rendered by the server get a strict `Content-Security-Policy`; any user-made HTML is shown only inside `<iframe sandbox="allow-scripts">` (no `allow-same-origin`).
8. **Running user code** (only if the app needs it): a **separate** service with **no secrets and no database**, resource limits (CPU 4 s, memory 512 MB, file size 1 MB, 64 files), no network, restricted built-ins, and an AST check that blocks `__dunder__` attributes and frame/generator attributes (`gi_`, `f_`, `tb_`, `co_`…).
9. **Secrets**: never in git (also no `.db` files, no `.env`). Admin password from an environment variable, minimum 12 characters; the server refuses to start in production without it. AI keys only on the server.
10. **Free hosting sleeps.** Free Render servers sleep after ~15 minutes: the first request takes 20–60 s. The app must: ping the server in the background on start; use a **75 s** timeout for the session check and login (normal requests 12 s); show the "server is waking up" message (§3.1); never log the user out because of a timeout (only on a real `401`).
11. **Backups**: database backed up to a **private** storage bucket (e.g. Supabase Storage, `public: false`), at most every 15 s after changes and on shutdown; restored on start.
12. **HTTPS everywhere**; CORS can be `*` only because auth uses bearer tokens, not cookies.
13. **Delete account** really deletes (database rows, photos/files, tokens, consents) and is available inside the app and via a public instruction page (required by Google Play).
14. **Privacy by design**: collect the minimum; no analytics/ads SDKs; write in the privacy policy exactly what you store. Note for later: Uzbekistan's personal-data law may require local storage of citizens' data; flag this to the owner before launch.

---

## 7. Working rules for Claude (how the owner works)
1. **Never commit to `main` directly.** One branch per task (`ai/<task-name>`), push, run the build, merge into `main` **only when the build is green**. Then confirm the website/APK actually updated.
2. Commit author: name **`Behruz`**, email **`behryzmamajon@gmail.com`**.
3. Every user-visible text in **Uzbek and Russian** (§4).
4. Use the design tokens and shared components (§2); never hard-code colours or font sizes in screens. No violet.
5. Keep tests green; add a test for each feature (logic tests + screen tests that tap through the app and fail on layout overflow).
6. Ask before: adding paid services, changing prices or data structure, deleting user data, adding new heavy dependencies.
7. Explain in **simple words** what changed and how to see it; the owner is not a programmer. Always give the live link at the end.
8. Write a `HANDOVER.md` in the repo (what the app is, map of the code, rules, how to build), and keep it updated.

---

## 8. Build and publish pipeline (GitHub)
- **Repository** on GitHub; **GitHub Actions** builds on every push to `main` and on manual runs for branches.
- **Jobs** (Flutter version, adapt for other stacks):
  1. **android**: Java **21** (Android lint crashes on 17), Flutter stable, generate platform folders if needed, `flutter analyze` (warnings non-fatal), `flutter test`, screenshot tests (light/dark, phone/desktop, uz/ru), `flutter build apk --release`, upload APK, publish a GitHub Release `latest` with `<App>.apk` (direct download link).
  2. **web**: `flutter build web --release --base-href "/<repo>/"`, set `<title>`, description, `lang="uz"`, `theme-color #0A6CFF`, **Open Graph** tags (title, description, 512 px icon) for nice Telegram/Instagram previews, manifest name/colours, favicons from the app icon, generate the static legal pages (uz + ru).
  3. **ios**: build without signing to prove it compiles (macOS runner).
  4. **web-deploy** (main only): combine website + APK into one folder (`/` site, `/<App>.apk`), upload to **GitHub Pages**, **wait 45 s** (GitHub lists new artifacts with a delay; without the wait the deploy fails with "No artifacts named github-pages"), then deploy. github.io opens in Uzbekistan.
  5. Save logs and screenshots to branches `ci-logs-android` / `ci-logs-ios` so they can be read without logging in.
- If only the deploy step fails, start a **fresh** run (a partial re-run uploads the artifact twice and fails with "Multiple artifacts").
- **Server**: Render web service from the same repo (`rootDir: server`), health check `/api/ping`, secrets set in Render → Environment (`ADMIN/TEACHER_PASSWORD`, `SUPABASE_URL`, `SUPABASE_KEY`, AI keys). Prefer a paid plan (~$7/month) when real users arrive, so the server never sleeps.

---

## 9. Definition of done (check every item and report)
- [ ] Owner's questions answered; app name/description in uz + ru.
- [ ] Design tokens, fonts, light + dark themes exactly as §2; no violet anywhere; screenshots of 5 key screens light/dark, phone/desktop look like `reference/`.
- [ ] Phone floating tab bar and desktop collapsible glass sidebar with profile card; mouse wheel/drag on horizontal rows; Enter confirms.
- [ ] Live background on main screens, off on focused screens; setting to switch it off; reduced motion respected.
- [ ] About (team photos), Privacy, Terms, Cookies & storage, Delete account: in the app **and** public URLs, uz + ru; consent ticks on sign-up; cookie notice on the website.
- [ ] Security list §6 implemented; second-account test proves users cannot read each other's data.
- [ ] Server wake-up handling (§6.10) works after 15 minutes of idle.
- [ ] Build green; website + APK published; links sent to the owner.
