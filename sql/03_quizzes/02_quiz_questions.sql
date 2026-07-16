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
