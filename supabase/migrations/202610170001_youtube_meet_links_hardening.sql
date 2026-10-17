-- Second migration. Never edit 202610140001_initial_foundation.sql; add new files instead.
--
-- 1. Live classes use a pasted Google Meet / Zoom link instead of an embedded Jitsi room.
-- 2. Videos are YouTube (unlisted) links only; nothing is stored in Supabase Storage.
-- 3. The teacher can see a student's email on enrollment requests.
-- 4. Defence in depth on table privileges.

-- 1. Live classes ----------------------------------------------------------------
alter table public.live_sessions alter column room_id drop not null;
alter table public.live_sessions add column if not exists meeting_url text;

-- NOT VALID: old Jitsi rows (if any) are left alone; every new or edited row is checked.
alter table public.live_sessions
  add constraint live_sessions_meeting_url_check check (
    meeting_url is not null
    and char_length(meeting_url) <= 500
    and meeting_url ~* '^https://([a-z0-9-]+\.)*(meet\.google\.com|zoom\.us|zoom\.com)(/|$)'
  ) not valid;

-- 2. YouTube links -----------------------------------------------------------------
alter table public.learning_materials
  add constraint learning_materials_youtube_url_check check (
    youtube_url is null
    or (
      char_length(youtube_url) <= 500
      and youtube_url ~* '^https://((www|m)\.)?(youtube\.com|youtu\.be)/'
    )
  ) not valid;

-- 3. Student email on the profile (read-only for students) -------------------------
alter table public.profiles add column if not exists email text not null default '';

update public.profiles p
set email = coalesce(u.email, '')
from auth.users u
where u.id = p.id and p.email = '';

create or replace function public.create_student_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Role is always 'student'. Sign-up metadata can never choose the role.
  insert into public.profiles (id, display_name, email, role)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'display_name', ''), 120),
    coalesce(new.email, ''),
    'student'
  );
  return new;
end;
$$;

revoke all on function public.create_student_profile() from public, anon, authenticated;

-- 4. Privilege hardening -------------------------------------------------------------
-- Profiles are only created by the auth trigger and never deleted by a client.
revoke insert, delete on public.profiles from authenticated;
-- Only display_name may be changed by the owner (role and email stay locked).
revoke update on public.profiles from authenticated;
grant update (display_name, updated_at) on public.profiles to authenticated;

-- Signed-out visitors need nothing from these tables.
revoke all on public.profiles, public.courses, public.batches, public.enrollments,
  public.learning_materials, public.live_sessions from anon;

-- TRUNCATE ignores row level security, so no client role should ever hold it.
revoke truncate, references, trigger on public.profiles, public.courses, public.batches,
  public.enrollments, public.learning_materials, public.live_sessions from authenticated;
