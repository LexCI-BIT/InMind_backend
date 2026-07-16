-- ============================================================================
-- InMind — FULL DATABASE SCHEMA (single file)
-- Generated from live project rvphxztkiucxvihduqcm on 2026-07-16
-- Run on a fresh Supabase project to recreate the entire database.
-- ============================================================================

-- ============================================================
-- InMind · 00 SETUP — types, functions, auth trigger, grants
-- Run this FIRST. Everything else depends on it.
-- ============================================================

-- ---------- Types ----------
-- Used by RLS policies via current_role(). The users.role column itself
-- is varchar (original schema), constrained to student/parent/teacher.
do $$ begin
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type public.user_role as enum ('student', 'parent', 'teacher', 'admin');
  end if;
end $$;

-- ---------- Functions ----------

-- Returns the role of the currently authenticated user.
-- SECURITY DEFINER so RLS policies can call it without recursion.
create or replace function public."current_role"()
returns user_role
language sql stable security definer
set search_path to 'public'
as $$
  select role::public.user_role from public.users where id = auth.uid();
$$;

-- Creates a public.users row automatically when someone signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path to 'public'
as $$
begin
  insert into public.users (id, role, full_name, email, phone_number)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'role', 'student'),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.email,
    new.raw_user_meta_data ->> 'phone_number'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Keeps updated_at fresh on every UPDATE (attached per-table).
create or replace function public.set_updated_at()
returns trigger
language plpgsql security invoker
set search_path to 'public'
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------- Auth trigger ----------
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Function grants (security hardening) ----------
revoke execute on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.handle_new_user() to supabase_auth_admin;

revoke execute on function public.set_updated_at() from public, anon, authenticated;

revoke execute on function public."current_role"() from public, anon;
grant execute on function public."current_role"() to authenticated;


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


-- ============================================================
-- InMind · flow_sessions — parent record for every check-in
-- ============================================================

create table public.flow_sessions (
  id                int4 generated by default as identity primary key,
  session_id        varchar not null,
  user_id           uuid not null references public.users(id) on delete cascade,
  flow_type         varchar not null,
  started_at        timestamptz not null,
  completed_at      timestamptz,
  total_duration_ms int4,
  total_steps       int4,
  steps_completed   int4,
  engagement_score  int4,
  engagement_label  varchar,
  is_genuine        boolean default true,
  flags             text[] default '{}'::text[],
  created_at        timestamptz default now(),

  constraint flow_sessions_session_id_key unique (session_id),
  constraint flow_sessions_flow_type_check check (flow_type in ('static', 'dynamic')),
  constraint flow_sessions_engagement_score_check
    check (engagement_score >= 0 and engagement_score <= 100)
);

-- Indexes
create index idx_flow_sessions_user on public.flow_sessions (user_id);
create index idx_flow_sessions_type on public.flow_sessions (flow_type);
create index idx_flow_sessions_date on public.flow_sessions (started_at);
create index idx_flow_sessions_genuine on public.flow_sessions (is_genuine)
  where is_genuine = false;

-- RLS
alter table public.flow_sessions enable row level security;

create policy flow_sessions_own on public.flow_sessions
  for all using (
    user_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  )
  with check (user_id = auth.uid());


-- ============================================================
-- InMind · static_flow_responses — daily static check-in
-- One row per session (and one per user per day).
-- ============================================================

create table public.static_flow_responses (
  id                     serial primary key,
  session_id             varchar not null references public.flow_sessions(session_id) on delete cascade,
  user_id                uuid not null references public.users(id) on delete cascade,
  selected_context       varchar,
  energy_value           int4,
  primary_emotion        varchar,
  sub_emotion            varchar,
  body_zone              varchar,
  sensation_type         varchar,
  sensation_intensity    int4,
  rapid_tap_count        int4 default 0,
  created_at             timestamptz not null default now(),
  response_date          date not null default current_date,
  total_response_time_ms int4,
  min_response_time_ms   int4,
  max_hesitation_ms      int4,
  max_option_changes     int4,
  max_idle_ms            int4,
  avg_depth_score        numeric,
  engagement_score       int4,
  engagement_label       varchar,
  is_genuine             boolean default true,
  flags                  text[] default '{}'::text[],

  constraint static_flow_responses_session_id_key unique (session_id),
  constraint uq_static_flow_user_date unique (user_id, response_date),
  constraint sfr_energy_range
    check (energy_value is null or (energy_value between 0 and 100)),
  constraint sfr_sensation_range
    check (sensation_intensity is null or (sensation_intensity between 0 and 100))
);

