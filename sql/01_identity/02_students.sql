-- ============================================================
-- InMind · students — student profile (1:1 with users)
-- ============================================================

create table public.students (
  id                   serial primary key,
  user_id              uuid not null references public.users(id) on delete cascade,
  roll_number          varchar,
  board                varchar,
  class_name           varchar,
  section              varchar,
  school_name          varchar,
  school_email         varchar,
  date_of_birth        varchar,
  blood_group          varchar,
  height               varchar,
  weight               varchar,
  parents_name         varchar,
  parents_phone        varchar,
  profile_photo_url    varchar,
  student_id_photo_url varchar,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint students_user_id_key unique (user_id)
);

-- Indexes
create index idx_students_class on public.students (class_name);
create index idx_students_section on public.students (section);

-- Trigger
create trigger trg_students_updated
  before update on public.students
  for each row execute function public.set_updated_at();

-- RLS
alter table public.students enable row level security;

create policy students_select on public.students
  for select using (
    user_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  );

create policy students_insert on public.students
  for insert with check (
    user_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  );

create policy students_update on public.students
  for update using (
    user_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  );
