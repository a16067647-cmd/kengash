# Kengash: rules for working on this project

## The one rule
**We build this app to make people's lives easier, not more difficult.**
(Biz bu ilovani odamlarning hayotini osonlashtirish uchun qilyapmiz, qiyinlashtirish uchun emas.)

Check every change against it:
- **Fewer steps.** If something takes 3 taps, look for a way to make it 1. Prefer good defaults over settings.
- **Nothing forced.** New features never add work, notifications or screens nobody asked for. Extra effects
  (moving background, liquid glass) stay off by default.
- **Fast first.** Speed and no lag matter more than visual effects. The app must work on cheap Android phones
  and slow mobile internet.
- **Simple words.** Short Uzbek (and Russian) text that a school student understands. No jargon.
- **Quiet.** Notifications only when they help: once, at a sensible time, never repeated.
- **Safe.** Students' data is private. People only see what their role needs.

## Project facts
- Flutter app in `app/` (Android APK, iOS, web on GitHub Pages) and a FastAPI server in `server/`
  (Render, Postgres on Supabase, schema `kengash`).
- Tests: `cd server && python -m pytest -q`; `cd app && flutter test` (widget tests use `test/fake_server.dart`).
- All user-facing text is in `app/lib/i18n.dart` (uz and ru, with the same keys).
- The repository is public: never commit secrets, keys or the signing keystore.

## Current state (update this section after each big change)
_Last updated: 2026-11-20. Latest merged PR: #36. Web/APK build on GitHub Pages: 89._

**Live:**
- Web: https://a16067647-cmd.github.io/kengash/ · APK: `…/kengash/Kengash.apk` (`version.json` drives the in-app update).
- Server: https://kengash-api.onrender.com (Render free plan, 1 instance, keepalive workflow pings it).
- Telegram bot: login, registration, notifications; menu button opens the app as a Mini App (auto sign-in).

**Features done:** channels (chat, voice, files, polls, announcements with "Ko‘rdi 9/12" + one reminder),
tasks (photo/voice reports, one-tap accept = +1 point), events (QR attendance only while check-in is open),
quarter rating + certificates, portfolio "Mening yo‘lim", book of the month, ideas box, staff accounts,
monthly report + Monday digest, school invite links (`?start=join_<school>`), smart defaults on create,
instant start from cached data, admin panel.

**Workflow:** branch from `main` → PR → CI (android, web, ios, server) green → squash-merge.
After a server change, deploy on Render (manual deploy of the merged commit). Pages rebuilds the app by itself.

**Video:** `tools/video/generate_video.py` makes a 1920×1080 presentation (Uzbek voice + PNG subtitles).
Voice: ElevenLabs if `ELEVENLABS_API_KEY` is set, else OpenAI, else edge-tts. Run it on your own computer
(cloud sessions can't reach the edge-tts service).

**Open / not done:**
- Instagram Reels version of the video (90 s, 1080×1920): requested, not started.
- "Keyingi qadam" (next step) card on Bugun: idea only.
- Database backups: Supabase shows none on the current plan (owner to decide: Pro plan or own weekly `pg_dump`).
- Spend alerts in Supabase / Render / Firebase: owner to check.
- Some Honor phones said "package invalid" for the APK; builds now use v1+v2+v3 signing. Telegram Mini App is the fallback.
