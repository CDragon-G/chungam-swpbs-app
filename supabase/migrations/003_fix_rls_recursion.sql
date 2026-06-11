-- Fix infinite recursion in RLS policies.
--
-- Problem: helper functions current_profile_role() / current_profile_school()
-- query the `profiles` table. The profiles SELECT policy `profiles_teacher_view`
-- itself calls these helpers, causing each row check to recurse infinitely.
--
-- Fix: mark the helpers as SECURITY DEFINER so they run with the function
-- owner's privileges and bypass RLS on the inner SELECT.

create or replace function current_profile_role()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select role from profiles where user_id = auth.uid() limit 1;
$$;

create or replace function current_profile_school()
returns uuid
language sql
stable
security definer
set search_path = public, auth
as $$
  select school_id from profiles where user_id = auth.uid() limit 1;
$$;

create or replace function current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = public, auth
as $$
  select id from profiles where user_id = auth.uid() limit 1;
$$;

-- Lock down EXECUTE so only authenticated/anon can call them
-- (default already permissive but being explicit).
grant execute on function current_profile_role() to anon, authenticated;
grant execute on function current_profile_school() to anon, authenticated;
grant execute on function current_profile_id() to anon, authenticated;