-- Indexes
create index idx_static_responses_session on public.static_flow_responses (session_id);
create index idx_static_responses_user_date on public.static_flow_responses (user_id, response_date desc);

-- RLS
alter table public.static_flow_responses enable row level security;

create policy static_flow_responses_own on public.static_flow_responses
  for all using (
    user_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  )
  with check (user_id = auth.uid());


-- ============================================================
-- InMind · dynamic_flow_responses — story-based flow, one row per step
-- ============================================================

create table public.dynamic_flow_responses (
  id                      serial primary key,
  session_id              varchar not null references public.flow_sessions(session_id) on delete cascade,
  user_id                 uuid not null references public.users(id) on delete cascade,
  step_number             int4 not null,
  screen_type             varchar not null,
  selection               varchar,
  narrow_selection        varchar,
  narrow_title            varchar,
  replay_data             jsonb,
  story_start_option      varchar,
  consequence_data        jsonb,
  prediction              varchar,
  seen_before             varchar,
  reflection_text         text,
  insight_data            jsonb,
  challenge_accepted      boolean,
  challenge_data          jsonb,
  completed               boolean,
  response_time_ms        int4,
  hesitation_time_ms      int4,
  option_change_count     int4 default 0,
  rapid_tap_count         int4 default 0,
  idle_duration_ms        int4 default 0,
  completion_duration_ms  int4,
  interaction_depth_score int4,
  has_text_input          boolean default false,
  text_length             int4 default 0,
  total_taps              int4 default 0,
  screen_rendered_at      timestamptz,
  first_interaction_at    timestamptz,
  response_submitted_at   timestamptz,
  created_at              timestamptz not null default now(),

  constraint dfr_step_range check (step_number between 0 and 10),
  constraint dfr_depth_range
    check (interaction_depth_score is null or (interaction_depth_score between 0 and 10))
);

-- Indexes
create index idx_dynamic_responses_session on public.dynamic_flow_responses (session_id);
create index idx_dynamic_responses_user on public.dynamic_flow_responses (user_id);

-- RLS
alter table public.dynamic_flow_responses enable row level security;

create policy dynamic_flow_responses_own on public.dynamic_flow_responses
  for all using (
    user_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  )
  with check (user_id = auth.uid());


-- ============================================================
-- InMind · behavioral_signals — granular authenticity signal log
-- ============================================================

create table public.behavioral_signals (
  id           serial primary key,
  session_id   varchar not null references public.flow_sessions(session_id) on delete cascade,
  user_id      uuid not null references public.users(id) on delete cascade,
  step_number  int4 not null,
  screen_name  varchar not null,
  signal_type  varchar not null,
  signal_value int4,
  severity     varchar not null,
  created_at   timestamptz default now(),

  constraint behavioral_signals_severity_check
    check (severity in ('low', 'medium', 'high'))
);

-- Indexes
create index idx_behavioral_signals_session on public.behavioral_signals (session_id);
create index idx_behavioral_signals_user on public.behavioral_signals (user_id, created_at desc);
create index idx_behavioral_signals_severity on public.behavioral_signals (severity);

-- RLS
alter table public.behavioral_signals enable row level security;

create policy behavioral_signals_own on public.behavioral_signals
  for all using (
    user_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  )
  with check (user_id = auth.uid());


-- ============================================================
-- InMind · challenges — post-flow suggested challenges
-- ============================================================

create table public.challenges (
  id             serial primary key,
  session_id     varchar not null references public.flow_sessions(session_id) on delete cascade,
  user_id        uuid not null references public.users(id) on delete cascade,
  accepted       boolean default false,
  reminder_set   boolean default false,
  challenge_text text,
  week_number    int4,
  day_index      int4,
  completed      boolean default false,
  completed_at   timestamptz,
  created_at     timestamptz not null default now()
);

-- Indexes
create index idx_challenges_user on public.challenges (user_id, completed);
create index idx_challenges_session on public.challenges (session_id);

-- RLS
alter table public.challenges enable row level security;

create policy challenges_own on public.challenges
  for all using (
    user_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  )
  with check (user_id = auth.uid());


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


