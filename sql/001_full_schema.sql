-- ============================================================
-- InMind App — Full Database Schema
-- Migration 001: Profiles + Role tables + Flows + Quizzes + Journal
-- Target: PostgreSQL (Supabase)
-- ============================================================
-- Run this in the Supabase SQL Editor (or via `supabase db push`).
-- ============================================================

-- ----------------------------------------------------------------
-- 0. Extensions
-- ----------------------------------------------------------------
create extension if not exists "pgcrypto";   -- gen_random_uuid()

-- ----------------------------------------------------------------
-- 1. Enums
-- ----------------------------------------------------------------
do $$ begin
  create type public.user_role as enum ('student', 'teacher', 'parent', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.relationship_type as enum ('father', 'mother', 'guardian', 'other');
exception when duplicate_object then null; end $$;

-- ----------------------------------------------------------------
-- 2. Shared trigger: keep updated_at fresh
-- ----------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ================================================================
-- 3. PROFILES  (1 row per auth user — the hub of the ecosystem)
-- ================================================================
create table if not exists public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  role          public.user_role not null,
  full_name     text not null,
  email         text unique,
  phone         text,
  avatar_url    text,
  date_of_birth date,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_profiles_role on public.profiles (role);

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- ================================================================
-- 4. STUDENTS
-- ================================================================
create table if not exists public.students (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null unique references public.profiles (id) on delete cascade,
  roll_number          text,
  board                text,
  class_name           text,
  section              text,
  school_name          text,
  date_of_birth        date,
  blood_group          text,
  height               text,
  weight               text,
  parent_name          text,
  parent_phone         text,
  profile_photo_url    text,
  student_id_photo_url text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index if not exists idx_students_class on public.students (class_name);
create index if not exists idx_students_section on public.students (section);

drop trigger if exists trg_students_updated_at on public.students;
create trigger trg_students_updated_at
  before update on public.students
  for each row execute function public.set_updated_at();

-- ================================================================
-- 5. TEACHERS
-- ================================================================
create table if not exists public.teachers (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null unique references public.profiles (id) on delete cascade,
  date_of_birth        date,
  teacher_id_photo_url text,
  id_verified          boolean not null default false,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

drop trigger if exists trg_teachers_updated_at on public.teachers;
create trigger trg_teachers_updated_at
  before update on public.teachers
  for each row execute function public.set_updated_at();

-- ================================================================
-- 6. PARENTS
-- ================================================================
create table if not exists public.parents (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null unique references public.profiles (id) on delete cascade,
  child_name    text,
  child_class   text,
  child_section text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

drop trigger if exists trg_parents_updated_at on public.parents;
create trigger trg_parents_updated_at
  before update on public.parents
  for each row execute function public.set_updated_at();

-- ================================================================
-- 7. PARENT <-> STUDENT link
-- ================================================================
create table if not exists public.parent_student (
  id            uuid primary key default gen_random_uuid(),
  parent_id     uuid not null references public.parents (id) on delete cascade,
  student_id    uuid not null references public.students (id) on delete cascade,
  relationship  public.relationship_type not null default 'guardian',
  is_primary    boolean not null default false,
  created_at    timestamptz not null default now(),
  unique (parent_id, student_id)
);

create index if not exists idx_parent_student_parent  on public.parent_student (parent_id);
create index if not exists idx_parent_student_student on public.parent_student (student_id);

-- ================================================================
-- 8. Auto-create a profile row when a new auth user signs up
-- ================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, role, full_name, email, phone)
  values (
    new.id,
    coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'student'),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.email,
    new.raw_user_meta_data ->> 'phone_number'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ================================================================
-- 9. Helper: current user's role (used by RLS policies)
-- ================================================================
create or replace function public.current_role()
returns public.user_role
language sql stable
security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- ================================================================
-- 10. FLOW SESSIONS
-- ================================================================
create table if not exists public.flow_sessions (
  id                serial primary key,
  session_id        varchar(100) unique not null,
  user_id           uuid not null references public.profiles (id) on delete cascade,
  flow_type         varchar(10) not null check (flow_type in ('static', 'dynamic')),
  started_at        timestamptz not null,
  completed_at      timestamptz,
  total_duration_ms int,
  total_steps       int,
  steps_completed   int,
  engagement_score  int check (engagement_score between 0 and 100),
  engagement_label  varchar(20),
  is_genuine        boolean default true,
  flags             text[] default '{}',
  created_at        timestamptz not null default now()
);

create index if not exists idx_flow_sessions_user on public.flow_sessions (user_id);
create index if not exists idx_flow_sessions_date on public.flow_sessions (started_at);
create index if not exists idx_flow_sessions_type on public.flow_sessions (flow_type);
create index if not exists idx_flow_sessions_genuine on public.flow_sessions (is_genuine) where is_genuine = false;

-- ================================================================
-- 11. STATIC FLOW RESPONSES
-- ================================================================
create table if not exists public.static_flow_responses (
  id                     serial primary key,
  session_id             varchar(100) not null references public.flow_sessions (session_id) on delete cascade,
  user_id                uuid not null references public.profiles (id) on delete cascade,
  step_number            int not null,
  screen_type            varchar(30),
  -- answer fields
  selected_context       varchar(50),
  energy_value           int,
  primary_emotion        varchar(50),
  sub_emotion            varchar(50),
  body_zone              varchar(30),
  sensation_type         varchar(30),
  sensation_intensity    int,
  -- behavioral metrics
  response_time_ms       int,
  hesitation_time_ms     int,
  option_change_count    int default 0,
  rapid_tap_count        int default 0,
  idle_duration_ms       int default 0,
  completion_duration_ms int,
  interaction_depth_score int,
  has_text_input         boolean default false,
  text_length            int default 0,
  total_taps             int default 0,
  screen_rendered_at     timestamptz,
  first_interaction_at   timestamptz,
  response_submitted_at  timestamptz,
  created_at             timestamptz not null default now()
);

create index if not exists idx_static_responses_session on public.static_flow_responses (session_id);

-- ================================================================
-- 12. DYNAMIC FLOW RESPONSES
-- ================================================================
create table if not exists public.dynamic_flow_responses (
  id                     serial primary key,
  session_id             varchar(100) not null references public.flow_sessions (session_id) on delete cascade,
  user_id                uuid not null references public.profiles (id) on delete cascade,
  step_number            int not null,
  screen_type            varchar(30),
  -- answer fields
  selection              text,
  narrow_selection       text,
  narrow_title           text,
  replay_data            jsonb,
  story_start_option     varchar(50),
  consequence_data       jsonb,
  prediction             text,
  seen_before            varchar(20),
  reflection_text        text,
  insight_data           jsonb,
  challenge_accepted     boolean,
  challenge_data         jsonb,
  completed              boolean,
  -- behavioral metrics
  response_time_ms       int,
  hesitation_time_ms     int,
  option_change_count    int default 0,
  rapid_tap_count        int default 0,
  idle_duration_ms       int default 0,
  completion_duration_ms int,
  interaction_depth_score int,
  has_text_input         boolean default false,
  text_length            int default 0,
  total_taps             int default 0,
  screen_rendered_at     timestamptz,
  first_interaction_at   timestamptz,
  response_submitted_at  timestamptz,
  created_at             timestamptz not null default now()
);

create index if not exists idx_dynamic_responses_session on public.dynamic_flow_responses (session_id);

-- ================================================================
-- 13. BEHAVIORAL SIGNALS
-- ================================================================
create table if not exists public.behavioral_signals (
  id           serial primary key,
  session_id   varchar(100) not null references public.flow_sessions (session_id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  step_number  int not null,
  screen_name  varchar(50),
  signal_type  varchar(30) not null,
  signal_value int,
  severity     varchar(10) not null check (severity in ('low', 'medium', 'high')),
  created_at   timestamptz not null default now()
);

create index if not exists idx_behavioral_signals_session on public.behavioral_signals (session_id);
create index if not exists idx_behavioral_signals_severity on public.behavioral_signals (severity);

-- ================================================================
-- 14. CHALLENGES
-- ================================================================
create table if not exists public.challenges (
  id             serial primary key,
  session_id     varchar(100) not null references public.flow_sessions (session_id) on delete cascade,
  user_id        uuid not null references public.profiles (id) on delete cascade,
  accepted       boolean default false,
  reminder_set   boolean default false,
  challenge_text text,
  week_number    int,
  day_index      int,
  completed      boolean default false,
  completed_at   timestamptz,
  created_at     timestamptz not null default now()
);

-- ================================================================
-- 15. QUIZZES (Teacher creates)
-- ================================================================
create table if not exists public.quizzes (
  id                   serial primary key,
  teacher_id           uuid not null references public.profiles (id) on delete cascade,
  title                varchar(255) not null,
  subject              varchar(100),
  target_class         varchar(50),
  target_section       varchar(10),
  duration_seconds     int default 210,
  status               varchar(15) not null default 'draft'
                         check (status in ('draft', 'scheduled', 'live', 'completed')),
  go_live_immediately  boolean default false,
  scheduled_at         timestamptz,
  started_at           timestamptz,
  ended_at             timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index if not exists idx_quizzes_teacher on public.quizzes (teacher_id);
create index if not exists idx_quizzes_status  on public.quizzes (status);
create index if not exists idx_quizzes_class   on public.quizzes (target_class);

drop trigger if exists trg_quizzes_updated_at on public.quizzes;
create trigger trg_quizzes_updated_at
  before update on public.quizzes
  for each row execute function public.set_updated_at();

-- ================================================================
-- 16. QUIZ QUESTIONS
-- ================================================================
create table if not exists public.quiz_questions (
  id              serial primary key,
  quiz_id         int not null references public.quizzes (id) on delete cascade,
  question_number int not null,
  category        varchar(50),
  question_text   text not null,
  option_a        varchar(255) not null,
  option_b        varchar(255) not null,
  option_c        varchar(255) not null,
  option_d        varchar(255) not null,
  correct_option  int not null check (correct_option between 0 and 3),
  created_at      timestamptz not null default now()
);

create index if not exists idx_quiz_questions_quiz on public.quiz_questions (quiz_id);

-- ================================================================
-- 17. QUIZ SESSIONS (Student attempts)
-- ================================================================
create table if not exists public.quiz_sessions (
  id                     serial primary key,
  quiz_id                int not null references public.quizzes (id) on delete cascade,
  student_id             uuid not null references public.profiles (id) on delete cascade,
  score                  int not null default 0,
  total_questions        int not null,
  percentage             decimal(5,2),
  tier                   varchar(15),
  time_remaining_seconds int,
  started_at             timestamptz not null,
  completed_at           timestamptz,
  created_at             timestamptz not null default now(),
  unique (quiz_id, student_id)
);

create index if not exists idx_quiz_sessions_quiz    on public.quiz_sessions (quiz_id);
create index if not exists idx_quiz_sessions_student on public.quiz_sessions (student_id);

-- ================================================================
-- 18. QUIZ ANSWERS
-- ================================================================
create table if not exists public.quiz_answers (
  id               serial primary key,
  quiz_session_id  int not null references public.quiz_sessions (id) on delete cascade,
  question_id      int not null references public.quiz_questions (id) on delete cascade,
  selected_option  int check (selected_option between 0 and 3),
  is_correct       boolean not null default false,
  response_time_ms int,
  created_at       timestamptz not null default now()
);

create index if not exists idx_quiz_answers_session on public.quiz_answers (quiz_session_id);

-- ================================================================
-- 19. JOURNAL ENTRIES
-- ================================================================
create table if not exists public.journal_entries (
  id          serial primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  entry_type  varchar(20) not null,
  prompt_text text,
  content     text not null,
  word_count  int default 0,
  entry_date  date not null default current_date,
  time_of_day varchar(10) check (time_of_day in ('morning', 'evening', 'anytime')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists idx_journal_entries_user on public.journal_entries (user_id);
create index if not exists idx_journal_entries_date on public.journal_entries (entry_date);
create index if not exists idx_journal_entries_type on public.journal_entries (entry_type);

drop trigger if exists trg_journal_entries_updated_at on public.journal_entries;
create trigger trg_journal_entries_updated_at
  before update on public.journal_entries
  for each row execute function public.set_updated_at();

-- ================================================================
-- 20. JOURNAL TAGS
-- ================================================================
create table if not exists public.journal_tags (
  id         serial primary key,
  entry_id   int not null references public.journal_entries (id) on delete cascade,
  tag        varchar(30) not null,
  created_at timestamptz not null default now(),
  unique (entry_id, tag)
);

create index if not exists idx_journal_tags_entry on public.journal_tags (entry_id);

-- ================================================================
-- 21. ROW LEVEL SECURITY
-- ================================================================
alter table public.profiles              enable row level security;
alter table public.students              enable row level security;
alter table public.teachers              enable row level security;
alter table public.parents               enable row level security;
alter table public.parent_student        enable row level security;
alter table public.flow_sessions         enable row level security;
alter table public.static_flow_responses enable row level security;
alter table public.dynamic_flow_responses enable row level security;
alter table public.behavioral_signals    enable row level security;
alter table public.challenges            enable row level security;
alter table public.quizzes               enable row level security;
alter table public.quiz_questions        enable row level security;
alter table public.quiz_sessions         enable row level security;
alter table public.quiz_answers          enable row level security;
alter table public.journal_entries       enable row level security;
alter table public.journal_tags          enable row level security;

-- ────────── PROFILES ──────────
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select using (
    id = auth.uid()
    or public.current_role() in ('admin', 'teacher')
  );

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update using (id = auth.uid() or public.current_role() = 'admin')
  with check (id = auth.uid() or public.current_role() = 'admin');

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert with check (true);  -- trigger inserts on behalf of new users

-- ────────── STUDENTS ──────────
drop policy if exists students_select on public.students;
create policy students_select on public.students
  for select using (
    user_id = auth.uid()
    or public.current_role() in ('admin', 'teacher')
    or exists (
      select 1 from public.parent_student ps
      join public.parents p on p.id = ps.parent_id
      where ps.student_id = students.id and p.user_id = auth.uid()
    )
  );

drop policy if exists students_insert on public.students;
create policy students_insert on public.students
  for insert with check (user_id = auth.uid() or public.current_role() in ('admin', 'teacher'));

drop policy if exists students_update on public.students;
create policy students_update on public.students
  for update using (user_id = auth.uid() or public.current_role() in ('admin', 'teacher'));

-- ────────── TEACHERS ──────────
drop policy if exists teachers_select on public.teachers;
create policy teachers_select on public.teachers
  for select using (auth.uid() is not null);

drop policy if exists teachers_insert on public.teachers;
create policy teachers_insert on public.teachers
  for insert with check (user_id = auth.uid() or public.current_role() = 'admin');

drop policy if exists teachers_update on public.teachers;
create policy teachers_update on public.teachers
  for update using (user_id = auth.uid() or public.current_role() = 'admin');

-- ────────── PARENTS ──────────
drop policy if exists parents_select on public.parents;
create policy parents_select on public.parents
  for select using (
    user_id = auth.uid()
    or public.current_role() in ('admin', 'teacher')
  );

drop policy if exists parents_insert on public.parents;
create policy parents_insert on public.parents
  for insert with check (user_id = auth.uid() or public.current_role() = 'admin');

drop policy if exists parents_update on public.parents;
create policy parents_update on public.parents
  for update using (user_id = auth.uid() or public.current_role() = 'admin');

-- ────────── PARENT_STUDENT ──────────
drop policy if exists parent_student_select on public.parent_student;
create policy parent_student_select on public.parent_student
  for select using (
    public.current_role() in ('admin', 'teacher')
    or exists (select 1 from public.parents p where p.id = parent_id and p.user_id = auth.uid())
    or exists (select 1 from public.students s where s.id = student_id and s.user_id = auth.uid())
  );

-- ────────── FLOW SESSIONS ──────────
drop policy if exists flow_sessions_own on public.flow_sessions;
create policy flow_sessions_own on public.flow_sessions
  for all using (user_id = auth.uid() or public.current_role() in ('admin', 'teacher'))
  with check (user_id = auth.uid());

-- ────────── STATIC FLOW RESPONSES ──────────
drop policy if exists static_flow_responses_own on public.static_flow_responses;
create policy static_flow_responses_own on public.static_flow_responses
  for all using (user_id = auth.uid() or public.current_role() in ('admin', 'teacher'))
  with check (user_id = auth.uid());

-- ────────── DYNAMIC FLOW RESPONSES ──────────
drop policy if exists dynamic_flow_responses_own on public.dynamic_flow_responses;
create policy dynamic_flow_responses_own on public.dynamic_flow_responses
  for all using (user_id = auth.uid() or public.current_role() in ('admin', 'teacher'))
  with check (user_id = auth.uid());

-- ────────── BEHAVIORAL SIGNALS ──────────
drop policy if exists behavioral_signals_own on public.behavioral_signals;
create policy behavioral_signals_own on public.behavioral_signals
  for all using (user_id = auth.uid() or public.current_role() in ('admin', 'teacher'))
  with check (user_id = auth.uid());

-- ────────── CHALLENGES ──────────
drop policy if exists challenges_own on public.challenges;
create policy challenges_own on public.challenges
  for all using (user_id = auth.uid() or public.current_role() in ('admin', 'teacher'))
  with check (user_id = auth.uid());

-- ────────── QUIZZES ──────────
-- Teachers manage their own quizzes; everyone authenticated can read (to take quizzes)
drop policy if exists quizzes_select on public.quizzes;
create policy quizzes_select on public.quizzes
  for select using (auth.uid() is not null);

drop policy if exists quizzes_insert on public.quizzes;
create policy quizzes_insert on public.quizzes
  for insert with check (teacher_id = auth.uid() and public.current_role() = 'teacher');

drop policy if exists quizzes_update on public.quizzes;
create policy quizzes_update on public.quizzes
  for update using (teacher_id = auth.uid() or public.current_role() = 'admin');

drop policy if exists quizzes_delete on public.quizzes;
create policy quizzes_delete on public.quizzes
  for delete using (teacher_id = auth.uid() or public.current_role() = 'admin');

-- ────────── QUIZ QUESTIONS ──────────
drop policy if exists quiz_questions_select on public.quiz_questions;
create policy quiz_questions_select on public.quiz_questions
  for select using (auth.uid() is not null);

drop policy if exists quiz_questions_insert on public.quiz_questions;
create policy quiz_questions_insert on public.quiz_questions
  for insert with check (
    exists (select 1 from public.quizzes q where q.id = quiz_id and q.teacher_id = auth.uid())
  );

-- ────────── QUIZ SESSIONS ──────────
drop policy if exists quiz_sessions_own on public.quiz_sessions;
create policy quiz_sessions_own on public.quiz_sessions
  for all using (
    student_id = auth.uid()
    or public.current_role() in ('admin', 'teacher')
  )
  with check (student_id = auth.uid());

-- ────────── QUIZ ANSWERS ──────────
drop policy if exists quiz_answers_own on public.quiz_answers;
create policy quiz_answers_own on public.quiz_answers
  for all using (
    exists (select 1 from public.quiz_sessions qs where qs.id = quiz_session_id and qs.student_id = auth.uid())
    or public.current_role() in ('admin', 'teacher')
  )
  with check (
    exists (select 1 from public.quiz_sessions qs where qs.id = quiz_session_id and qs.student_id = auth.uid())
  );

-- ────────── JOURNAL ENTRIES ──────────
drop policy if exists journal_entries_own on public.journal_entries;
create policy journal_entries_own on public.journal_entries
  for all using (user_id = auth.uid() or public.current_role() in ('admin', 'teacher'))
  with check (user_id = auth.uid());

-- ────────── JOURNAL TAGS ──────────
drop policy if exists journal_tags_own on public.journal_tags;
create policy journal_tags_own on public.journal_tags
  for all using (
    exists (select 1 from public.journal_entries je where je.id = entry_id and je.user_id = auth.uid())
    or public.current_role() in ('admin', 'teacher')
  )
  with check (
    exists (select 1 from public.journal_entries je where je.id = entry_id and je.user_id = auth.uid())
  );

-- ============================================================
-- End of migration 001
-- ============================================================
