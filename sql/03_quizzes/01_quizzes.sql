-- ============================================================
-- InMind · quizzes — teacher-created quizzes with lifecycle
-- ============================================================

create table public.quizzes (
  id                  serial primary key,
  teacher_id          uuid not null references public.users(id) on delete cascade,
  title               varchar not null,
  subject             varchar,
  target_class        varchar,
  target_section      varchar,
  duration_seconds    int4 default 210,
  status              varchar not null default 'draft',
  go_live_immediately boolean default false,
  scheduled_at        timestamptz,
  started_at          timestamptz,
  ended_at            timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint quizzes_status_check
    check (status in ('draft', 'scheduled', 'live', 'completed'))
);

-- Indexes
create index idx_quizzes_teacher on public.quizzes (teacher_id);
create index idx_quizzes_status on public.quizzes (status);
create index idx_quizzes_class on public.quizzes (target_class);
create index idx_quizzes_status_class on public.quizzes (status, target_class, target_section);

-- Trigger
create trigger trg_quizzes_updated
  before update on public.quizzes
  for each row execute function public.set_updated_at();

-- RLS
alter table public.quizzes enable row level security;

create policy quizzes_select on public.quizzes
  for select using (auth.uid() is not null);

create policy quizzes_insert on public.quizzes
  for insert with check (
    teacher_id = auth.uid() and "current_role"() = 'teacher'::user_role
  );

create policy quizzes_update on public.quizzes
  for update using (teacher_id = auth.uid() or "current_role"() = 'admin'::user_role);

create policy quizzes_delete on public.quizzes
  for delete using (teacher_id = auth.uid() or "current_role"() = 'admin'::user_role);
