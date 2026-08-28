-- 043_homeroom.sql
-- 담임반 관리
--   담임은 가입할 때 묻지 않고, 학기 중에 바뀌기도 하며, 해마다 달라진다.
--   그래서 선생님이 직접 '내 담임 학급'을 지정하고 언제든 바꿀 수 있게 한다.
--   지정하면 그 학급 학생들의 참여도·점수·포인트를 한 화면에서 본다.

-- ═══════════ 1) 우리 학교에 있는 학급 목록 ═══════════
create or replace function school_class_list()
returns table (grade int, class_num int, student_count int)
language sql stable security definer set search_path = public as $$
  select p.grade, p.class_num, count(*)::int
    from profiles p
   where p.school_id = current_profile_school()
     and p.role = 'student'
     and p.grade is not null and p.class_num is not null
   group by p.grade, p.class_num
   order by p.grade, p.class_num;
$$;
grant execute on function school_class_list() to authenticated;

-- ═══════════ 2) 내 담임 학급 지정 · 해제 ═══════════
create or replace function set_my_homeroom(p_grade int, p_class int)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare v_school uuid;
begin
  select school_id into v_school from profiles
   where user_id = auth.uid() and role = 'teacher';
  if v_school is null then
    return json_build_object('ok', false, 'error', '교사만 설정할 수 있어요');
  end if;
  if p_grade is not null and (p_grade < 1 or p_grade > 6) then
    return json_build_object('ok', false, 'error', '학년을 확인해주세요');
  end if;
  if p_class is not null and (p_class < 1 or p_class > 30) then
    return json_build_object('ok', false, 'error', '반을 확인해주세요');
  end if;

  update profiles
     set grade = p_grade, class_num = p_class
   where user_id = auth.uid();

  return json_build_object('ok', true, 'grade', p_grade, 'class_num', p_class);
end $$;
grant execute on function set_my_homeroom(int, int) to authenticated;

-- ═══════════ 3) 우리 반 현황 (요약 + 학생별) ═══════════
create or replace function homeroom_overview(p_days int default 30)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_grade int; v_class int;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_from date;
  v_students json;
  v_total int; v_today_cnt int;
  v_avg_part numeric; v_avg_score numeric; v_total_points bigint;
  v_school_days int;
begin
  select school_id, grade, class_num into v_school, v_grade, v_class
    from profiles where user_id = auth.uid() and role = 'teacher';

  if v_school is null then
    return json_build_object('ok', false, 'reason', 'not_teacher');
  end if;
  if v_grade is null or v_class is null then
    return json_build_object('ok', false, 'reason', 'no_homeroom');
  end if;

  v_from := v_today - (greatest(1, least(p_days, 180)) - 1);

  -- 기간 내 수업일 수 (참여율 분모)
  select count(*) into v_school_days
    from generate_series(v_from, v_today, interval '1 day') d
   where is_school_day(v_school, d::date);
  if v_school_days = 0 then v_school_days := 1; end if;

  with stu as (
    select p.user_id, p.id as profile_id, p.nickname,
           coalesce(p.student_num, 0) as student_num
      from profiles p
     where p.school_id = v_school and p.role = 'student'
       and p.grade = v_grade and p.class_num = v_class
  ),
  chk as (
    select d.user_id, d.checkin_date, d.score_pct
      from daily_checkins d
      join stu on stu.user_id = d.user_id
     where d.checkin_date >= v_from
  ),
  agg as (
    select c.user_id,
           count(distinct c.checkin_date)::int as days,
           max(c.checkin_date) as last_date,
           avg(c.score_pct) as avg_score,
           bool_or(c.checkin_date = v_today) as today_done
      from chk c group by c.user_id
  ),
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
    select s.user_id, max(s.len) as streak
      from streaks s where s.ends >= v_today - 1 group by s.user_id
  ),
  pts as (
    select t.user_id, sum(t.amount)::int as bal
      from point_transactions t
      join stu on stu.user_id = t.user_id
     group by t.user_id
  ),
  bdg as (
    select ub.user_id, count(*)::int as cnt
      from user_badges ub join stu on stu.user_id = ub.user_id
     group by ub.user_id
  ),
  rows_ as (
    select
      stu.user_id, stu.profile_id, stu.nickname, stu.student_num,
      coalesce(agg.days, 0) as days,
      round(100.0 * coalesce(agg.days, 0) / v_school_days)::int as part_pct,
      coalesce(round(agg.avg_score)::int, 0) as avg_score,
      coalesce(agg.today_done, false) as today_done,
      agg.last_date,
      coalesce(cur.streak, 0)::int as streak,
      coalesce(pts.bal, 0) as points,
      coalesce(bdg.cnt, 0) as badges,
      case when agg.last_date is null then 999
           else (v_today - agg.last_date)::int end as missed
    from stu
    left join agg on agg.user_id = stu.user_id
    left join cur on cur.user_id = stu.user_id
    left join pts on pts.user_id = stu.user_id
    left join bdg on bdg.user_id = stu.user_id
  )
  select
    coalesce(json_agg(to_json(r) order by r.student_num, r.nickname), '[]'::json),
    count(*), count(*) filter (where r.today_done),
    coalesce(round(avg(r.part_pct)), 0), coalesce(round(avg(r.avg_score)), 0),
    coalesce(sum(r.points), 0)
  into v_students, v_total, v_today_cnt, v_avg_part, v_avg_score, v_total_points
  from rows_ r;

  return json_build_object(
    'ok', true,
    'grade', v_grade, 'class_num', v_class,
    'days', p_days, 'school_days', v_school_days,
    'total', v_total,
    'today_done', v_today_cnt,
    'today_pct', case when v_total = 0 then 0
                      else round(100.0 * v_today_cnt / v_total)::int end,
    'avg_participation', v_avg_part::int,
    'avg_score', v_avg_score::int,
    'total_points', v_total_points,
    'students', v_students);
end $$;
grant execute on function homeroom_overview(int) to authenticated;
