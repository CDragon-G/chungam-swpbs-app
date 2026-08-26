-- 041_class_point_economy.sql
-- 1) 우리 반 포인트 현황 — 담임 선생님이 자기 학급 포인트 분포를 볼 수 있게
-- 2) 전교 포인트 현황 쿼리 최적화 (학생 수만큼 반복되던 상관 서브쿼리 제거)

-- ═══════════ 1) 전교 포인트 현황 (관리자) — 최적화 ═══════════
-- 기존: 학생 1명마다 point_transactions 를 다시 훑는 상관 서브쿼리
-- 개선: 한 번의 집계 후 조인. 학생 수가 늘어도 스캔이 한 번이다.
create or replace function point_economy_stats()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_school uuid := current_profile_school();
  v_res json;
begin
  if v_school is null or current_profile_role() <> 'teacher' then
    return json_build_object('ok', false);
  end if;

  select json_build_object(
    'ok', true,
    'scope', 'school',
    'students', count(*),
    'total', coalesce(sum(bal), 0),
    'avg', coalesce(round(avg(bal))::int, 0),
    'median', coalesce(
      percentile_cont(0.5) within group (order by bal)::int, 0),
    'max', coalesce(max(bal), 0),
    'rich_ratio', case when count(*) = 0 then 0
      else round(100.0 * count(*) filter (where bal >= 1000) / count(*))::int end
  ) into v_res
  from (
    select p.user_id, coalesce(t.bal, 0) as bal
      from profiles p
      left join (
        select user_id, sum(amount) as bal
          from point_transactions
         where school_id = v_school
         group by user_id
      ) t on t.user_id = p.user_id
     where p.school_id = v_school and p.role = 'student'
  ) s;

  return v_res;
end $$;
grant execute on function point_economy_stats() to authenticated;

-- ═══════════ 2) 우리 반 포인트 현황 (담임) ═══════════
-- p_grade / p_class 를 주지 않으면 호출한 교사 프로필의 학년·반을 쓴다.
create or replace function class_point_economy_stats(
  p_grade int default null, p_class int default null)
returns json
language plpgsql stable security definer set search_path = public as $$
declare
  v_school uuid := current_profile_school();
  v_grade int := p_grade;
  v_class int := p_class;
  v_res json;
begin
  if v_school is null or current_profile_role() <> 'teacher' then
    return json_build_object('ok', false, 'reason', 'not_teacher');
  end if;

  -- 인자가 없으면 내 프로필의 담임 학급을 쓴다
  if v_grade is null or v_class is null then
    select grade, class_num into v_grade, v_class
      from profiles where user_id = auth.uid();
  end if;

  if v_grade is null or v_class is null then
    return json_build_object('ok', false, 'reason', 'no_class');
  end if;

  select json_build_object(
    'ok', true,
    'scope', 'class',
    'grade', v_grade,
    'class_num', v_class,
    'students', count(*),
    'total', coalesce(sum(bal), 0),
    'avg', coalesce(round(avg(bal))::int, 0),
    'median', coalesce(
      percentile_cont(0.5) within group (order by bal)::int, 0),
    'max', coalesce(max(bal), 0),
    'min', coalesce(min(bal), 0),
    'rich_ratio', case when count(*) = 0 then 0
      else round(100.0 * count(*) filter (where bal >= 1000) / count(*))::int end
  ) into v_res
  from (
    select p.user_id, coalesce(t.bal, 0) as bal
      from profiles p
      left join (
        select user_id, sum(amount) as bal
          from point_transactions
         where school_id = v_school
         group by user_id
      ) t on t.user_id = p.user_id
     where p.school_id = v_school
       and p.role = 'student'
       and p.grade = v_grade
       and p.class_num = v_class
  ) s;

  return v_res;
end $$;
grant execute on function class_point_economy_stats(int, int) to authenticated;

-- ═══════════ 3) 집계 성능을 위한 인덱스 ═══════════
create index if not exists pt_school_user_idx
  on point_transactions(school_id, user_id);
create index if not exists profiles_school_role_class_idx
  on profiles(school_id, role, grade, class_num);
