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
