-- 071_student_rows_round.sql
-- 교사 대시보드 '학생별' 탭이 "데이터 처리 중 오류가 발생했어요" 로 뜨던 문제.
--
-- 원인
--   daily_checkins.score_pct 는 float(double precision) 이라 avg() 도 double 이 된다.
--   Postgres 에는 round(double precision, integer) 가 없다 (numeric 만 자릿수를 받는다).
--     ERROR 42883: function round(double precision, integer) does not exist
--   042 부터 있던 문제다. 062 에서 고친 user_id 모호함 오류가 먼저 나서 가려져 있었다.
--
-- 고친 것
--   평균을 numeric 으로 바꾼 뒤 반올림한다. 나머지는 063 과 똑같다.
--   다른 함수의 round(…, n) 은 모두 numeric 을 받고 있음을 확인했다.

create or replace function student_rows(p_days int default 60)
returns table (
  user_id uuid,
  profile_id uuid,
  nickname text,
  grade int,
  class_num int,
  student_num int,
  streak int,
  last_checkin_date date,
  avg_score numeric,
  badge_count int,
  missed_days int
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_school uuid := current_profile_school();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_from date;
  v_prev date;
begin
  if v_school is null or current_profile_role() <> 'teacher' then
    return;
  end if;
  v_from := v_today - (greatest(1, least(p_days, 180)) - 1);
  v_prev := prev_school_day(v_school, v_today);

  return query
  with stu as (
    select p.user_id, p.id as profile_id, p.nickname,
           coalesce(p.grade, 0) as grade,
           coalesce(p.class_num, 0) as class_num,
           coalesce(p.student_num, 0) as student_num
      from profiles p
     where p.school_id = v_school and p.role = 'student'
       and p.left_at is null
  ),
  chk as (
    select d.user_id, d.checkin_date, d.score_pct
      from daily_checkins d
     where d.school_id = v_school and d.checkin_date >= v_from
  ),
  agg as (
    select c.user_id,
           max(c.checkin_date) as last_date,
           avg(c.score_pct)    as avg_score
      from chk c group by c.user_id
  ),
  cur as (
    -- 수업일 기준 연속 참여 (063). 주말·공휴일·휴업일은 건너뛴다
    select cs.user_id,
           streak_now(cs.current_days, cs.last_date, v_today, v_prev) as streak
      from checkin_streaks cs
      join stu on stu.user_id = cs.user_id
  ),
  bdg as (
    select ub.user_id, count(*)::int as cnt
      from user_badges ub
      join stu on stu.user_id = ub.user_id
     group by ub.user_id
  )
  select
    stu.user_id, stu.profile_id, stu.nickname,
    stu.grade, stu.class_num, stu.student_num,
    coalesce(cur.streak, 0)::int,
    agg.last_date,
    coalesce(round(agg.avg_score::numeric, 1), 0)::numeric,  -- 071: float → numeric
    coalesce(bdg.cnt, 0)::int,
    case when agg.last_date is null then 999
         else greatest(0, (v_today - agg.last_date))::int end
  from stu
  left join agg on agg.user_id = stu.user_id
  left join cur on cur.user_id = stu.user_id
  left join bdg on bdg.user_id = stu.user_id
  order by stu.grade, stu.class_num, stu.student_num;
end $$;
grant execute on function student_rows(int) to authenticated;

-- ═══════════ 확인 ═══════════
--   교사 계정으로 앱의 대시보드 → 학생별 탭을 열어 목록이 나오는지 본다.
--   SQL 에디터에서는 로그인한 교사가 없어 빈 결과가 정상이다.
