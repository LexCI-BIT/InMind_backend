-- ============================================================
-- InMind · audio_tracks — audio library (audiobooks / clips / focus)
-- ============================================================

do $$ begin
  if not exists (select 1 from pg_type where typname = 'audio_category') then
    create type public.audio_category as enum ('audiobook', 'clip', 'focus');
  end if;
end $$;

create table public.audio_tracks (
  id               uuid primary key default gen_random_uuid(),
  title            text not null,
  description      text,
  category         public.audio_category not null default 'clip',
  sub_category     text,
  cover_url        text,
  audio_url        text,
  duration_seconds int4 not null default 0,
  author           text,
  is_published     boolean not null default true,
  sort_order       int4 not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- Indexes
create index idx_audio_tracks_category on public.audio_tracks (category, sort_order)
  where is_published = true;

-- Trigger
create trigger trg_audio_tracks_updated
  before update on public.audio_tracks
  for each row execute function public.set_updated_at();

-- RLS
alter table public.audio_tracks enable row level security;

create policy audio_tracks_select on public.audio_tracks
  for select using (is_published = true or "current_role"() = 'admin'::user_role);

create policy audio_tracks_admin_write on public.audio_tracks
  for all using ("current_role"() = 'admin'::user_role)
  with check ("current_role"() = 'admin'::user_role);
