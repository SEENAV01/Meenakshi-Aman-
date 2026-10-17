# GYANIFY Project Status

Branch: `main` (all work happens here; there is no `feat/app-foundation` branch).

## What the app does now

Teacher (`teacher_admin`):
- Create courses and batches.
- Per batch: upload PDF notes (private storage, max 20 MB), add Unlisted YouTube video links,
  delete materials.
- Live Classes tab: schedule a class (batch, title, date, time, Google Meet / Zoom link),
  delete it, and "Join" it.
- Requests tab: see student name + email, Approve / Reject, later Remove access or Approve again.

Student:
- Sign up (always `student`; works with email confirmation OFF), browse courses, request a batch.
- After approval: open PDFs in-app, Download PDFs (short-lived signed link), watch YouTube videos
  inside the app (with an "Open in YouTube" fallback), see live classes with a Join button.
- Rejected / removed students see nothing from that batch.

Removed: embedded Jitsi (`jitsi_meet_flutter_sdk`), and the unused `record` / `audioplayers` packages.

## Database

- `supabase/migrations/202610140001_initial_foundation.sql` — unchanged.
- `supabase/migrations/202610170001_youtube_meet_links_hardening.sql` — new:
  `live_sessions.meeting_url` (Meet/Zoom only, `room_id` now optional), YouTube-only video
  links, `profiles.email` (read-only, filled by the sign-up trigger), and privilege hardening
  (no client profile insert/delete, no anon table access, no TRUNCATE).

## CI (GitHub Actions)

- `android-apk.yml` — on every push to `main` (pure docs changes skipped): `flutter analyze`, `flutter test`, build the APK,
  verify its signature, publish `gyanify.apk` on the Release named `latest`.
  Release-signed when the four `ANDROID_*` secrets exist, otherwise a DEBUG test build
  (the release notes say which).
- `security-test.yml` — job `local`: starts a throwaway Supabase in the runner, applies all
  migrations, runs `supabase/tests/security_test.mjs` and `app/test/backend_integration_test.dart`.
  Job `live`: runs the security test against the real project once the secrets exist
  (skipped with a warning until then). Also runs weekly and on manual dispatch.

## Verified

See the latest section below; every claim there has a command or CI run behind it.

### 2026-10-17 checkpoint

Verified locally (this cloud session, Flutter 3.47.7, local `supabase start` stack, CLI 2.121.0):
- Both migrations apply in order on a local Supabase (second one applied on top of the first,
  like on a live project).
- `node supabase/tests/security_test.mjs` → `43 passed, 0 failed`.
- Mutation check: after deliberately adding a permissive storage read policy and
  `grant update (role)` on profiles, the same test reported `33 passed, 10 failed` (exit 1);
  after removing them, `43 passed` again. The test really detects holes.
- `flutter test test/backend_integration_test.dart` (app's real `GyanifyBackend` against the local
  stack: create course/batch, upload PDF, add video, schedule class, student sign-up, request,
  approve, view + download PDF with `Content-Disposition`, live class link, revoke, delete) → passed.
- `flutter analyze` → No issues found. `flutter test` → 6 passed, 1 skipped (integration, needs env).
- `scripts/create-release-keystore.sh` creates a PKCS12 key and refuses to overwrite an existing one.
- A local Android release build could not finish here: Maven Central answered
  `429 Too Many Requests` twice. Android builds are proven in GitHub Actions instead (below).

Verified in GitHub Actions (https://github.com/SEENAV01/Meenakshi-Aman-/actions):
- Supabase security test run 39006631972, job `local`: both migrations applied on a fresh
  Supabase, `43 passed, 0 failed`, integration test `1 test passed`. Job `live`: skipped (no secrets).
- Android APK run for commit `e58991f`: analyze + tests passed, DEBUG test build published on
  Release `latest` as `gyanify.apk` (149.8 MB, not connected to Supabase because the secrets
  are missing; the release notes say so).
- Android APK run 39007636008 (`release_check`): release APK built and signed through
  `android/key.properties` with a throwaway key (`apksigner`: `CN=Throwaway check`), 76.4 MB,
  nothing published. So the real key path works once the four `ANDROID_*` secrets exist.

- Android APK run 39011738960 (commit `9127521`, after the owner fixed the `SUPABASE_URL` secret):
  log shows `Supabase config found for host: bthmlxzzcipctmseckvx.supabase.co`; Release `latest`
  = Gyanify 1.0.7, "Connected to Supabase", still a DEBUG test build (no signing secrets yet).

Verified on live backend:
- The project host answers (`/auth/v1/health` → HTTP 401 "No API key found", i.e. it exists).
- Nothing else yet. No live Supabase URL/key is available to this session; the `live` job runs as soon
  as the secrets are added.

Not verified:
- The APK has not been installed or used on a real Android phone (YouTube playback inside the
  WebView, PDF download in the phone browser, Meet/Zoom app hand-off, sign-in deep link).
- Password-reset emails: Supabase's built-in email only reaches project team members; students
  need custom SMTP for "Forgot password" to work.

## Owner setup required

See the numbered list in the final report of the 2026-10-17 session (also repeated in
`docs/OWNER_SETUP.md`).
