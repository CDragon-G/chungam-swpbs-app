-- 014_hall_of_fame.sql
-- 명예의 전당: 이달의 학생 선정.
-- 종합 점수 = 칭찬 40% + 연속 참여(점검일수) 30% + 평균 점검 점수 30%
--
-- 반환 타입은 double precision 사용:
--   numeric은 PostgREST가 JSON 문자열로 직렬화해 앱의 num 캐스팅이 깨진다.
--   double precision은 JSON 숫자로 직렬화되어 안전하다.
-- 반환 타입을 바꾸므로 기존 함수를 먼저 drop 한다.

drop function if exists public.hall_of_fame(uuid, text);

create or replace function public.hall_of_fame(
  p_school_id uuid,
  p_year_month text default null
)
returns table (
  scope text,
  scope_label text,
  user_id uuid,
  nickname text,
  grade int,
  class_num int,
  student_num int,
  praise_count int,
  checkin_days int,
  avg_score double precision,
  total_score double precision
)
language plpgsql
security definer
set search_path = public, auth
as $$
-- 반환 컬럼(user_id, grade 등)과 테이블 컬럼 이름이 겹칠 때 컬럼을 우선 해석
#variable_conflict use_column
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
      (round(
        (s.praise_count::numeric / m.mp) * 40
        + (s.checkin_days::numeric / m.md) * 30
        + (s.avg_score / 100.0) * 30
      , 1))::double precision as total_score
    from stats s cross join maxes m
    where s.checkin_days > 0 or s.praise_count > 0
  ),
  ranked_school as (
    select *, row_number() over (order by total_score desc) as rn from scored
  ),
  ranked_grade as (
    select *, row_number() over (partition by grade order by total_score desc) as rn from scored
  ),
  ranked_class as (
    select *, row_number() over (partition by grade, class_num order by total_score desc) as rn from scored
  )
  select 'school'::text, '전교'::text, sc.user_id, sc.nickname,
         sc.grade, sc.class_num, sc.student_num,
         sc.praise_count, sc.checkin_days,
         (round(sc.avg_score, 1))::double precision, sc.total_score
  from ranked_school sc where sc.rn = 1
  union all
  select 'grade'::text, sc.grade || '학년', sc.user_id, sc.nickname,
         sc.grade, sc.class_num, sc.student_num,
         sc.praise_count, sc.checkin_days,
         (round(sc.avg_score, 1))::double precision, sc.total_score
  from ranked_grade sc where sc.rn = 1
  union all
  select 'class'::text, sc.grade || '학년 ' || sc.class_num || '반', sc.user_id, sc.nickname,
         sc.grade, sc.class_num, sc.student_num,
         sc.praise_count, sc.checkin_days,
         (round(sc.avg_score, 1))::double precision, sc.total_score
  from ranked_class sc where sc.rn = 1;
end;
$$;

revoke all on function public.hall_of_fame(uuid, text) from public;
grant execute on function public.hall_of_fame(uuid, text) to authenticated;
