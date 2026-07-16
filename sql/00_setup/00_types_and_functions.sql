-- ============================================================
-- InMind · 00 SETUP — types, functions, auth trigger, grants
-- Run this FIRST. Everything else depends on it.
-- ============================================================

-- ---------- Types ----------
-- Used by RLS policies via current_role(). The users.role column itself
-- is varchar (original schema), constrained to student/parent/teacher.
do $$ begin
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type public.user_role as enum ('student', 'parent', 'teacher', 'admin');
  end if;
end $$;

-- ---------- Functions ----------

-- Returns the role of the currently authenticated user.
-- SECURITY DEFINER so RLS policies can call it without recursion.
create or replace function public."current_role"()
returns user_role
language sql stable security definer
set search_path to 'public'
as $$
  select role::public.user_role from public.users where id = auth.uid();
$$;

-- Creates a public.users row automatically when someone signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path to 'public'
as $$
begin
  insert into public.users (id, role, full_name, email, phone_number)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'role', 'student'),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.email,
    new.raw_user_meta_data ->> 'phone_number'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Keeps updated_at fresh on every UPDATE (attached per-table).
create or replace function public.set_updated_at()
returns trigger
language plpgsql security invoker
set search_path to 'public'
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------- Auth trigger ----------
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Function grants (security hardening) ----------
revoke execute on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.handle_new_user() to supabase_auth_admin;

revoke execute on function public.set_updated_at() from public, anon, authenticated;

revoke execute on function public."current_role"() from public, anon;
grant execute on function public."current_role"() to authenticated;
