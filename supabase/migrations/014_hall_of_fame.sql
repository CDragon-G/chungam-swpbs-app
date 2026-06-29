-- 014_hall_of_fame.sql
-- 명예의 전당: 이달의 학생 선정.
-- 종합 점수 = 칭찬 40% + 연속 참여(점검일수) 30% + 평균 점검 점수 30%
-- 각 지표를 0~100으로 정규화한 뒤 가중 합산.
-- 학급/학년/전교 단위로 최고 학생을 반환한다.

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
  max_praise int;
  max_days int;
begin
  -- 학생별 월간 지표 집계
  create temporary table _stats on commit drop as
  select
    p.user_id,
    p.nickname,
    p.grade,
    p.class_num,
    p.student_num,
    coalesce(pr.cnt, 0) as praise_count,
    coalesce(ck.days, 0) as checkin_days,
    coalesce(ck.avg_pct, 0) as avg_score
  from profiles p
  left join (
    select student_id, count(*) cnt
    from praise
    where school_id = p_school_id
      and created_at >= d_start and created_at < d_end
    group by student_id
  ) pr on pr.student_id = p.user_id
  left join (
    select user_id, count(*) days, avg(score_pct) avg_pct
    from daily_checkins
    where school_id = p_school_id
      and checkin_date >= d_start and checkin_date < d_end
    group by user_id
  ) ck on ck.user_id = p.user_id
  where p.school_id = p_school_id and p.role = 'student';

  select greatest(max(s.praise_count), 1), greatest(max(s.checkin_days), 1)
  into max_praise, max_days from _stats s;

  -- 종합 점수 계산 (정규화 + 가중)
  create temporary table _scored on commit drop as
  select
    s.*,
    round(
      (s.praise_count::numeric / max_praise) * 40
      + (s.checkin_days::numeric / max_days) * 30
      + (s.avg_score / 100.0) * 30
    , 1) as total_score
  from _stats s
  where s.checkin_days > 0 or s.praise_count > 0;  -- 활동이 있는 학생만

  -- 전교 1위
  return query
  select 'school'::text, '전교'::text, sc.user_id, sc.nickname, sc.grade, sc.class_num, sc.student_num,
         sc.praise_count, sc.checkin_days, round(sc.avg_score, 1), sc.total_score
  from _scored sc order by sc.total_score desc limit 1;

  -- 학년별 1위
  return query
  select 'grade'::text, sc.grade || '학년', sc.user_id, sc.nickname, sc.grade, sc.class_num, sc.student_num,
         sc.praise_count, sc.checkin_days, round(sc.avg_score, 1), sc.total_score
  from (
    select *, row_number() over (partition by grade order by total_score desc) rn
    from _scored
  ) sc where sc.rn = 1 order by sc.grade;

  -- 학급별 1위
  return query
  select 'class'::text, sc.grade || '학년 ' || sc.class_num || '반', sc.user_id, sc.nickname, sc.grade, sc.class_num, sc.student_num,
         sc.praise_count, sc.checkin_days, round(sc.avg_score, 1), sc.total_score
  from (
    select *, row_number() over (partition by grade, class_num order by total_score desc) rn
    from _scored
  ) sc where sc.rn = 1 order by sc.grade, sc.class_num;
end;
$$;

revoke all on function public.hall_of_fame(uuid, text) from public;
grant execute on function public.hall_of_fame(uuid, text) to authenticated;
