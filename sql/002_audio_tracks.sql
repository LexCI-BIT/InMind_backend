-- ============================================================
-- InMind App — Audio Space Schema
-- Migration 002: Audio tracks + playback progress
-- Target: PostgreSQL (Supabase)
-- ============================================================
-- Run this in the Supabase SQL Editor.
-- ============================================================

-- ----------------------------------------------------------------
-- 1. Audio category enum
-- ----------------------------------------------------------------
do $$ begin
  create type public.audio_category as enum ('audiobook', 'clip', 'focus');
exception when duplicate_object then null; end $$;

-- ----------------------------------------------------------------
-- 2. Audio tracks — metadata for every audio file
-- ----------------------------------------------------------------
create table if not exists public.audio_tracks (
  id               uuid primary key default gen_random_uuid(),
  title            text not null,
  description      text,
  category         public.audio_category not null default 'clip',
  sub_category     text,                       -- e.g. 'meditation', 'breathing', 'deep work'
  cover_url        text,                       -- Supabase Storage public URL for cover art
  audio_url        text not null,              -- Supabase Storage public URL for the audio file
  duration_seconds integer not null default 0, -- total length in seconds
  author           text,                       -- author / narrator
  is_published     boolean not null default true,
  sort_order       integer not null default 0, -- for manual ordering
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists idx_audio_tracks_category on public.audio_tracks (category);
create index if not exists idx_audio_tracks_published on public.audio_tracks (is_published);

drop trigger if exists trg_audio_tracks_updated_at on public.audio_tracks;
create trigger trg_audio_tracks_updated_at
  before update on public.audio_tracks
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------
-- 3. Playback progress — resume-where-you-left-off (per user)
-- ----------------------------------------------------------------
create table if not exists public.audio_playback_progress (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  track_id         uuid not null references public.audio_tracks (id) on delete cascade,
  position_seconds integer not null default 0,   -- where the user stopped
  completed        boolean not null default false,
  last_played_at   timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  unique (user_id, track_id)
);

create index if not exists idx_playback_user on public.audio_playback_progress (user_id);
create index if not exists idx_playback_track on public.audio_playback_progress (track_id);

drop trigger if exists trg_playback_updated_at on public.audio_playback_progress;
create trigger trg_playback_updated_at
  before update on public.audio_playback_progress
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------
-- 4. RLS policies
-- ----------------------------------------------------------------
alter table public.audio_tracks enable row level security;
alter table public.audio_playback_progress enable row level security;

-- Anyone authenticated can read published tracks
create policy "Anyone can read published audio tracks"
  on public.audio_tracks for select
  using (is_published = true);

-- Admins / service role can manage tracks (insert/update/delete)
create policy "Service role manages audio tracks"
  on public.audio_tracks for all
  using (auth.role() = 'service_role');

-- Users can only see/manage their own playback progress
create policy "Users read own playback progress"
  on public.audio_playback_progress for select
  using (auth.uid() = user_id);

create policy "Users upsert own playback progress"
  on public.audio_playback_progress for insert
  with check (auth.uid() = user_id);

create policy "Users update own playback progress"
  on public.audio_playback_progress for update
  using (auth.uid() = user_id);

-- ----------------------------------------------------------------
-- 5. Seed data — sample tracks for testing
-- ----------------------------------------------------------------
-- Replace the audio_url values with real Supabase Storage URLs
-- after uploading files to the 'audio-space' bucket.

insert into public.audio_tracks (title, description, category, sub_category, audio_url, duration_seconds, author, sort_order)
values
  ('2-Min Calm Breathing',   'A quick guided breathing exercise to reset your mind.',       'clip',      'breathing',   'https://example.com/placeholder.mp3', 120, 'InMind',           1),
  ('Morning Zen',            'Start your day with a 5-minute mindfulness meditation.',      'clip',      'meditation',  'https://example.com/placeholder.mp3', 300, 'InMind',           2),
  ('Ocean Mist',             'Gentle ocean sounds for instant calm.',                       'clip',      'calm',        'https://example.com/placeholder.mp3', 180, 'InMind',           3),
  ('Breath Release',         'Release tension through rhythmic breathing.',                 'clip',      'breathing',   'https://example.com/placeholder.mp3', 120, 'InMind',           4),
  ('Mental Reset',           'A quick 2-minute focus reset exercise.',                      'clip',      'focus',       'https://example.com/placeholder.mp3', 120, 'InMind',           5),
  ('Neural Sync Beats',      'Optimized frequencies for high cognitive output.',            'focus',     'deep work',   'https://example.com/placeholder.mp3', 2700, 'InMind Audio Lab',  6),
  ('Binaural Study Hub',     'Deep work session with binaural beats.',                      'focus',     'deep work',   'https://example.com/placeholder.mp3', 2700, 'InMind Audio Lab',  7),
  ('Lo-Fi Coding Ambience',  'Productivity ambience for long coding sessions.',             'focus',     'productivity','https://example.com/placeholder.mp3', 3600,'InMind Audio Lab',  8),
  ('Atomic Habits',          'Key insights from the bestselling book by James Clear.',      'audiobook', null,          'https://example.com/placeholder.mp3', 600, 'James Clear',       9),
  ('The Power of Now',       'Eckhart Tolle''s guide to spiritual enlightenment.',          'audiobook', null,          'https://example.com/placeholder.mp3', 720, 'Eckhart Tolle',    10),
  ('Ego is the Enemy',       'Ryan Holiday on the dangers of ego in our lives.',            'audiobook', null,          'https://example.com/placeholder.mp3', 600, 'Ryan Holiday',     11)
on conflict do nothing;
