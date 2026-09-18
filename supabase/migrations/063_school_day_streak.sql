-- 063_school_day_streak.sql
-- 연속 참여를 '수업일' 기준으로 센다 + 불꽃 뱃지 + 명예의 전당 '불꽃' 순위
--
-- 전에는 달력 날짜로 셌다. 058 부터 점검은 수업일에만 할 수 있으므로
-- 금요일에 점검해도 토요일에 연속이 0 이 되었다. 그래서 '7일 연속', '30일 연속'
-- 뱃지는 사실상 받을 수 없었다 (한 주 최대 5일).
--
-- 이제는 수업일만 센다. 주말·공휴일·학교 휴업일·방학은 건너뛴다.
--   금요일 점검 → 월요일 점검 : 연속 +1
--   수업일에 한 번 빠지면      : 다시 1 부터
--   오늘 아직 안 했으면         : 어제(직전 수업일)까지의 연속을 그대로 보여준다
--
-- 계산은 점검이 저장될 때 한 번만 한다 (checkin_streaks 표).
-- 학기 정리(060)로 원본을 지워도 연속·최고 기록은 남는다.

-- ═══════════ 1) 직전 수업일 ═══════════
--   방학이 길어도 찾도록 200일까지 거슬러 본다. 보통은 1~3일 안에 끝난다.
create or replace function prev_school_day(p_school uuid, p_date date)
returns date
language plpgsql stable security definer set search_path = public as $$
declare
  d date := p_date - 1;
begin
  for i in 1..200 loop
    if is_school_day(p_school, d) then
      return d;
    end if;
    d := d - 1;
  end loop;
  return null;
end $$;

-- ═══════════ 2) 연속 기록 표 ═══════════
create table if not exists checkin_streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  school_id uuid not null references schools(id) on delete cascade,
  current_days int not null default 0,   -- 마지막 점검까지 이어진 수업일 수
  best_days int not null default 0,      -- 지금까지 가장 길었던 연속
  last_date date,                   -- 마지막으로 연속에 들어간 점검 날짜
  updated_at timestamptz not null default now()
);
create index if not exists checkin_streaks_school_idx
  on checkin_streaks (school_id, current_days desc);
alter table checkin_streaks enable row level security;   -- 함수로만 읽는다

--   저장된 연속이 '지금도' 살아 있는가.
--   오늘 했거나, 직전 수업일까지 했으면 살아 있다. 아니면 0.
create or replace function streak_now(p_current int, p_last date, p_today date, p_prev date)
returns int
language sql immutable as $$
  select case
    when p_last is null then 0
    when p_last >= p_today then p_current
    when p_prev is not null and p_last >= p_prev then p_current
    else 0
  end;
$$;

-- ═══════════ 3) 점검이 저장될 때 연속 갱신 ═══════════
--   어떤 오류가 나도 점검 저장은 막지 않는다.
create or replace function trg_update_checkin_streak()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  s checkin_streaks;
  v_prev date;
  v_cur int;
begin
  begin
    if not is_school_day(new.school_id, new.checkin_date) then
      return new;   -- 쉬는 날 기록은 연속에 넣지도, 끊지도 않는다
    end if;

    select * into s from checkin_streaks where user_id = new.user_id for update;
    if s.user_id is null then
      insert into checkin_streaks (user_id, school_id, current_days, best_days, last_date)
      values (new.user_id, new.school_id, 1, 1, new.checkin_date)
      on conflict (user_id) do nothing;
      return new;
    end if;
    if s.last_date is not null and new.checkin_date <= s.last_date then
      return new;   -- 같은 날 다시 저장, 또는 지난 날짜
    end if;

    v_prev := prev_school_day(new.school_id, new.checkin_date);
    v_cur := case when s.last_date is not null and s.last_date = v_prev
                  then s.current_days + 1 else 1 end;

    update checkin_streaks
       set current_days = v_cur,
           best_days = greatest(best_days, v_cur),
           last_date = new.checkin_date,
           school_id = new.school_id,
           updated_at = now()
     where user_id = new.user_id;
  exception when others then
    raise warning 'checkin streak update failed: %', sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists checkin_streak_update on daily_checkins;