-- ============================================================
-- InMind · quiz_questions — MCQ questions (4 options, 0–3 correct index)
-- ============================================================

create table public.quiz_questions (
  id              serial primary key,
  quiz_id         int4 not null references public.quizzes(id) on delete cascade,
  question_number int4 not null,
  category        varchar,
  question_text   text not null,
  option_a        varchar not null,
  option_b        varchar not null,
  option_c        varchar not null,
  option_d        varchar not null,
  correct_option  int4 not null,
  created_at      timestamptz not null default now(),

  constraint quiz_questions_correct_option_check
    check (correct_option between 0 and 3)
);

-- Indexes
create index idx_quiz_questions_quiz on public.quiz_questions (quiz_id);

-- RLS
alter table public.quiz_questions enable row level security;

create policy quiz_questions_select on public.quiz_questions
  for select using (auth.uid() is not null);

create policy quiz_questions_insert on public.quiz_questions
  for insert with check (
    exists (
      select 1 from public.quizzes q
      where q.id = quiz_questions.quiz_id and q.teacher_id = auth.uid()
    )
  );


-- ============================================================
-- InMind · quiz_sessions — a student's attempt at a quiz
-- ============================================================

create table public.quiz_sessions (
  id                     serial primary key,
  quiz_id                int4 not null references public.quizzes(id) on delete cascade,
  student_id             uuid not null references public.users(id) on delete cascade,
  score                  int4 not null default 0,
  total_questions        int4 not null,
  percentage             numeric,
  tier                   varchar,
  time_remaining_seconds int4,
  started_at             timestamptz not null,
  completed_at           timestamptz,
  created_at             timestamptz not null default now(),

  constraint quiz_sessions_quiz_id_student_id_key unique (quiz_id, student_id)
);

-- Indexes
create index idx_quiz_sessions_quiz on public.quiz_sessions (quiz_id);
create index idx_quiz_sessions_student on public.quiz_sessions (student_id);

-- RLS
alter table public.quiz_sessions enable row level security;

create policy quiz_sessions_own on public.quiz_sessions
  for all using (
    student_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  )
  with check (student_id = auth.uid());


-- ============================================================
-- InMind · quiz_answers — per-question answers within a session
-- ============================================================

create table public.quiz_answers (
  id               serial primary key,
  quiz_session_id  int4 not null references public.quiz_sessions(id) on delete cascade,
  question_id      int4 not null references public.quiz_questions(id) on delete cascade,
  selected_option  int4,
  is_correct       boolean not null default false,
  response_time_ms int4,
  created_at       timestamptz not null default now(),

  constraint quiz_answers_selected_option_check
    check (selected_option between 0 and 3)
);

-- Indexes
create index idx_quiz_answers_session on public.quiz_answers (quiz_session_id);
create index idx_quiz_answers_question on public.quiz_answers (question_id);

-- RLS
alter table public.quiz_answers enable row level security;

create policy quiz_answers_own on public.quiz_answers
  for all using (
    exists (
      select 1 from public.quiz_sessions qs
      where qs.id = quiz_answers.quiz_session_id and qs.student_id = auth.uid()
    )
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  )
  with check (
    exists (
      select 1 from public.quiz_sessions qs
      where qs.id = quiz_answers.quiz_session_id and qs.student_id = auth.uid()
    )
  );


-- ============================================================
-- InMind · journal_entries — prompted journaling
-- ============================================================

create table public.journal_entries (
  id          serial primary key,
  user_id     uuid not null references public.users(id) on delete cascade,
  entry_type  varchar not null,
  prompt_text text,
  content     text not null,
  word_count  int4 default 0,
  entry_date  date not null default current_date,
  time_of_day varchar,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint journal_entries_time_of_day_check
    check (time_of_day in ('morning', 'evening', 'anytime'))
);

-- Indexes
create index idx_journal_entries_user on public.journal_entries (user_id);
create index idx_journal_entries_date on public.journal_entries (entry_date);
create index idx_journal_entries_type on public.journal_entries (entry_type);
create index idx_journal_entries_user_date on public.journal_entries (user_id, entry_date desc);

-- Trigger
create trigger trg_journal_updated
  before update on public.journal_entries
  for each row execute function public.set_updated_at();

-- RLS
alter table public.journal_entries enable row level security;

