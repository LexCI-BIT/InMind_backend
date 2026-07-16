-- ============================================================
-- InMind · thoughts — class thought feed (supports anonymous posts)
-- ============================================================

create table public.thoughts (
  id           serial primary key,
  author_id    uuid not null references public.users(id) on delete cascade,
  author_name  varchar,
  class_name   varchar,
  content      text not null,
  is_anonymous boolean not null default false,
  created_at   timestamptz not null default now()
);

-- Indexes
create index idx_thoughts_author on public.thoughts (author_id);
create index idx_thoughts_created on public.thoughts (created_at desc);

-- RLS
alter table public.thoughts enable row level security;

create policy thoughts_select on public.thoughts
  for select using (auth.uid() is not null);

create policy thoughts_insert on public.thoughts
  for insert with check (author_id = auth.uid());

create policy thoughts_update on public.thoughts
  for update using (author_id = auth.uid() or "current_role"() = 'admin'::user_role);

create policy thoughts_delete on public.thoughts
  for delete using (
    author_id = auth.uid()
    or "current_role"() = any (array['admin'::user_role, 'teacher'::user_role])
  );
