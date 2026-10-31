-- 074_point_amounts_for_all.sql
-- 앱 화면이 '포인트 설정' 값을 그대로 보여주게 한다.
--
-- 무엇이 문제였나
--   064 부터 지급은 학교가 정한 금액(school_point_rules)을 그때그때 읽는다.
--   그런데 앱 화면 아홉 곳에 금액이 숫자로 박혀 있었다
--   ('각 +50P', '매일 자기점검 1회 = +100P', '개근 보너스 +500P' …).
--   칭찬을 100P 로 바꿔도 화면은 계속 50P 라고 말해서 "반영이 안 된다" 로 보였다.
--
--   금액 목록(point_rules)은 선생님만 볼 수 있어서 학생 화면은 읽을 수 없었다.
--   금액은 숨길 정보가 아니므로 같은 학교 사람이면 누구나 읽게 한다.
--
-- 바뀌는 것
--   point_amounts() — 우리 학교의 지금 금액 다섯 가지를 돌려준다 (학생 · 선생님 모두).
--   쓰기(set_point_rule)는 그대로 관리자 선생님만.

create or replace function point_amounts()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
begin
  if v_school is null then
    return json_build_object('ok', false);
  end if;
  return json_build_object(
    'ok', true,
    'checkin_daily',  point_amount(v_school, 'checkin_daily'),
    'checkin_weekly', point_amount(v_school, 'checkin_weekly'),
    'praise',         point_amount(v_school, 'praise'),
    'quiz',           point_amount(v_school, 'quiz'),
    'honor_gardener', point_amount(v_school, 'honor_gardener'));
end $$;
revoke all on function point_amounts() from public, anon;
grant execute on function point_amounts() to authenticated;

-- ═══════════ 확인 ═══════════
--   앱에서 교환소 → '포인트 적립 방법' 의 금액이 포인트 설정과 같으면 적용된 것이다.
--   (SQL 에디터에서는 로그인한 사용자가 없어 ok:false 가 나온다)
