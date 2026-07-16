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
