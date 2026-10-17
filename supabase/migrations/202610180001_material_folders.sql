-- Third migration: folders (chapters) inside a batch. Never edit older migration files.
--
-- Access rules are exactly the same as learning_materials:
--   * only the teacher who owns the batch can create / rename / reorder / delete,
--   * only approved students of that batch can read,
--   * signed-out visitors get nothing.

create table public.material_folders (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.batches (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete restrict,
  title text not null check (char_length(btrim(title)) between 1 and 160),
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  -- lets learning_materials point at (folder, batch) so a material can only sit
  -- in a folder of its own batch
  unique (id, batch_id)
);

create index material_folders_batch_order_idx
  on public.material_folders (batch_id, display_order, created_at);

-- NULL folder_id = "not in a folder" (materials added before folders existed).
alter table public.learning_materials add column folder_id uuid;

-- Default NO ACTION: a folder that still has materials cannot be deleted
-- (the app asks the teacher to move or delete them first, so no PDF is lost).
-- Deleting a whole batch still works: both cascades finish before the check.
alter table public.learning_materials
  add constraint learning_materials_folder_same_batch_fkey
  foreign key (folder_id, batch_id)
  references public.material_folders (id, batch_id);

create index learning_materials_folder_order_idx
  on public.learning_materials (folder_id, display_order, created_at);

alter table public.material_folders enable row level security;

create policy "teacher_manage_folders"
on public.material_folders for all to authenticated
using ((select public.owns_batch(batch_id)))
with check ((select public.owns_batch(batch_id)) and created_by = (select auth.uid()));

create policy "approved_students_read_folders"
on public.material_folders for select to authenticated
using ((select public.is_approved_batch_student(batch_id)));

grant select, insert, update, delete on public.material_folders to authenticated;
revoke all on public.material_folders from anon;
revoke truncate, references, trigger on public.material_folders from authenticated;
