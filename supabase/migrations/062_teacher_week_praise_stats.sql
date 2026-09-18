-- 062_teacher_week_praise_stats.sql
-- 선생님 화면 네 가지
--
--   1) 대시보드 '학생별' 탭 오류 고침
--      student_rows() 안에서 user_id 를 표 이름 없이 썼는데, 이 함수가 돌려주는 칸
--      이름도 user_id 라서 Postgres 가 어느 쪽인지 몰라 매번 실패했다.
--      ("column reference "user_id" is ambiguous") 042 부터 계속 그랬다.
--   2) 담임반 · 학급 목록에서 졸업·전출 처리된 학생을 뺀다 (055 이후 필요해진 것)
--   3) 주간 점검표 — 반 학생들이 이번 주 어느 날 점검했는지 한눈에
--   4) 칭찬 우체통 통계 — 오늘 학생들 사이에 오간 칭찬 편지 수
--
-- 앱보다 먼저 실행해도 된다. 1·2 는 지금 쓰는 앱에서도 바로 고쳐진다.

-- ═══════════ 1) 학생별 탭 ═══════════
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
  -- 연속 참여일: 날짜에서 행번호를 빼면 연속 구간이 같은 값으로 묶인다
  runs as (
    select c.user_id, c.checkin_date,
           c.checkin_date
             - (row_number() over (partition by c.user_id
                                   order by c.checkin_date))::int as grp
      from (select distinct c0.user_id, c0.checkin_date from chk c0) c
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

-- ═══════════ 2) 졸업·전출 학생 빼기 ═══════════
create or replace function school_class_list()
returns table (grade int, class_num int, student_count int)
language sql stable security definer set search_path = public as $$
  select p.grade, p.class_num, count(*)::int
    from profiles p
   where p.school_id = current_profile_school()
     and p.role = 'student'
     and p.left_at is null
     and p.grade is not null and p.class_num is not null
   group by p.grade, p.class_num
   order by p.grade, p.class_num;
$$;
grant execute on function school_class_list() to authenticated;

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
  runs as (
    select c.user_id, c.checkin_date,
           c.checkin_date
             - (row_number() over (partition by c.user_id
                                   order by c.checkin_date))::int as grp
      from (select distinct c0.user_id, c0.checkin_date from chk c0) c
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

-- ═══════════ 3) 주간 점검표 ═══════════
--   한 반 학생들의 월~금 점검 여부. 담임반 화면과 대시보드 반별 탭에서 쓴다.
--   선생님이면 어느 반이든 볼 수 있다 (반별 통계와 같은 범위).
--
--   phase — 그날을 어떻게 표시할지
--     past          지난 날. 수업일인데 기록이 없으면 '안 함'
--     today_open    오늘, 점검이 열려 있음. 아직 안 했으면 '아직'
--     today_closed  오늘, 아직 열리기 전(오후 1시 전). 안 했어도 '안 함' 이 아니다
--     future        앞으로 올 날
create or replace function class_week_checkins(
  p_grade int, p_class int, p_week_start date default null
)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_ws date;
  v_open boolean;
  v_days json; v_students json;
begin
  select school_id, role into v_school, v_role from profiles where user_id = auth.uid();
  if v_school is null or v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 볼 수 있어요');
  end if;
  if p_grade is null or p_class is null then
    return json_build_object('ok', false, 'error', '학급을 골라주세요');
  end if;

  v_ws := date_trunc('week', coalesce(p_week_start, v_today))::date;
  v_open := is_checkin_open(v_school);

  select json_agg(json_build_object(
           'date', to_char(x.day, 'YYYY-MM-DD'),
           'school_day', is_school_day(v_school, x.day),
           'phase', case when x.day > v_today then 'future'
                         when x.day = v_today then
                           case when v_open then 'today_open' else 'today_closed' end
                         else 'past' end)
         order by x.day)
    into v_days
    from (select g::date as day
            from generate_series(v_ws, v_ws + 4, interval '1 day') g) x;

  select coalesce(json_agg(json_build_object(
           'user_id', s.user_id,
           'nickname', s.nickname,
           'student_num', s.student_num,
           'scores', s.scores)
         order by s.student_num nulls last, s.nickname), '[]'::json)
    into v_students
    from (
      select p.user_id, p.nickname, p.student_num,
             (select coalesce(json_object_agg(to_char(c.checkin_date, 'YYYY-MM-DD'),
                                              round(c.score_pct)), '{}'::json)
                from daily_checkins c
               where c.user_id = p.user_id
                 and c.checkin_date between v_ws and v_ws + 4) as scores
        from profiles p
       where p.school_id = v_school and p.role = 'student' and p.left_at is null
         and p.grade = p_grade and p.class_num = p_class
    ) s;

  return json_build_object(
    'ok', true,
    'week_start', to_char(v_ws, 'YYYY-MM-DD'),
    'today', to_char(v_today, 'YYYY-MM-DD'),
    'days', coalesce(v_days, '[]'::json),
    'students', v_students);