create trigger checkin_streak_update
  after insert on daily_checkins
  for each row execute function trg_update_checkin_streak();

-- ═══════════ 4) 지금까지의 기록으로 채우기 ═══════════
--   남아 있는 점검 원본(학기 정리 전 것)으로 학생마다 연속·최고를 계산한다.
--   수업일에 번호를 매기고, 점검한 수업일 번호가 이어지는 구간을 찾는다.
with bounds as (
  select school_id, min(checkin_date) as d0
    from daily_checkins group by school_id
),
sd as (
  select b.school_id, g::date as day,
         row_number() over (partition by b.school_id order by g) as idx
    from bounds b,
         generate_series(b.d0, (now() at time zone 'Asia/Seoul')::date,
                         interval '1 day') g
   where is_school_day(b.school_id, g::date)
),
ck as (
  select distinct d.user_id, d.school_id, d.checkin_date, sd.idx
    from daily_checkins d
    join sd on sd.school_id = d.school_id and sd.day = d.checkin_date
),
isl as (
  select c.user_id, c.school_id, c.checkin_date,
         c.idx - row_number() over (partition by c.user_id order by c.idx) as grp
    from ck c
),
runs as (
  select i.user_id, i.school_id, i.grp,
         count(*)::int as len, max(i.checkin_date) as last_date
    from isl i group by i.user_id, i.school_id, i.grp
),
latest as (
  select distinct on (r.user_id) r.user_id, r.school_id, r.len, r.last_date
    from runs r order by r.user_id, r.last_date desc
),
best as (
  select r.user_id, max(r.len) as best from runs r group by r.user_id
)
insert into checkin_streaks (user_id, school_id, current_days, best_days, last_date)
select l.user_id, l.school_id, l.len, b.best, l.last_date
  from latest l join best b on b.user_id = l.user_id
on conflict (user_id) do update
   set current_days = excluded.current_days,
       best_days = greatest(checkin_streaks.best_days, excluded.best_days),
       last_date = excluded.last_date,
       school_id = excluded.school_id,
       updated_at = now();

-- ═══════════ 5) 내 연속 기록 ═══════════
create or replace function my_streak()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  s checkin_streaks;
  v_school uuid := current_profile_school();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  select * into s from checkin_streaks where user_id = auth.uid();
  if s.user_id is null or v_school is null then
    return json_build_object('ok', true, 'current', 0, 'best', 0, 'today_done', false);
  end if;
  return json_build_object(
    'ok', true,
    'current', streak_now(s.current_days, s.last_date, v_today,
                          prev_school_day(v_school, v_today)),
    'best', s.best_days,
    'last_date', s.last_date,
    'today_done', s.last_date = v_today);
end $$;
grant execute on function my_streak() to authenticated;

-- ═══════════ 6) 명예의 전당 — 불꽃 순위 ═══════════
--   지금 이어지고 있는 연속 참여 순. 이름은 가운데를 가린다.
--   전교 상위 p_limit 명 + 우리 반 상위 3명 + 내 기록.
create or replace function streak_leaders(p_limit int default 10)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text; v_grade int; v_class int;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_prev date;
  v_school_top json; v_class_top json;
