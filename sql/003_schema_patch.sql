-- ============================================================
-- InMind App — Schema patch for static_flow_responses
-- Migration 003: Add missing columns used by the flows router
-- ============================================================
-- Run this in the Supabase SQL Editor AFTER 001_full_schema.sql.
-- ============================================================

-- Add the consolidated/aggregate columns the flows router expects
alter table public.static_flow_responses
  add column if not exists response_date       date,
  add column if not exists total_response_time_ms  int,
  add column if not exists min_response_time_ms    int,
  add column if not exists max_hesitation_ms       int,
  add column if not exists max_option_changes      int,
  add column if not exists max_idle_ms             int,
  add column if not exists avg_depth_score         real,
  add column if not exists engagement_score        real,
  add column if not exists engagement_label        varchar(30),
  add column if not exists is_genuine              boolean,
  add column if not exists flags                   jsonb;

-- Add unique constraint for the one-row-per-day upsert
-- (the router does: on_conflict="user_id,response_date")
do $$ begin
  alter table public.static_flow_responses
    add constraint uq_static_flow_user_date unique (user_id, response_date);
exception when duplicate_object then null; end $$;

-- Also add the same columns to flow_sessions if missing
alter table public.flow_sessions
  add column if not exists engagement_score  real,
  add column if not exists engagement_label  varchar(30),
  add column if not exists is_genuine        boolean,
  add column if not exists flags             jsonb;

-- The static flow router consolidates all steps into one row per day,
-- so step_number and screen_type are not always provided. Make them nullable.
alter table public.static_flow_responses
  alter column step_number drop not null,
  alter column screen_type drop not null;

-- session_id also needs to be nullable for the consolidated row format
alter table public.static_flow_responses
  alter column session_id drop not null;
