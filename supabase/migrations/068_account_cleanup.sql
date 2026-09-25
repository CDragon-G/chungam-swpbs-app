-- 068_account_cleanup.sql
-- 계정 삭제가 제대로 되도록 고치고, 테스트 학생을 지울 수 있게 한다.
--
-- ─── 고친 것 ───────────────────────────────────────────────
-- 1) 선생님 계정 삭제(delete_teacher)가 항상 실패했다.
--    profiles 에 없는 name 컬럼을 읽고 있었다. (0.29.0 에서 고친 화면 오류와 같은 원인)
--
-- 2) 이름을 고쳐도 삭제가 거부될 선생님이 많았다.
--    · 강화물 교환을 한 번이라도 '지급 처리' 한 선생님
--      → point_exchanges.fulfilled_by 에 삭제 규칙이 없어서 거부
--    · K-ODR 을 한 번이라도 기록한 선생님
--      → kodr_records.teacher_id 가 '비우면 안 됨' 인데 '교사 삭제 시 비움' 이라 충돌
--
-- 3) 선생님을 지우면 그 선생님이 보낸 칭찬이 전부 사라졌다.
--    praise.teacher_id 가 '교사 삭제 시 함께 삭제' 였다. 삭제 확인 창에는
--    "남기신 칭찬과 기록은 그대로 있습니다" 라고 적혀 있었는데 사실이 아니었다.
--    이제 칭찬은 남고 보낸 선생님만 비워진다 (학생 화면에는 '선생님' 으로 보인다).
--
-- 4) 학생이 스스로 탈퇴하면 명렬표 자리가 '가입됨' 으로 잠긴 채 남았다.
--    다시 가입하려 해도 "이미 가입에 사용된 학번이에요" 가 떴다.
--
-- ─── 새로 만든 것 ─────────────────────────────────────────
-- 5) 관리자 선생님이 학생 계정을 지울 수 있다 (delete_student).
--    테스트로 만든 계정(tes1 같은 것)을 정리하는 용도.
--    · K-ODR 이나 학맞통 안건이 있는 학생은 지우지 않는다 — 공식 기록이 함께 사라지기 때문
--    · 명렬표 자리는 다시 가입할 수 있게 풀어 준다
--    · 전학·졸업한 실제 학생은 지우지 말고 명렬표 진급 처리(055)로 정리한다

-- ═══════════ 1) 참조 규칙 바로잡기 ═══════════

--   기존 참조 제약의 이름을 짐작하지 않고, 실제로 걸려 있는 것을 찾아 지운 뒤 새로 건다.
--   (이름이 다르면 옛 제약이 남아 계속 삭제를 막기 때문)
do $$
declare c record;
begin
  for c in
    select con.conname, rel.relname
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_attribute att
        on att.attrelid = con.conrelid and att.attnum = any(con.conkey)
     where con.contype = 'f'
       and rel.relnamespace = 'public'::regnamespace
       and ((rel.relname = 'praise'            and att.attname = 'teacher_id')
         or (rel.relname = 'point_exchanges'   and att.attname = 'fulfilled_by')
         or (rel.relname = 'teacher_exchanges' and att.attname = 'fulfilled_by'))
  loop
    execute format('alter table public.%I drop constraint %I', c.relname, c.conname);
  end loop;
end $$;

-- 강화물 지급 처리한 선생님 — 선생님이 떠나도 교환 기록은 남는다
alter table point_exchanges add constraint point_exchanges_fulfilled_by_fkey
  foreign key (fulfilled_by) references auth.users(id) on delete set null;
alter table teacher_exchanges add constraint teacher_exchanges_fulfilled_by_fkey
  foreign key (fulfilled_by) references auth.users(id) on delete set null;

-- K-ODR 을 쓴 선생님 — 선생님이 떠나도 K-ODR 은 남는다 (작성자만 비워진다)
alter table kodr_records alter column teacher_id drop not null;

-- 칭찬을 보낸 선생님 — 선생님이 떠나도 학생이 받은 칭찬은 남는다
alter table praise alter column teacher_id drop not null;
alter table praise add constraint praise_teacher_id_fkey
  foreign key (teacher_id) references auth.users(id) on delete set null;

