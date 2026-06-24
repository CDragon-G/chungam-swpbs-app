-- 009_reset_student_password.sql
-- 교사가 같은 학교 학생의 비밀번호를 임시 비번으로 초기화하는 기능.
-- 이메일 발송 의존 없이, 학교 현장에서 담임 교사가 즉시 처리할 수 있도록 함.
--
-- 보안: SECURITY DEFINER로 실행하되, 호출자가
--   1) 교사여야 하고
--   2) 대상 학생과 같은 학교여야 함
-- 을 함수 내부에서 검증한다.

create or replace function public.reset_student_password(
  p_profile_id uuid,
  p_new_password text
)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  caller_role text;
  caller_school uuid;
  target_user uuid;
  target_school uuid;
  target_role text;
begin
  -- 호출자(교사) 확인
  select role, school_id
    into caller_role, caller_school
  from profiles
  where user_id = auth.uid();

  if caller_role is null then
    raise exception '로그인 상태가 아닙니다.';
  end if;
  if caller_role <> 'teacher' then
    raise exception '교사만 학생 비밀번호를 초기화할 수 있어요.';
  end if;

  -- 대상 학생 확인
  select user_id, school_id, role
    into target_user, target_school, target_role
  from profiles
  where id = p_profile_id;

  if target_user is null then
    raise exception '학생을 찾을 수 없어요.';
  end if;
  if target_role <> 'student' then
    raise exception '학생 계정만 초기화할 수 있어요.';
  end if;
  if target_school is distinct from caller_school then
    raise exception '같은 학교 학생만 초기화할 수 있어요.';
  end if;
  if char_length(p_new_password) < 6 then
    raise exception '비밀번호는 6자 이상이어야 해요.';
  end if;

  -- 비밀번호 변경 (Supabase 호환 bcrypt 해시)
  update auth.users
  set encrypted_password = crypt(p_new_password, gen_salt('bf')),
      updated_at = now()
  where id = target_user;
end;
$$;

revoke all on function public.reset_student_password(uuid, text) from public;
grant execute on function public.reset_student_password(uuid, text) to authenticated;
