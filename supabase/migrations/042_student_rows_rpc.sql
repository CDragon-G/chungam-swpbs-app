-- 042_student_rows_rpc.sql
-- 학생 목록 집계를 서버로 옮긴다.
--
-- 기존: 앱이 전교 60일치 자기점검 기록을 통째로 내려받아(수만 건) 클라이언트에서
--       학생 수만큼 반복 필터링했다. 학생이 늘수록 전송량과 계산량이 함께 폭증한다.
--       779명 × 60일 ≈ 4만 7천 건 ≈ 20MB, 비교 연산 3천만 회.
-- 개선: 학생 1명당 1행만 서버에서 집계해 내려준다. 전송량이 수백 분의 일로 줄고
--       연속 참여일 계산도 Postgres 가 처리한다.

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
declare
  v_school uuid := current_profile_school();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_from date;
begin
  if v_school is null or current_profile_role() <> 'teacher' then
    return;
  end if;
  v_from := v_today - (greatest(1, least(p_days, 180)) - 1);

  return query
  with stu as (
    select p.user_id, p.id as profile_id, p.nickname,
           coalesce(p.grade, 0) as grade,
           coalesce(p.class_num, 0) as class_num,
           coalesce(p.student_num, 0) as student_num
      from profiles p
     where p.school_id = v_school and p.role = 'student'
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
  -- 연속 참여일: 날짜에서 행번호를 빼면 연속 구간이 같은 값으로 묶인다
  runs as (
    select c.user_id, c.checkin_date,
           c.checkin_date
             - (row_number() over (partition by c.user_id
                                   order by c.checkin_date))::int as grp
      from (select distinct user_id, checkin_date from chk) c
  ),
  streaks as (
    select r.user_id, count(*)::int as len, max(r.checkin_date) as ends
      from runs r group by r.user_id, r.grp
  ),
  cur as (
    -- 오늘 또는 어제로 끝나는 구간만 '현재 연속'으로 인정
    select s.user_id, max(s.len) as streak
      from streaks s
     where s.ends >= v_today - 1
     group by s.user_id
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
    coalesce(round(agg.avg_score, 1), 0)::numeric,
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

-- 집계에 쓰이는 인덱스
create index if not exists dc_school_date_idx
  on daily_checkins(school_id, checkin_date);
create index if not exists dc_user_date_idx
  on daily_checkins(user_id, checkin_date);