end $$;
grant execute on function class_week_checkins(int, int, date) to authenticated;

-- ═══════════ 4) 칭찬 우체통 통계 ═══════════
--   숫자만 준다. 누가 누구에게 보냈는지는 담임·관리자용 class_praise_mail() 에서만.
--   숨김 처리된 편지(선생님이 숨김 · 받은 학생이 '사실이 아니에요')는 세지 않는다.
create index if not exists praise_mail_school_created_idx
  on praise_mail (school_id, created_at);

create or replace function praise_mail_stats()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text; v_grade int; v_class int;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_day0 timestamptz := (v_today::timestamp at time zone 'Asia/Seoul');
  v_week0 timestamptz :=
    (date_trunc('week', v_today)::date::timestamp at time zone 'Asia/Seoul');
  v_today_n int; v_senders int; v_week_n int; v_class_n int; v_last7 json;
begin
  select school_id, role, grade, class_num
    into v_school, v_role, v_grade, v_class
    from profiles where user_id = auth.uid();
  if v_school is null or v_role is distinct from 'teacher' then
    return json_build_object('ok', false);
  end if;

  select count(*) filter (where m.created_at >= v_day0),
         count(distinct m.sender_id) filter (where m.created_at >= v_day0),
         count(*) filter (where m.created_at >= v_week0)
    into v_today_n, v_senders, v_week_n
    from praise_mail m
   where m.school_id = v_school
     and m.created_at >= least(v_day0, v_week0)
     and m.hidden_at is null;

  if v_grade is not null and v_class is not null then
    select count(*) into v_class_n
      from praise_mail m
      join profiles r on r.user_id = m.recipient_id
     where m.school_id = v_school
       and m.created_at >= v_day0
       and m.hidden_at is null
       and r.grade = v_grade and r.class_num = v_class;
  end if;

  select json_agg(json_build_object('date', to_char(g.d, 'YYYY-MM-DD'),
                                    'count', coalesce(x.n, 0)) order by g.d)
    into v_last7
    from generate_series(v_today - 6, v_today, interval '1 day') g(d)
    left join (
      select (m.created_at at time zone 'Asia/Seoul')::date as day, count(*) n
        from praise_mail m
       where m.school_id = v_school
         and m.created_at >= ((v_today - 6)::timestamp at time zone 'Asia/Seoul')
         and m.hidden_at is null
       group by 1
    ) x on x.day = g.d::date;

  return json_build_object(
    'ok', true,
    'today', v_today_n,
    'today_senders', v_senders,
    'week', v_week_n,
    'my_class_today', v_class_n,
    'my_class_label', case when v_grade is null or v_class is null then null
                           else v_grade || '학년 ' || v_class || '반' end,
    'last7', coalesce(v_last7, '[]'::json));
end $$;
grant execute on function praise_mail_stats() to authenticated;

-- ═══════════ 확인 ═══════════
--   앱의 대시보드 → 학생별 탭이 목록으로 열리면 1번이 고쳐진 것이다.
--   SQL 에디터에서는 로그인한 선생님이 없어 아래 함수들이 빈 값·ok:false 를 돌려준다.
