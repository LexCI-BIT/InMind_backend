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