-- ═══════════ 2) 선생님 계정 삭제 ═══════════
create or replace function delete_teacher(p_profile_id uuid)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid; v_target_user uuid; v_target_school uuid;
  v_target_role text; v_target_teacher_role text; v_name text;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 삭제할 수 있어요');
  end if;

  select school_id into v_school from profiles where user_id = auth.uid();
  -- profiles 에는 name 컬럼이 없다. 이름은 nickname.
  select user_id, school_id, role, teacher_role, nickname
    into v_target_user, v_target_school, v_target_role, v_target_teacher_role, v_name
    from profiles where id = p_profile_id;

  if v_target_user is null then
    return json_build_object('ok', false, 'error', '선생님을 찾을 수 없어요');
  end if;
  if v_target_school is distinct from v_school then
    return json_build_object('ok', false, 'error', '우리 학교 선생님만 삭제할 수 있어요');
  end if;
  if v_target_role <> 'teacher' then
    return json_build_object('ok', false, 'error', '교사 계정이 아니에요');
  end if;
  if v_target_user = auth.uid() then
    return json_build_object('ok', false, 'error', '본인 계정은 삭제할 수 없어요');
  end if;
  -- 관리자가 한 명뿐인데 그 관리자를 지우면 학교가 잠긴다
  if v_target_teacher_role = 'admin' and (
       select count(*) from profiles
        where school_id = v_school and role = 'teacher' and teacher_role = 'admin') <= 1 then
    return json_build_object('ok', false, 'error', '마지막 관리자 선생님은 삭제할 수 없어요');
  end if;

  delete from auth.users where id = v_target_user;   -- profiles 는 cascade
  return json_build_object('ok', true, 'name', v_name);
end $$;
revoke all on function delete_teacher(uuid) from public;
grant execute on function delete_teacher(uuid) to authenticated;

-- ═══════════ 3) 학생 계정 삭제 (관리자) ═══════════
create or replace function delete_student(p_profile_id uuid)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid;
  t profiles;
  v_kodr int; v_ref int;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 삭제할 수 있어요');
  end if;
  select school_id into v_school from profiles where user_id = auth.uid();

  select * into t from profiles where id = p_profile_id;
  if t.id is null then
    return json_build_object('ok', false, 'error', '학생을 찾을 수 없어요');
  end if;
  if t.school_id is distinct from v_school then
    return json_build_object('ok', false, 'error', '우리 학교 학생만 삭제할 수 있어요');
  end if;
  if t.role <> 'student' then
    return json_build_object('ok', false, 'error', '학생 계정이 아니에요');
  end if;

  -- K-ODR · 학맞통 안건은 공식 기록이다. 계정을 지우면 함께 사라지므로 막는다.
  select count(*) into v_kodr from kodr_records where student_id = t.user_id;
  select count(*) into v_ref from support_referrals where student_id = t.user_id;
  if v_kodr > 0 or v_ref > 0 then
    return json_build_object('ok', false, 'error',
      'K-ODR 이나 학맞통 기록이 있는 학생은 삭제할 수 없어요. '
      || '공식 기록이 함께 지워지기 때문이에요. '
      || '전학·졸업은 학생 명단의 진급 처리로 정리해주세요.');
  end if;

  -- 명렬표 자리를 다시 가입할 수 있게 풀어 준다
  update student_roster
     set claimed = false, claimed_by = null
   where claimed_by = t.user_id;

  delete from auth.users where id = t.user_id;   -- 점검·포인트·뱃지 등은 cascade
  return json_build_object('ok', true, 'name', t.nickname);
end $$;
revoke all on function delete_student(uuid) from public;
grant execute on function delete_student(uuid) to authenticated;

-- ═══════════ 4) 본인 탈퇴 — 명렬표 자리도 풀어 준다 ═══════════
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception '로그인 상태가 아닙니다.';
  end if;

  -- 학생이면 명렬표 자리를 풀어 다시 가입할 수 있게 한다.
  -- (예전에는 자리가 '가입됨' 으로 남아 같은 학번으로 다시 가입할 수 없었다)
  update student_roster
     set claimed = false, claimed_by = null
   where claimed_by = uid;

  -- auth.users 삭제 → ON DELETE CASCADE로 관련 데이터 삭제
  delete from auth.users where id = uid;
end;
$$;
revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- ═══════════ 5) 이미 잠긴 자리 풀기 ═══════════
--   예전에 탈퇴한 학생의 자리는 claimed = true 인데 claimed_by 가 비어 있다.
update student_roster
   set claimed = false
 where claimed = true and claimed_by is null;

-- ═══════════ 확인 ═══════════
--   select conname, confdeltype from pg_constraint
--    where conname in ('praise_teacher_id_fkey', 'point_exchanges_fulfilled_by_fkey');
--   -- confdeltype 'n' = set null