create policy journal_entries_own on public.journal_entries
  for all using (
    user_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  )
  with check (user_id = auth.uid());


-- ============================================================
-- InMind · journal_tags — tags on journal entries
-- ============================================================

create table public.journal_tags (
  id         serial primary key,
  entry_id   int4 not null references public.journal_entries(id) on delete cascade,
  tag        varchar not null,
  created_at timestamptz not null default now(),

  constraint journal_tags_entry_id_tag_key unique (entry_id, tag)
);

-- Indexes
create index idx_journal_tags_entry on public.journal_tags (entry_id);
create index idx_journal_tags_tag on public.journal_tags (tag);

-- RLS
alter table public.journal_tags enable row level security;

create policy journal_tags_own on public.journal_tags
  for all using (
    exists (
      select 1 from public.journal_entries je
      where je.id = journal_tags.entry_id and je.user_id = auth.uid()
    )
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  )
  with check (
    exists (
      select 1 from public.journal_entries je
      where je.id = journal_tags.entry_id and je.user_id = auth.uid()
    )
  );


-- ============================================================
-- InMind · thoughts — class thought feed (supports anonymous posts)
-- ============================================================

create table public.thoughts (
  id           serial primary key,
  author_id    uuid not null references public.users(id) on delete cascade,
  author_name  varchar,
  class_name   varchar,
  content      text not null,
  is_anonymous boolean not null default false,
  created_at   timestamptz not null default now()
);

-- Indexes
create index idx_thoughts_author on public.thoughts (author_id);
create index idx_thoughts_created on public.thoughts (created_at desc);

-- RLS
alter table public.thoughts enable row level security;

create policy thoughts_select on public.thoughts
  for select using (auth.uid() is not null);

create policy thoughts_insert on public.thoughts
  for insert with check (author_id = auth.uid());

create policy thoughts_update on public.thoughts
  for update using (author_id = auth.uid() or "current_role"() = 'admin'::user_role);

create policy thoughts_delete on public.thoughts
  for delete using (
    author_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  );


-- ============================================================
-- InMind · audio_tracks — audio library (audiobooks / clips / focus)
-- ============================================================

do $$ begin
  if not exists (select 1 from pg_type where typname = 'audio_category') then
    create type public.audio_category as enum ('audiobook', 'clip', 'focus');
  end if;
end $$;

create table public.audio_tracks (
  id               uuid primary key default gen_random_uuid(),
  title            text not null,
  description      text,
  category         public.audio_category not null default 'clip',
  sub_category     text,
  cover_url        text,
  audio_url        text,
  duration_seconds int4 not null default 0,
  author           text,
  is_published     boolean not null default true,
  sort_order       int4 not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- Indexes
create index idx_audio_tracks_category on public.audio_tracks (category, sort_order)
  where is_published = true;

-- Trigger
create trigger trg_audio_tracks_updated
  before update on public.audio_tracks
  for each row execute function public.set_updated_at();

-- RLS
alter table public.audio_tracks enable row level security;

create policy audio_tracks_select on public.audio_tracks
  for select using (is_published = true or "current_role"() = 'admin'::user_role);

create policy audio_tracks_admin_write on public.audio_tracks
  for all using ("current_role"() = 'admin'::user_role)
  with check ("current_role"() = 'admin'::user_role);


-- ============================================================
-- InMind · audio_playback_progress — per-user listening position
-- ============================================================

create table public.audio_playback_progress (
  id               uuid primary key default gen_random_uuid(),
  track_id         uuid not null references public.audio_tracks(id) on delete cascade,
  user_id          uuid not null references public.users(id) on delete cascade,
  position_seconds int4 not null default 0,
  completed        boolean not null default false,
  last_played_at   timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint audio_playback_progress_user_id_track_id_key unique (user_id, track_id)
);

-- Indexes
create index idx_audio_progress_user on public.audio_playback_progress (user_id, last_played_at desc);

-- Trigger
create trigger trg_audio_progress_updated
  before update on public.audio_playback_progress
  for each row execute function public.set_updated_at();

-- RLS
alter table public.audio_playback_progress enable row level security;

create policy audio_progress_own on public.audio_playback_progress
  for all using (user_id = auth.uid() or "current_role"() = 'admin'::user_role)
  with check (user_id = auth.uid());


