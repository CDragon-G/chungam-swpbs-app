-- 007_delete_account.sql
-- Apple App Store Guideline 5.1.1(v) 대응: 앱 내 계정 삭제 기능
-- 사용자가 본인 계정과 관련 데이터를 완전히 삭제할 수 있는 RPC 함수.
--
-- 모든 사용자 데이터 테이블(profiles, daily_checkins, user_badges,
-- point_transactions, point_exchanges)은 user_id가 auth.users(id)를
-- ON DELETE CASCADE로 참조하므로, auth.users에서 사용자를 삭제하면
-- 관련 데이터가 자동으로 모두 삭제됨.
--
-- SECURITY DEFINER로 실행되어 auth.users 삭제 권한을 가짐.

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

  -- auth.users 삭제 → ON DELETE CASCADE로 모든 관련 데이터 자동 삭제
  delete from auth.users where id = uid;
end;
$$;

-- 로그인한 사용자만 본인 계정 삭제 호출 가능
revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
