-- 006_teacher_roles.sql
-- Teacher permission tiers: admin (SWPBS leadership) vs regular

-- 1. Add teacher_role column
alter table profiles
  add column if not exists teacher_role text
  check (teacher_role is null or teacher_role in ('admin', 'regular'));

-- 2. Backfill existing teachers as admin (they're school creators)
update profiles
  set teacher_role = 'admin'
  where role = 'teacher' and teacher_role is null;

-- 3. Helper function
create or replace function is_admin_teacher()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(
    (select role = 'teacher' and teacher_role = 'admin'
     from profiles where user_id = auth.uid() limit 1),
    false
  );
$$;
grant execute on function is_admin_teacher() to authenticated;

-- 4. Tighten policies — admin only for write operations
-- (Read access stays for all teachers in the school)

-- school_rules: admin only for write
drop policy if exists school_rules_teacher_write on school_rules;
create policy school_rules_admin_write on school_rules
  for all using (
    is_admin_teacher() and school_id = current_profile_school()
  ) with check (
    is_admin_teacher() and school_id = current_profile_school()
  );

-- point_store_items: admin only for write
drop policy if exists psi_teacher_write on point_store_items;
create policy psi_admin_write on point_store_items
  for all using (
    is_admin_teacher() and school_id = current_profile_school()
  ) with check (
    is_admin_teacher() and school_id = current_profile_school()
  );

-- point_exchanges: regular teachers can READ, admin can manage
drop policy if exists pe_teacher_manage on point_exchanges;
create policy pe_admin_manage on point_exchanges
  for all using (
    is_admin_teacher() and school_id = current_profile_school()
  ) with check (
    is_admin_teacher() and school_id = current_profile_school()
  );

drop policy if exists pe_teacher_read on point_exchanges;
create policy pe_teacher_read on point_exchanges
  for select using (
    current_profile_role() = 'teacher'
    and school_id = current_profile_school()
  );

-- announcements: admin only write
drop policy if exists announcements_teacher_write on announcements;
create policy announcements_admin_write on announcements
  for all using (
    is_admin_teacher() and school_id = current_profile_school()
  ) with check (
    is_admin_teacher() and school_id = current_profile_school()
  );

-- schools: admin only update
drop policy if exists schools_update on schools;
create policy schools_admin_update on schools
  for update using (
    is_admin_teacher() and id = current_profile_school()
  );

-- profiles: admin can update teacher_role of same-school teachers
drop policy if exists profiles_admin_role_update on profiles;
create policy profiles_admin_role_update on profiles
  for update using (
    is_admin_teacher()
    and school_id = current_profile_school()
    and role = 'teacher'
  ) with check (
    is_admin_teacher()
    and school_id = current_profile_school()
    and role = 'teacher'
  );

-- 5. Function to update a teacher's role (admin only, with safety check)
create or replace function set_teacher_role(
  p_profile_id uuid,
  p_new_role text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_school_id uuid := current_profile_school();
  v_admin_count int;
begin
  if not is_admin_teacher() then
    raise exception '관리자 권한이 필요합니다.';
  end if;
  if p_new_role not in ('admin', 'regular') then
    raise exception '잘못된 권한 값입니다.';
  end if;

  -- Safety: never let school end with zero admins
  if p_new_role = 'regular' then
    select count(*) into v_admin_count
    from profiles
    where school_id = v_school_id
      and role = 'teacher'
      and teacher_role = 'admin'
      and id != p_profile_id;
    if v_admin_count < 1 then
      raise exception '최소 한 명의 관리자가 필요합니다. 다른 교사를 먼저 관리자로 임명해주세요.';
    end if;
  end if;

  update profiles
    set teacher_role = p_new_role
    where id = p_profile_id
      and school_id = v_school_id
      and role = 'teacher';

  if not found then
    raise exception '교사를 찾을 수 없습니다.';
  end if;
end;
$$;
grant execute on function set_teacher_role(uuid, text) to authenticated;