begin
  select school_id, role, grade, class_num
    into v_school, v_role, v_grade, v_class
    from profiles where user_id = auth.uid();
  if v_school is null then
    return json_build_object('ok', false);
  end if;
  v_prev := prev_school_day(v_school, v_today);

  with alive as (
    select p.user_id, p.grade, p.class_num, p.nickname,
           streak_now(cs.current_days, cs.last_date, v_today, v_prev) as days,
           cs.best_days as best
      from checkin_streaks cs
      join profiles p on p.user_id = cs.user_id
     where cs.school_id = v_school
       and p.school_id = v_school and p.role = 'student' and p.left_at is null
       and p.grade is not null and p.class_num is not null
  )
  select
    (select coalesce(json_agg(json_build_object(
              'label', a.grade || '-' || a.class_num || ' ' || mask_name(a.nickname),
              'days', a.days, 'best', a.best, 'is_me', a.user_id = auth.uid())
            order by a.days desc, a.best desc, a.grade, a.class_num), '[]'::json)
       from (select * from alive where days >= 3
              order by days desc, best desc limit greatest(1, least(p_limit, 30))) a),
    (select coalesce(json_agg(json_build_object(
              'label', mask_name(a.nickname),
              'days', a.days, 'best', a.best, 'is_me', a.user_id = auth.uid())
            order by a.days desc, a.best desc), '[]'::json)
       from (select * from alive
              where v_grade is not null and grade = v_grade and class_num = v_class
                and days >= 1
              order by days desc, best desc limit 3) a)
    into v_school_top, v_class_top;

  return json_build_object(
    'ok', true,
    'school_top', v_school_top,
    'class_top', v_class_top,
    'class_label', case when v_grade is null or v_class is null then null
                        else v_grade || '학년 ' || v_class || '반' end);
end $$;
grant execute on function streak_leaders(int) to authenticated;

-- ═══════════ 7) 뱃지 ═══════════
--   기존 연속 뱃지 설명을 '수업일' 기준으로 바꾼다 (이름·그림은 그대로)
update badges set description = '수업일 3일 연속 참여 — 새싹이 시원하게 목을 축였어요!'
 where condition_type = 'streak_3';
update badges set description = '수업일 7일 연속 참여! 뿌리가 튼튼해졌어요'
 where condition_type = 'streak_7';
update badges set description = '수업일 30일 연속 돌봄 — 프로 식집사 인정!'
 where condition_type = 'streak_30';

--   불꽃 뱃지 5단계 (앱: assets/badges/streak_days_N.png)
insert into badges (name, description, icon_emoji, condition_type, condition_value)
select v.name, v.description, '🔥', 'streak_days', v.days
  from (values
    ('작은 불꽃',     '수업일 5일 연속 참여! 마음에 작은 불꽃이 켜졌어요',   5),
    ('타오르는 불꽃', '수업일 10일 연속 참여! 불꽃이 활활 타올라요',        10),
    ('뜨거운 불꽃',   '수업일 20일 연속 참여! 누구도 끌 수 없는 열정',      20),
    ('푸른 불꽃',     '수업일 50일 연속 참여! 가장 뜨거운 푸른 불꽃',       50),
    ('전설의 불꽃',   '수업일 100일 연속 참여! 우리 학교의 전설이 되었어요', 100)
  ) as v(name, description, days)
 where not exists (select 1 from badges b
                    where b.condition_type = 'streak_days'
                      and b.condition_value = v.days);

-- ═══════════ 8) 선생님 화면의 연속 참여도 수업일 기준으로 ═══════════
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
  v_prev date;
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
  v_prev := prev_school_day(v_school, v_today);

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
       and p.left_at is null
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
  cur as (
    -- 수업일 기준 연속 참여 (063). 주말·공휴일·휴업일은 건너뛴다
    select cs.user_id,
           streak_now(cs.current_days, cs.last_date, v_today, v_prev) as streak
      from checkin_streaks cs
      join stu on stu.user_id = cs.user_id
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

-- ═══════════ 9) 명예의 전당 — 우리 학교만 · 떠난 학생 제외 ═══════════
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
  -- 우리 학교만 볼 수 있다. 예전에는 학교 id 만 알면 다른 학교 학생 이름을 받을 수 있었다.
  if p_school_id is distinct from current_profile_school() then
    return;
  end if;

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
      and p.left_at is null
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

-- ═══════════ 확인 ═══════════
--   select count(*), max(best), avg(current)::numeric(5,1) from checkin_streaks;
--   select name, condition_value from badges where condition_type = 'streak_days' order by 2;
