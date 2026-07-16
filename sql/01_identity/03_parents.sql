-- ============================================================
-- InMind · parents — parent profile (1:1 with users)
-- ============================================================

create table public.parents (
  id            serial primary key,
  user_id       uuid not null references public.users(id) on delete cascade,
  child_name    varchar,
  child_class   varchar,
  child_section varchar,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint parents_user_id_key unique (user_id)
);

-- Trigger
create trigger trg_parents_updated
  before update on public.parents
  for each row execute function public.set_updated_at();

-- RLS
alter table public.parents enable row level security;

create policy parents_select on public.parents
  for select using (
    user_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  );

create policy parents_insert on public.parents
  for insert with check (user_id = auth.uid() or "current_role"() = 'admin'::user_role);

create policy parents_update on public.parents
  for update using (user_id = auth.uid() or "current_role"() = 'admin'::user_role);
