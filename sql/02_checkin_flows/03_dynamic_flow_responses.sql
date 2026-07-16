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
