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
