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
