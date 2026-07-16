-- ============================================================
-- InMind · users — central identity table (extends auth.users)
-- ============================================================

create table public.users (
  id           uuid primary key references auth.users(id) on delete cascade,
  role         varchar not null,
  full_name    varchar,
  email        varchar not null,
  phone_number varchar,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  is_verified  boolean default false,

  constraint users_role_check check (role in ('student', 'parent', 'teacher')),
  constraint users_email_key unique (email)
);

-- Indexes
create index idx_users_role on public.users (role);

-- Trigger
create trigger trg_profiles_updated
  before update on public.users
  for each row execute function public.set_updated_at();

-- RLS
alter table public.users enable row level security;

create policy profiles_select on public.users
  for select using (
    id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  );

create policy profiles_insert on public.users
  for insert with check (id = auth.uid());

create policy profiles_update on public.users
  for update using (id = auth.uid() or "current_role"() = 'admin'::user_role)
  with check (id = auth.uid() or "current_role"() = 'admin'::user_role);
