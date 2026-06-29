-- 014_hall_of_fame.sql
-- 명예의 전당: 이달의 학생 선정.
-- 종합 점수 = 칭찬 40% + 연속 참여(점검일수) 30% + 평균 점검 점수 30%
-- 각 지표를 0~100으로 정규화한 뒤 가중 합산.
-- 학급/학년/전교 단위로 최고 학생을 반환한다.
--
-- 주의: count(*)는 bigint, avg(float)는 float을 반환하므로 명시적으로
--       int / numeric 으로 캐스팅한다 (반환 타입과 round() 호환).

create or replace function public.hall_of_fame(
  p_school_id uuid,
  p_year_month text default null  -- 'YYYY-MM', null이면 이번 달
)
returns table (
  scope text,            -- 'class' | 'grade' | 'school'
  scope_label text,      -- '1학년 1반' | '1학년' | '전교'
  user_id uuid,
  nickname text,
  grade int,
  class_num int,
  student_num int,
  praise_count int,
  checkin_days int,
  avg_score numeric,
  total_score numeric
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  ym text := coalesce(p_year_month, to_char((now() at time zone 'Asia/Seoul'), 'YYYY-MM'));
  d_start date := to_date(ym || '-01', 'YYYY-MM-DD');
  d_end date := (to_date(ym || '-01', 'YYYY-MM-DD') + interval '1 month')::date;
begin
  return query
  with stats as (
    select
      p.user_id,
      p.nickname,
      p.grade,
      p.class_num,
      p.student_num,
      coalesce(pr.cnt, 0)::int          as praise_count,
      coalesce(ck.days, 0)::int         as checkin_days,
      coalesce(ck.avg_pct, 0)::numeric  as avg_score
    from profiles p
    left join (
      select student_id, count(*) as cnt
      from praise
      where school_id = p_school_id
        and created_at >= d_start and created_at < d_end
      group by student_id
    ) pr on pr.student_id = p.user_id
    left join (
      select user_id, count(*) as days, avg(score_pct)::numeric as avg_pct
      from daily_checkins
      where school_id = p_school_id
        and checkin_date >= d_start and checkin_date < d_end
      group by user_id
    ) ck on ck.user_id = p.user_id
    where p.school_id = p_school_id and p.role = 'student'
  ),
  maxes as (
    select greatest(max(praise_count), 1) as mp,
           greatest(max(checkin_days), 1) as md
    from stats
  ),
  scored as (
    select s.*,
      round(
        (s.praise_count::numeric / m.mp) * 40
        + (s.checkin_days::numeric / m.md) * 30
        + (s.avg_score / 100.0) * 30
      , 1) as total_score
    from stats s cross join maxes m
    where s.checkin_days > 0 or s.praise_count > 0  -- 활동이 있는 학생만
  ),
  ranked_grade as (
    select *, row_number() over (partition by grade order by total_score desc) as rn
    from scored
  ),
  ranked_class as (
    select *, row_number() over (partition by grade, class_num order by total_score desc) as rn
    from scored
  )
  -- 전교 1위
  select 'school'::text, '전교'::text, sc.user_id, sc.nickname,
         sc.grade, sc.class_num, sc.student_num,
         sc.praise_count, sc.checkin_days, round(sc.avg_score, 1), sc.total_score
  from scored sc order by sc.total_score desc limit 1
  union all
  -- 학년별 1위
  select 'grade'::text, sc.grade || '학년', sc.user_id, sc.nickname,
         sc.grade, sc.class_num, sc.student_num,
         sc.praise_count, sc.checkin_days, round(sc.avg_score, 1), sc.total_score
  from ranked_grade sc where sc.rn = 1
  union all
  -- 학급별 1위
  select 'class'::text, sc.grade || '학년 ' || sc.class_num || '반', sc.user_id, sc.nickname,
         sc.grade, sc.class_num, sc.student_num,
         sc.praise_count, sc.checkin_days, round(sc.avg_score, 1), sc.total_score
  from ranked_class sc where sc.rn = 1;
end;
$$;

revoke all on function public.hall_of_fame(uuid, text) from public;
grant execute on function public.hall_of_fame(uuid, text) to authenticated;
