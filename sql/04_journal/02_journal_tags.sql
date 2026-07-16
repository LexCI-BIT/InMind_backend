-- ============================================================
-- InMind · journal_tags — tags on journal entries
-- ============================================================

create table public.journal_tags (
  id         serial primary key,
  entry_id   int4 not null references public.journal_entries(id) on delete cascade,
  tag        varchar not null,
  created_at timestamptz not null default now(),

  constraint journal_tags_entry_id_tag_key unique (entry_id, tag)
);

-- Indexes
create index idx_journal_tags_entry on public.journal_tags (entry_id);
create index idx_journal_tags_tag on public.journal_tags (tag);

-- RLS
alter table public.journal_tags enable row level security;

create policy journal_tags_own on public.journal_tags
  for all using (
    exists (
      select 1 from public.journal_entries je
      where je.id = journal_tags.entry_id and je.user_id = auth.uid()
    )
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  )
  with check (
    exists (
      select 1 from public.journal_entries je
      where je.id = journal_tags.entry_id and je.user_id = auth.uid()
    )
  );
