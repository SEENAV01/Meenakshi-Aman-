# Gyanify agent rules

Gyanify is a coaching app: a teacher (`teacher_admin`) runs courses and batches,
students sign up, request a batch, and get materials only after approval.
The owner is a teacher, not a developer: talk in simple Hinglish, ask one
question at a time and only when truly blocked.

## Layout
- Flutter app in `app/` (`lib/src/app.dart` UI, `backend.dart` Supabase calls,
  `links.dart` YouTube / Meet / Zoom link checks).
- Supabase in `supabase/` (`migrations/`, `tests/security_test.mjs`).
- Branch: `main`. All work, commits and pushes go to `main`
  (there is no `feat/app-foundation` branch).
- CI: `.github/workflows/android-apk.yml` builds the APK on every push to `main`
  and publishes it on the GitHub Release named `latest`.
  `.github/workflows/security-test.yml` runs the security test (local stack + live project).

## Product decisions (do not change without the owner)
- Videos: Unlisted YouTube links, played inside the app. Never store video files in Supabase.
- Live classes: a pasted Google Meet / Zoom link with date and time; "Join" opens it.
  No embedded Jitsi / meet.jit.si.
- Config: `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` come from GitHub Actions
  secrets via `--dart-define`. Auth redirect URL is `gyanify://login-callback/`.
- Signing: one fixed release keystore kept in GitHub secrets. Without it CI publishes
  a debug test build and must say so.
- Sign-up works with Supabase email confirmation OFF; the teacher's approval is the gate.

## Tooling
- Flutter 3.47.7: `$HOME/.local/share/gyanify/flutter/bin`. Set `ANDROID_HOME` and
  `ANDROID_SDK_ROOT` to `$HOME/.local/share/gyanify/android-sdk`.
- Use `set -o pipefail` whenever piping to `tee`. A step passed only if its exit code is 0.
- APK builds: `GRADLE_OPTS='-Dorg.gradle.jvmargs=-Xmx1536m -Dorg.gradle.workers.max=1'`.
  If the kernel_snapshot step fails, run `flutter clean` + `flutter pub get` and retry once.
  If it fails again, stop and report the error with `free -h` and `df -h`.
- After every build, report the APK path, size, sha256 and modified time, and confirm it is
  newer than the last source edit.

## Proof
- Never claim something works without showing the command and the last lines of its
  output, or the GitHub Actions run result.
- Every final report has three sections: verified locally / verified on live backend / not verified.

## Secrets and git
- Never commit `.env` or config files with real values, keystores (`*.jks`, `.release-keys/`),
  `key.properties`, service_role keys, or APKs. Check `git diff --cached --name-only`
  before every commit.
- After committing, report `git status -sb`. If a push fails, report the exact error and stop.
  Don't try to work around authentication.
- After each working phase, commit and push to `main`.

## Database
- Never edit a migration that has been applied to a live project. Add a new timestamped
  file in `supabase/migrations/`.
- Any change to RLS, grants or storage policies must keep `supabase/tests/security_test.mjs`
  passing (rejected student cannot list/sign/download batch files by any path, no student
  can become `teacher_admin`, students cannot approve requests or create courses).

## Docs
- Update `PROJECT_STATUS.md` at the end of each milestone.
