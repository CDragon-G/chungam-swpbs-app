-- 011_roster_delete.sql
-- 명단 개별 삭제 + 전체 삭제 (교사 전용).
-- 잘못 등록한 명단을 정리할 수 있도록 함. 이미 가입(claimed)된 항목 삭제 시
-- 해당 학생 계정은 유지되며 명단 행만 제거된다.

-- 개별 삭제
create or replace function public.delete_roster_entry(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  caller_role text;
  caller_school uuid;
  target_school uuid;
begin
  select role, school_id into caller_role, caller_school
  from profiles where user_id = auth.uid();
  if caller_role <> 'teacher' then raise exception '교사만 명단을 삭제할 수 있어요.'; end if;

  select school_id into target_school from student_roster where id = p_id;
  if target_school is null then raise exception '명단을 찾을 수 없어요.'; end if;
  if target_school is distinct from caller_school then
    raise exception '본인 학교 명단만 삭제할 수 있어요.';
  end if;

  delete from student_roster where id = p_id;
end;
$$;

revoke all on function public.delete_roster_entry(uuid) from public;
grant execute on function public.delete_roster_entry(uuid) to authenticated;

-- 학교 전체 명단 삭제
create or replace function public.clear_roster(p_school_id uuid)
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  caller_role text;
  caller_school uuid;
  n int;
begin
  select role, school_id into caller_role, caller_school
  from profiles where user_id = auth.uid();
  if caller_role <> 'teacher' then raise exception '교사만 명단을 삭제할 수 있어요.'; end if;
  if caller_school is distinct from p_school_id then
    raise exception '본인 학교 명단만 삭제할 수 있어요.';
  end if;

  with deleted as (
    delete from student_roster where school_id = p_school_id returning 1
  )
  select count(*) into n from deleted;
  return n;
end;
$$;

revoke all on function public.clear_roster(uuid) from public;
grant execute on function public.clear_roster(uuid) to authenticated;
