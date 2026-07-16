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
