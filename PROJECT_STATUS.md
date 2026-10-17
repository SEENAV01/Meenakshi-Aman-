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
  verify its signature, publish `Meenakshi-Amman-Hindi-Classes.apk` (until 1.0.7: `gyanify.apk`) on the Release named `latest`.
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

### 2026-10-17 — dialog crash fix + rename

- Bug in 1.0.7: Create course → Save showed a red screen. `showTextForm` disposed its
  TextEditingControllers when the dialog Future completed, while the TextFields were still
  animating out. Now a StatefulWidget (`lib/src/dialogs.dart`) disposes them in `dispose()`.
  Verified locally: `flutter test test/dialogs_test.dart` failed 7 tests on the old code
  ("A TextEditingController was used after being disposed", dialogs.dart:221) and passes 9/9
  after the fix (course/batch/PDF form, video form, schedule class, delete confirm; Save and Cancel).
- Visible name is now "Meenakshi Amman Hindi Classes" (app title, login, notice, header,
  profile, Android install/Settings label, release notes, APK file
  `Meenakshi-Amman-Hindi-Classes.apk`, README). Home-screen icon label: "Meenakshi"
  (owner's choice, the full name would be cut). Internal IDs unchanged.
- Verified locally: `flutter analyze` no issues; `flutter test` 18 passed, 1 skipped.
- Not verified: how the label and header look on a real phone.

### 2026-10-18 — refresh bug, folders (chapters), YouTube title

- Bug: after adding a course/batch/material the list only updated after going back
  ("setState() callback argument returned a Future"). All 25 `setState(() => …)` in lib/
  are now block bodies (the role retry had the same bug). Verified locally:
  `test/refresh_test.dart` failed on the old code (course not shown) and passes now; a guard
  test fails if the arrow pattern comes back.
- Found while testing folders: postgrest-dart's `.order()` defaults to descending, so
  courses were Z→A and live classes latest-first. Every `.order()` now says `ascending:`.
- Folders: new migration `202610180001_material_folders.sql` (older files untouched).
  Same rules as materials (teacher writes, approved students read, anon nothing); a material
  can only sit in a folder of its own batch; a non-empty folder cannot be deleted.
  Teacher: create, rename, delete (empty only), reorder folders; pick a folder when adding;
  move items; reorder items (up/down). Students: folder list → items numbered 1, 2, 3 in
  the teacher's order. Old materials show under "Other materials".
- Before the SQL is run the app shows "The database needs an update … run
  supabase/migrations/202610180001_material_folders.sql" (students: "Your teacher is
  updating this class"), no crash. Verified against local Supabase with the table hidden.
- YouTube: pasting a link fills the title from oEmbed (no API key); if that fails the teacher
  types it; a typed title is never overwritten; thumbnail next to the title and in lists.
- Verified locally: `flutter analyze` no issues; `flutter test` 48 passed (incl. 2 backend
  integration tests on local Supabase); `security_test.mjs` 54 passed, 0 failed; with two
  deliberately opened folder holes it reported 3 failures.
- Not verified: on a real phone; on the live Supabase (folders SQL not run there yet).

### 2026-10-18 — lists always refresh, Requests badge

- Bug: the teacher's Requests tab only showed a new student request after restarting the app
  (tabs live in an IndexedStack and loaded once; empty lists were not pull-to-refresh).
- Now every list (teacher: courses, requests, live classes, batch folders, folder items;
  student: catalog, my learning, live classes, folders, items) can be pulled down even when
  empty or showing an error, and has a Refresh button. A tab reloads when you switch to it and
  when the app comes back from the background. The Requests tab shows a badge with the number
  of pending requests (updated on start, tab switch, resume, refresh and after approve/reject).
- Verified locally: `test/tabs_refresh_test.dart` — 12 tests failed on the old code
  ("Asha" not found after switching tabs; nothing to pull on the empty list) and pass now.
  `flutter analyze` no issues; `flutter test` 58 passed (2 integration tests skipped without
  env); with local Supabase both integration tests pass (badge count +1 after a request,
  back after approval); `security_test.mjs` 54 passed.
- Not verified: on a real phone; on the live Supabase.

### 2026-10-17 — live security test runs #7/#8 failed (not a security gap)

- Runs #7 and #8 were started 13 s apart with the same test teacher. Each run deleted all
  "[SECTEST]" courses at start and end, so each wiped the other's test data mid-run. Every
  failed check was "teacher can't see own course/folder/PDF" or the approved-student positive
  control; no "student cannot …" check failed.
- Fixed in the test, no migration needed: each run tags its own course, deletes only that
  course (plus leftovers older than 1 hour), stops with a clear message if its data vanishes,
  requires teacher approve/reject/revoke to change a row, and the "materials not moved" check
  needs both items. The live job now has a concurrency group (one run at a time).
- Verified locally: two copies of the OLD test started 0.2 s apart broke 3/3 times (same
  errors); two copies of the NEW test passed 54/54 each, 3/3 times, leaving no test course.

## Owner setup required

See the numbered list in the final report of the 2026-10-17 session (also repeated in
`docs/OWNER_SETUP.md`).
