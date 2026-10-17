# Gyanify — owner setup (sirf aap kar sakti/sakte hain)

Repo: https://github.com/SEENAV01/Meenakshi-Aman-
Kabhi bhi `service_role` / secret key app, repo ya chat mein mat daaliye. Sirf **publishable** key.

## A. Supabase (https://supabase.com/dashboard → apna project)

1. **Pehli SQL file (agar pehle nahi chalayi):** Left menu → *Table Editor*. Agar wahan `profiles`,
   `courses`, `batches` tables dikh rahi hain to ye step chhod dijiye. Nahi dikh rahi to:
   GitHub par `supabase/migrations/202610140001_initial_foundation.sql` kholiye → upar right
   *Copy raw file* button → Supabase left menu *SQL Editor* → *New query* → paste → *Run*.
   "Success. No rows returned" aana chahiye.
2. **Doosri SQL file (zaroori, ek hi baar):** same tarah
   `supabase/migrations/202610170001_youtube_meet_links_hardening.sql` copy → SQL Editor → *Run*.
   Isse Meet/Zoom link, YouTube link, student email aur extra security aayegi.
   Do baar chalayenge to "already exists" error aayega — matlab pehle hi chal chuki hai, theek hai.
3. **Email confirmation OFF:** *Authentication* → *Sign In / Providers* → *Email* →
   **Confirm email** ka toggle OFF → *Save*. (Approval aapke haath mein hai, isliye ye safe hai.)
4. **Redirect URL:** *Authentication* → *URL Configuration* → *Redirect URLs* → *Add URL* →
   `gyanify://login-callback/` → *Save*.
5. **URL aur key copy kariye:** *Project Settings* (neeche gear icon) → *Data API* (ya *API*) mein
   **Project URL** (`https://xxxx.supabase.co`), aur *API Keys* mein **Publishable key**
   (`sb_publishable_...`). Dono GitHub secrets mein jayenge (step B).

## B. GitHub secrets

Repo kholiye → **Settings** → left mein **Secrets and variables** → **Actions** →
**New repository secret**. Har secret ke liye: *Name* likhiye, *Secret* mein value paste, *Add secret*.

6. `SUPABASE_URL` = Project URL (jaise `https://abcd1234.supabase.co`, aage-peeche space nahi).
   Naam bilkul yahi hona chahiye — capital letters aur underscore ke saath. Ye URL secret nahi hai,
   isliye *Variables* tab mein bhi isi naam se rakh sakte hain; workflow dono jagah dekhta hai.
7. `SUPABASE_PUBLISHABLE_KEY` = `sb_publishable_...` wali key

## C. Signing key (ek hi baar — isse students bina uninstall kiye update kar paayenge)

8. Repo page → green **Code** button → **Codespaces** tab → apna Codespace kholiye
   (ya *Create codespace on main*).
9. Neeche Terminal mein ye do lines chalaiye:
   ```
   git pull
   bash scripts/create-release-keystore.sh
   ```
   "Done." dikhega.
10. Phir: `code .release-keys/github-secrets.txt` — file khulegi. Usme 4 naam aur unki values hain.
    Step B ki tarah 4 secrets banaiye: `ANDROID_KEY_ALIAS`, `ANDROID_KEYSTORE_PASSWORD`,
    `ANDROID_KEY_PASSWORD`, `ANDROID_KEYSTORE_BASE64` (ye bahut lambi ek line hai — poori copy kariye).
11. **Backup:** left Explorer mein `.release-keys` folder → `gyanify-release.jks` par right-click →
    *Download* → Google Drive / pen drive mein safe rakhiye, aur `github-secrets.txt` bhi
    (password ke liye) kisi safe jagah. Ye kho gayi to students ko app uninstall karke dobara
    install karni padegi. Phir Codespace mein `github-secrets.txt` delete kar dijiye.
    (`.release-keys/` git mein kabhi commit nahi hota.)

## D. Naya APK banwana aur bhejna

12. Repo → **Actions** → *Android APK* → *Run workflow* → *Run workflow* (ya koi bhi naya push).
    Green tick aane tak ruko (~10 min).
13. Phone par: repo → **Releases** → **latest** → `Meenakshi-Amman-Hindi-Classes.apk` download → install
    ("unknown apps" allow karna padega). Release notes mein likha hoga
    *Release build* ya *TEST BUILD (debug)*.
14. WhatsApp par students ko `Meenakshi-Amman-Hindi-Classes.apk` **Document** ki tarah bhejiye.

## E. Aapka teacher account

15. App install karke **New student? Create an account** se apne email se sign up kariye.
16. Supabase *SQL Editor* mein (email badal kar) chalaiye — "1 row" affected aana chahiye:
    ```sql
    update public.profiles p
    set role = 'teacher_admin'
    from auth.users u
    where u.id = p.id
      and lower(u.email) = lower('aapka-email@gmail.com');
    ```
    App band karke dobara kholiye — ab *GYANIFY · Teacher* dikhega.

## F. Live security test

17. Ek **alag test teacher** account banaiye (aapka asli password GitHub mein nahi jayega):
    app mein sign up kariye `aapka-naam+sectest@gmail.com` jaise email se (Gmail `+` wale email
    aapke hi inbox mein aate hain), phir step 16 wala SQL is email ke saath chalaiye.
18. GitHub secrets (step B jaisa): `SECTEST_TEACHER_EMAIL` aur `SECTEST_TEACHER_PASSWORD`.
19. Repo → **Actions** → *Supabase security test* → *Run workflow*. Job **live** mein
    `43 passed, 0 failed` aana chahiye. Test har baar 2 test-student accounts banata hai
    (`...+sectest-rejected-...`) — *Authentication → Users* mein inhe kabhi bhi delete kar sakte hain.
    Test ka course "[SECTEST] delete me" khud delete ho jata hai.

## G. YouTube

20. Video YouTube par **Unlisted** upload kariye. *Details → Show more → Allow embedding* ON rahe
    (default ON hota hai). Link (`youtu.be/...` ya `youtube.com/watch?v=...`) app mein batch →
    *Add material* → *Add YouTube video link* mein paste kariye.

## H. Optional — "Forgot password"

21. Supabase ka free built-in email sirf aapki team ke emails par jata hai, students ko nahi.
    Students ka password reset chahiye to *Authentication → Emails → SMTP Settings* mein apna SMTP
    (jaise Brevo / Resend free plan) lagaiye. Tab tak student bhool jaye to naya account bana kar
    dobara request bhej sakta hai.
