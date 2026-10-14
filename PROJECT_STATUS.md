# GYANIFY Project Status

## Implemented in this checkpoint

- Student email/password signup with email verification redirect, sign-in, password recovery and reset, persistent Supabase sessions, and sign-out.
- Database-backed role selection and separate student/teacher navigation. Signup always creates a `student`; no client action can set `teacher_admin`.
- Teacher course and batch creation, enrollment request review, and private PDF upload for a batch.
- Student course/batch catalog, enrollment request, approved-batch view, and PDF viewing using short-lived signed links.
- Supabase Row Level Security for teacher-owned courses/batches, own enrollment requests, teacher review, approved-student materials, and private PDF storage.
- Enrollment review trigger and constraints prevent students from changing request state and prevent teachers from rewriting enrollment identity.
- Android deep-link registration for `gyanify://login-callback/`.

## Actually verified locally

- `cd app && flutter pub get` completed successfully.
- `cd app && flutter analyze` passed with no issues.
- `cd app && flutter test` passed (the backend-not-configured widget test).
- `cd app && flutter build apk --debug` built a debug APK at `app/build/app/outputs/flutter-apk/app-debug.apk`.
- The APK is a DEVELOPMENT / DEBUG build, unsigned for release, and has not been installed or exercised on an Android device.

## Not verified against a deployed backend

- No Supabase project URL or publishable key is configured in this workspace; no `.env`, `supabase/config.toml`, deployed project, or usable Supabase CLI is present.
- The migration has not been applied. Signup/email delivery, redirects, trusted teacher provisioning, CRUD, enrollment, PDF upload, signed links, and direct-API authorization have therefore not been end-to-end tested against Supabase.
- Jitsi host/join runtime behavior has not been tested.

## Owner setup required

1. Supabase Dashboard mein project create/open karein. Project URL aur **publishable** key apne local Codespace environment mein rakhein; `service_role`/secret key app, repository, ya chat mein kabhi na daalein.
2. Supabase SQL Editor mein `supabase/migrations/202610140001_initial_foundation.sql` ka poora SQL run karein. Isse tables, roles, RLS, private PDF bucket/policies aur auth profile trigger deploy honge.
3. Authentication > Providers > Email mein email signup enabled aur email confirmation ON rakhein. Authentication > URL Configuration > Redirect URLs mein exactly `gyanify://login-callback/` add karein; koi verified website ho to usse Site URL rakhein.
4. Authentication > SMTP Settings mein verified sender ke saath apna SMTP provider configure karein, aur sender domain ka SPF/DKIM verify karein. SMTP credentials sirf Dashboard mein enter karein, chat/repository mein nahi.
5. Ek teacher pehle student ki tarah sign up karke email verify kare. Uske baad owner/admin SQL Editor mein apne verified teacher email ke liye yeh statement run karein; affected row count `1` confirm karein:

   ```sql
   update public.profiles p
   set role = 'teacher_admin'
   from auth.users u
   where u.id = p.id
     and lower(u.email) = lower('verified-teacher@example.com');
   ```

6. Local build ko `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` aur zarurat par `SUPABASE_AUTH_REDIRECT_URL=gyanify://login-callback/` ke saath `--dart-define` se configure karein. Values local environment mein hi rakhein.

## Exact Jitsi / Kotlin warning and impact

The most recent Android build output reported:

> Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): jitsi_meet_flutter_sdk<br>
> Future versions of Flutter will fail to build if your app uses plugins that apply KGP.

The Flutter build completed successfully with this warning on the installed Flutter 3.47.7 toolchain. Flutter's official [built-in Kotlin migration guidance for app developers](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers) explains the plugin migration path; this is a future Flutter build-compatibility warning, not evidence of a current build or runtime failure. It does not justify removing Jitsi or delaying this workflow. No warning suppression or Jitsi removal was applied.

## Next concrete step

Complete the owner setup above, build with the real project URL and publishable key, then run the full teacher/student workflow against the deployed backend. Explicitly verify with a second, unapproved student that both the `learning_materials` query and private Storage object/signing request are denied. Install the resulting development APK on Android and test verification/recovery deep links, PDF upload/viewing, and Jitsi host/join before considering any release build.
