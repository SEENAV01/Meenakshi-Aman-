create extension if not exists pgcrypto with schema extensions;

create type public.app_role as enum ('teacher_admin', 'student');
create type public.enrollment_status as enum ('pending', 'approved', 'rejected', 'revoked');
create type public.material_kind as enum ('youtube_video', 'pdf');
create type public.live_session_status as enum ('scheduled', 'live', 'ended', 'cancelled');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  role public.app_role not null default 'student',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles (id) on delete restrict,
  title text not null check (char_length(title) between 1 and 160),
  description text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.batches (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  description text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.enrollments (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.batches (id) on delete cascade,
  student_id uuid not null references public.profiles (id) on delete cascade,
  status public.enrollment_status not null default 'pending',
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  unique (batch_id, student_id),
  constraint enrollments_reviewed_at_check check (
    (status = 'pending' and reviewed_at is null)
    or (status <> 'pending' and reviewed_at is not null)
  )
);

create table public.learning_materials (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.batches (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete restrict,
  kind public.material_kind not null,
  title text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  youtube_url text,
  storage_path text,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint learning_materials_payload_check check (
    (kind = 'youtube_video' and youtube_url is not null and storage_path is null)
    or (kind = 'pdf' and storage_path is not null and youtube_url is null)
  )
);

create table public.live_sessions (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.batches (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete restrict,
  title text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  starts_at timestamptz not null,
  ends_at timestamptz,
  room_id text not null unique check (char_length(room_id) between 24 and 160),
  status public.live_session_status not null default 'scheduled',
  created_at timestamptz not null default now(),
  constraint live_sessions_time_check check (ends_at is null or ends_at > starts_at)
);

create index batches_course_id_idx on public.batches (course_id);
create index enrollments_student_status_idx on public.enrollments (student_id, status);
create index learning_materials_batch_order_idx on public.learning_materials (batch_id, display_order, created_at desc);
create index live_sessions_batch_start_idx on public.live_sessions (batch_id, starts_at);

create function public.current_user_is_teacher()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'teacher_admin'
  );
$$;

create function public.owns_course(p_course_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.courses c
    where c.id = p_course_id and c.teacher_id = (select auth.uid())
  );
$$;

create function public.owns_batch(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.batches b
    join public.courses c on c.id = b.course_id
    where b.id = p_batch_id and c.teacher_id = (select auth.uid())
  );
$$;

create function public.is_approved_batch_student(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.enrollments e
    where e.batch_id = p_batch_id
      and e.student_id = (select auth.uid())
      and e.status = 'approved'
  );
$$;

create function public.create_student_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', ''),
    'student'
  );
  return new;
end;
$$;

create function public.guard_enrollment_review()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.batch_id is distinct from old.batch_id
    or new.student_id is distinct from old.student_id
    or new.requested_at is distinct from old.requested_at then
    raise exception 'Enrollment identity and request time cannot be changed';
  end if;

  if not (select public.owns_batch(old.batch_id))
    or new.status not in ('approved', 'rejected', 'revoked')
    or new.reviewed_at is null then
    raise exception 'Only the batch teacher can review an enrollment';
  end if;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.create_student_profile();

create trigger guard_enrollment_review
before update on public.enrollments
for each row execute function public.guard_enrollment_review();

alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.batches enable row level security;
alter table public.enrollments enable row level security;
alter table public.learning_materials enable row level security;
alter table public.live_sessions enable row level security;

create policy "profiles_select_self_or_teacher"
on public.profiles for select to authenticated
using (id = (select auth.uid()) or (select public.current_user_is_teacher()));

create policy "profiles_update_self"
on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

revoke update on public.profiles from authenticated;
grant update (display_name, updated_at) on public.profiles to authenticated;

create policy "courses_visible_to_signed_in_users"
on public.courses for select to authenticated
using ((select auth.uid()) is not null);

create policy "courses_teacher_insert"
on public.courses for insert to authenticated
with check ((select public.current_user_is_teacher()) and teacher_id = (select auth.uid()));

create policy "courses_teacher_update"
on public.courses for update to authenticated
using ((select public.owns_course(id)))
with check ((select public.owns_course(id)));

create policy "courses_teacher_delete"
on public.courses for delete to authenticated
using ((select public.owns_course(id)));

create policy "batches_visible_to_signed_in_users"
on public.batches for select to authenticated
using ((select auth.uid()) is not null);

create policy "batches_teacher_insert"
on public.batches for insert to authenticated
with check ((select public.owns_course(course_id)));

create policy "batches_teacher_update"
on public.batches for update to authenticated
using ((select public.owns_batch(id)))
with check ((select public.owns_course(course_id)));

create policy "batches_teacher_delete"
on public.batches for delete to authenticated
using ((select public.owns_batch(id)));

create policy "enrollments_select_own_or_managed"
on public.enrollments for select to authenticated
using (student_id = (select auth.uid()) or (select public.owns_batch(batch_id)));

create policy "students_request_own_enrollment"
on public.enrollments for insert to authenticated
with check (
  student_id = (select auth.uid())
  and status = 'pending'
  and reviewed_at is null
  and (select auth.uid()) is not null
  and not (select public.current_user_is_teacher())
);

create policy "teacher_review_enrollment"
on public.enrollments for update to authenticated
using ((select public.owns_batch(batch_id)))
with check ((select public.owns_batch(batch_id)));

create policy "teacher_manage_materials"
on public.learning_materials for all to authenticated
using ((select public.owns_batch(batch_id)))
with check ((select public.owns_batch(batch_id)) and created_by = (select auth.uid()));

create policy "approved_students_read_materials"
on public.learning_materials for select to authenticated
using ((select public.is_approved_batch_student(batch_id)));

create policy "teacher_manage_live_sessions"
on public.live_sessions for all to authenticated
using ((select public.owns_batch(batch_id)))
with check ((select public.owns_batch(batch_id)) and created_by = (select auth.uid()));

create policy "approved_students_read_live_sessions"
on public.live_sessions for select to authenticated
using ((select public.is_approved_batch_student(batch_id)));

grant usage on schema public to authenticated;
grant select, insert, delete on public.profiles to authenticated;
grant select, insert, update, delete on
  public.courses, public.batches, public.enrollments,
  public.learning_materials, public.live_sessions to authenticated;
revoke all on function public.current_user_is_teacher() from public, anon, authenticated;
revoke all on function public.owns_course(uuid) from public, anon, authenticated;
revoke all on function public.owns_batch(uuid) from public, anon, authenticated;
revoke all on function public.is_approved_batch_student(uuid) from public, anon, authenticated;
grant execute on function public.current_user_is_teacher() to authenticated;
grant execute on function public.owns_course(uuid) to authenticated;
grant execute on function public.owns_batch(uuid) to authenticated;
grant execute on function public.is_approved_batch_student(uuid) to authenticated;
revoke all on function public.create_student_profile() from public, anon, authenticated;
revoke all on function public.guard_enrollment_review() from public, anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('learning-materials', 'learning-materials', false, 20971520, array['application/pdf'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "teachers_upload_batch_pdfs"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'learning-materials'
  and exists (
    select 1 from public.batches b
    where b.id::text = (storage.foldername(name))[1]
      and (select public.owns_batch(b.id))
  )
);

create policy "authorized_users_read_batch_pdfs"
on storage.objects for select to authenticated
using (
  bucket_id = 'learning-materials'
  and exists (
    select 1
    from public.learning_materials m
    where m.storage_path = storage.objects.name
      and (
        (select public.owns_batch(m.batch_id))
        or (select public.is_approved_batch_student(m.batch_id))
      )
  )
);

create policy "teachers_delete_batch_pdfs"
on storage.objects for delete to authenticated
using (
  bucket_id = 'learning-materials'
  and exists (
    select 1 from public.batches b
    where b.id::text = (storage.foldername(name))[1]
      and (select public.owns_batch(b.id))
  )
);