-- 029_find_account.sql
-- 계정 찾기 지원.
--   · get_student_email: 같은 학교 교사가 학생의 로그인 이메일을 조회
--     (이메일을 잊은 학생 지원 — 교사 인증 + 소속 검증을 서버에서 강제)
--   · 비밀번호 재설정(이메일 OTP)은 Supabase Auth 기본 기능 사용:
--     Dashboard → Authentication → Email Templates → "Reset Password" 본문에
--     {{ .Token }} (6자리 코드)가 포함되어야 앱의 코드 입력 방식이 동작한다.

create or replace function public.get_student_email(p_profile_id uuid)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
begin
  if current_profile_role() <> 'teacher' then
    raise exception '교사만 조회할 수 있어요.';
  end if;
  select u.email::text into v_email
  from profiles p
  join auth.users u on u.id = p.user_id
  where p.id = p_profile_id
    and p.school_id = current_profile_school()
    and p.role = 'student';
  if v_email is null then
    raise exception '학생을 찾을 수 없어요.';
  end if;
  return v_email;
end $$;
revoke all on function public.get_student_email(uuid) from public;
grant execute on function public.get_student_email(uuid) to authenticated;
