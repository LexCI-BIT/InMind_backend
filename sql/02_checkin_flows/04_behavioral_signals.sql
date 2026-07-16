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
