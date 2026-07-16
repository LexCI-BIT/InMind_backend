-- ============================================================
-- InMind · teachers — teacher profile (1:1 with users)
-- ============================================================

create table public.teachers (
  id                   serial primary key,
  user_id              uuid not null references public.users(id) on delete cascade,
  date_of_birth        date,
  teacher_id_photo_url varchar,
  id_verified          boolean not null default false,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint teachers_user_id_key unique (user_id)
);

-- Trigger
create trigger trg_teachers_updated
  before update on public.teachers
  for each row execute function public.set_updated_at();

-- RLS
alter table public.teachers enable row level security;

create policy teachers_select on public.teachers
  for select using (auth.uid() is not null);

create policy teachers_insert on public.teachers
  for insert with check (user_id = auth.uid() or "current_role"() = 'admin'::user_role);

create policy teachers_update on public.teachers
  for update using (user_id = auth.uid() or "current_role"() = 'admin'::user_role);
