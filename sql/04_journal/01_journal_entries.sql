-- ============================================================
-- InMind · journal_entries — prompted journaling
-- ============================================================

create table public.journal_entries (
  id          serial primary key,
  user_id     uuid not null references public.users(id) on delete cascade,
  entry_type  varchar not null,
  prompt_text text,
  content     text not null,
  word_count  int4 default 0,
  entry_date  date not null default current_date,
  time_of_day varchar,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint journal_entries_time_of_day_check
    check (time_of_day in ('morning', 'evening', 'anytime'))
);

-- Indexes
create index idx_journal_entries_user on public.journal_entries (user_id);
create index idx_journal_entries_date on public.journal_entries (entry_date);
create index idx_journal_entries_type on public.journal_entries (entry_type);
create index idx_journal_entries_user_date on public.journal_entries (user_id, entry_date desc);

-- Trigger
create trigger trg_journal_updated
  before update on public.journal_entries
  for each row execute function public.set_updated_at();

-- RLS
alter table public.journal_entries enable row level security;

create policy journal_entries_own on public.journal_entries
  for all using (
    user_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  )
  with check (user_id = auth.uid());
