-- 061_bottleneck_relief.sql
-- 학교가 많아져도 버티도록 무거운 길을 줄인다.
--
-- 무엇이 무거웠나 (학교 1,500명 기준)
--   1) 교사 홈 · 대시보드: 전교 14일치 점검 원본(규칙별 O/X 포함)을 통째로 내려받아
--      앱에서 합계를 냈다. 선생님이 홈을 열 때마다 약 1만 건.
--      → 서버가 합계만 계산해 돌려준다 (수 KB)
--   2) 학교 새싹: 앱을 열 때마다 서버가 20여 가지를 새로 셌다.
--      → 학교별로 10분 동안 결과를 보관해 둔다
--   3) 이 주의 명예 식집사: 홈을 열어둔 모든 학생이 5분마다 전교 순위를 새로 계산했다.
--      → 학교별로 5분 동안 순위를 보관해 둔다
--   4) 학생 '총 점검 횟수': 지금까지의 점검 id 를 전부 내려받아 개수를 셌다.
--      게다가 060 학기 정리 뒤로는 원본만 세서 횟수가 0 부터 다시 시작했다.
--      → 서버가 원본 + 학기 요약을 합쳐 숫자 하나만 돌려준다
--
-- 보관해 둔 값이 만료되는 순간 여러 명이 동시에 들어와도 한 명만 다시 계산하고
-- 나머지는 직전 값을 받는다 (advisory lock). 한꺼번에 몰려 서버가 멈추지 않게.

-- ═══════════ 0) 인덱스 — 학교 새싹이 학년도 범위로 세는 표들 ═══════════
create index if not exists praise_school_created_idx
  on praise (school_id, created_at);
create index if not exists class_votes_school_created_idx
  on class_votes (school_id, created_at);
create index if not exists point_tx_school_reason_created_idx
  on point_transactions (school_id, reason, created_at);
create index if not exists cico_enroll_school_created_idx
  on cico_enrollments (school_id, created_at);

-- ═══════════ 1) 교사 홈 · 대시보드 — 서버에서 합계 ═══════════
create or replace function teacher_school_overview()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_week date := date_trunc('week', (now() at time zone 'Asia/Seoul')::date)::date;
  v_total int; v_today_n int;
  v_week_avg double precision; v_last_week_avg double precision;
  v_last14 json; v_classes json; v_cats json;
begin
  select school_id, role into v_school, v_role from profiles where user_id = auth.uid();
  if v_school is null or v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 볼 수 있어요');
  end if;

  select count(*) into v_total from profiles
   where school_id = v_school and role = 'student' and left_at is null;

  -- 참여율이 100% 를 넘지 않게 지금 재학 중인 학생만 센다
  select count(distinct d.user_id) into v_today_n
    from daily_checkins d
    join profiles p on p.user_id = d.user_id
   where d.school_id = v_school and d.checkin_date = v_today
     and p.role = 'student' and p.left_at is null;

  select avg(score_pct) filter (where checkin_date >= v_week),
         avg(score_pct) filter (where checkin_date < v_week)
    into v_week_avg, v_last_week_avg
    from daily_checkins
   where school_id = v_school
     and checkin_date >= v_week - 7 and checkin_date < v_week + 7;

  select json_agg(json_build_object(
           'date', to_char(g.d, 'YYYY-MM-DD'),
           'avg', coalesce(round(x.a::numeric, 1), 0),
           'participants', coalesce(x.n, 0)) order by g.d)
    into v_last14
    from generate_series(v_today - 13, v_today, interval '1 day') g(d)
    left join (
      select checkin_date, avg(score_pct) a, count(*) n
        from daily_checkins
       where school_id = v_school and checkin_date between v_today - 13 and v_today
       group by checkin_date
    ) x on x.checkin_date = g.d::date;

  select coalesce(json_object_agg(t.k, t.pct), '{}'::json) into v_classes
    from (
      select p.grade || '-' || p.class_num as k,
             round(100.0 * count(d.user_id) / count(*), 1) as pct
        from profiles p
        left join daily_checkins d
          on d.user_id = p.user_id and d.checkin_date = v_today
       where p.school_id = v_school and p.role = 'student' and p.left_at is null
         and p.grade is not null and p.class_num is not null
       group by p.grade, p.class_num
    ) t;

  select coalesce(json_object_agg(t.k, t.v), '{}'::json) into v_cats
    from (
      select e.key as k, round(avg(e.value::numeric), 1) as v
        from daily_checkins d, jsonb_each(d.category_scores) e
       where d.school_id = v_school
         and d.checkin_date between v_today - 13 and v_today
         and jsonb_typeof(e.value) = 'number'
       group by e.key
    ) t;

  return json_build_object(
    'ok', true,
    'total_students', v_total,
    'today_participants', v_today_n,
    'today_pct', case when v_total > 0 then round(100.0 * v_today_n / v_total, 1) else 0 end,
    'weekly_avg', coalesce(round(v_week_avg::numeric, 1), 0),
    'last_week_avg', coalesce(round(v_last_week_avg::numeric, 1), 0),
    'last14', coalesce(v_last14, '[]'::json),
    'class_participation', v_classes,
    'category_averages', v_cats);
end $$;
grant execute on function teacher_school_overview() to authenticated;

create or replace function teacher_class_stats(p_grade int, p_class int)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_ids uuid[]; v_n int; v_days json; v_cats json; v_weak json; v_nonp json;
begin
  select school_id, role into v_school, v_role from profiles where user_id = auth.uid();
  if v_school is null or v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 볼 수 있어요');
  end if;

  select coalesce(array_agg(user_id), '{}') into v_ids from profiles
   where school_id = v_school and role = 'student' and left_at is null
     and grade = p_grade and class_num = p_class;
  v_n := coalesce(array_length(v_ids, 1), 0);

  select json_agg(json_build_object(
           'date', to_char(g.d, 'YYYY-MM-DD'),
           'participants', coalesce(x.n, 0),
           'total', v_n) order by g.d)
    into v_days
    from generate_series(v_today - 13, v_today, interval '1 day') g(d)
    left join (
      select d.checkin_date, count(distinct d.user_id) n
        from daily_checkins d
       where d.user_id = any(v_ids)
         and d.checkin_date between v_today - 13 and v_today
       group by d.checkin_date
    ) x on x.checkin_date = g.d::date;

  select coalesce(json_object_agg(t.k, t.v), '{}'::json) into v_cats
    from (
      select e.key as k, round(avg(e.value::numeric), 1) as v
        from daily_checkins d
        cross join lateral jsonb_each(d.category_scores) e
       where d.user_id = any(v_ids)
         and d.checkin_date between v_today - 13 and v_today
         and jsonb_typeof(e.value) = 'number'
       group by e.key
    ) t;

  select coalesce(json_agg(json_build_object(
           'rule_id', t.rule_id, 'text', t.rule_text, 'avg_ok', t.avg_ok)
           order by t.avg_ok), '[]'::json)
    into v_weak
    from (
      select e.key as rule_id, max(sr.rule_text) as rule_text,
             avg(case when e.value = 'true' then 1.0 else 0.0 end) as avg_ok
        from daily_checkins d
        cross join lateral jsonb_each_text(d.answers) e
        join school_rules sr on sr.id::text = e.key and sr.school_id = v_school
       where d.user_id = any(v_ids)
         and d.checkin_date between v_today - 13 and v_today
         and e.value in ('true', 'false')
       group by e.key
       order by avg_ok
       limit 3
    ) t;

  select coalesce(json_agg(json_build_object(
           'nickname', p.nickname, 'grade', p.grade,
           'class_num', p.class_num, 'student_num', p.student_num)
           order by p.student_num nulls last), '[]'::json)
    into v_nonp
    from profiles p
   where p.user_id = any(v_ids)
     and not exists (select 1 from daily_checkins d
                      where d.user_id = p.user_id and d.checkin_date = v_today);

  return json_build_object(
    'ok', true,
    'student_count', v_n,
    'by_day', coalesce(v_days, '[]'::json),
    'category_averages', v_cats,
    'weakest_rules', v_weak,
    'non_participants_today', v_nonp);
end $$;
grant execute on function teacher_class_stats(int, int) to authenticated;

-- ═══════════ 2) 학생 총 점검 횟수 — 원본 + 학기 요약 ═══════════
create or replace function my_total_checkins()
returns int
language sql stable security definer set search_path = public, auth as $$
  select ((select count(*) from daily_checkins where user_id = auth.uid())
        + (select coalesce(sum(days_done), 0) from checkin_semester_summary
            where user_id = auth.uid()))::int;
$$;
grant execute on function my_total_checkins() to authenticated;

-- ═══════════ 3) 학교 새싹 — 10분 보관 ═══════════
create table if not exists school_growth_cache (
  school_id uuid primary key references schools(id) on delete cascade,
  payload jsonb not null,
  computed_at timestamptz not null default now()
);
alter table school_growth_cache enable row level security;   -- 함수로만 읽는다

create or replace function public.school_growth_compute(p_school uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_school uuid := p_school;
  v_name text;
  v_started date;
  v_year date := growth_year_start();
  v_year_ts timestamptz;
  v_from date;
  v_days int;

  v_rules int; v_roster int; v_students int;
  v_checkins bigint; v_active30 int;
  v_praise bigint; v_kodr bigint; v_kodr30 bigint; v_kodr_prev30 bigint;
  v_cico int; v_cico_grad int; v_rounds int; v_items int;
  v_exch bigint; v_votes bigint; v_ann int; v_weekly bigint;

  m1 boolean; m2 boolean; m3 boolean; m4 boolean;
  m5 boolean; m6 boolean; m7 boolean; m8 boolean;

  v_part numeric; v_kodr_mode text;
  a_part int; a_praise int; a_kodr int; a_cico int;
  a_items int; a_exch int; a_votes int; a_ann int; a_weekly int;
  v_score int; v_hist jsonb;
begin
  if v_school is null then
    raise exception '학교가 없어요.';
  end if;

  select name, created_at::date into v_name, v_started
    from schools where id = v_school;

  v_year_ts := v_year::timestamp at time zone 'Asia/Seoul';
  v_from := greatest(v_year, v_started);
  v_days := greatest((now() at time zone 'Asia/Seoul')::date - v_from, 0);

  select count(*) into v_rules from school_rules
    where school_id = v_school and is_active = true;
  select count(*) into v_roster from student_roster
    where school_id = v_school;
  -- 떠난 학생 제외
  select count(*) into v_students from profiles
    where school_id = v_school and role = 'student' and left_at is null;
  select count(*) into v_items from point_store_items
    where school_id = v_school;

  -- 학기 요약으로 정리된 점검도 '이번 학년도 점검' 으로 센다 (060)
  select (select count(*) from daily_checkins
           where school_id = v_school and checkin_date >= v_year)
       + (select coalesce(sum(days_done), 0) from checkin_semester_summary
           where school_id = v_school and semester_start >= v_year)
    into v_checkins;
  select count(distinct d.user_id) into v_active30
    from daily_checkins d
    join profiles p on p.user_id = d.user_id and p.left_at is null
   where d.school_id = v_school
     and d.checkin_date >= current_date - interval '30 days';
  select count(*) into v_praise from praise
    where school_id = v_school and created_at >= v_year_ts;
  select count(*) into v_kodr from kodr_records
    where school_id = v_school and occurred_date >= v_year;
  select count(*) into v_kodr30 from kodr_records
    where school_id = v_school and occurred_date >= current_date - 30;
  select count(*) into v_kodr_prev30 from kodr_records
    where school_id = v_school
      and occurred_date >= current_date - 60
      and occurred_date <  current_date - 30;
  select count(*) into v_cico from cico_enrollments
    where school_id = v_school and created_at >= v_year_ts;
  select count(*) into v_cico_grad from cico_enrollments
    where school_id = v_school and status = 'graduated'
      and coalesce(end_date, start_date) >= v_year;
  select count(*) into v_rounds from vote_rounds
    where school_id = v_school and created_at >= v_year_ts;
  select count(*) into v_exch from point_exchanges
    where school_id = v_school and status = 'fulfilled'
      and coalesce(fulfilled_at, requested_at) >= v_year_ts;
  select count(*) into v_votes from class_votes
    where school_id = v_school and created_at >= v_year_ts;
  select count(*) into v_ann from announcements
    where school_id = v_school and created_at >= v_year_ts;
  select count(*) into v_weekly from point_transactions
    where school_id = v_school and reason = 'checkin_weekly'
      and created_at >= v_year_ts;

  m1 := v_rules >= 5;
  m2 := v_roster > 0;
  m3 := v_roster > 0 and v_students >= v_roster * 0.5;
  m4 := v_checkins > 0;
  m5 := v_praise > 0;
  m6 := v_kodr > 0;
  m7 := v_cico > 0;
  m8 := v_rounds > 0;

  v_part := case when v_students > 0
                 then round(v_active30::numeric / v_students * 100, 1)
                 else 0 end;
  a_part := least((v_part / 2.5)::int, 40);
  a_praise := least((v_praise / 10)::int, 25);

  if v_days < 90 then
    v_kodr_mode := 'early';
    a_kodr := least((v_kodr * 2)::int, 20);
  elsif v_kodr30 <= v_kodr_prev30 then
    v_kodr_mode := 'down';
    a_kodr := 20;
  else
    v_kodr_mode := 'up';
    a_kodr := 5;
  end if;

  a_cico   := least(v_cico_grad * 5, 15);
  a_items  := least(v_items * 2, 10);
  a_exch   := least((v_exch / 5)::int, 15);
  a_votes  := least((v_votes / 10)::int, 15);
  a_ann    := least(v_ann * 2, 10);
  a_weekly := least((v_weekly / 10)::int, 10);

  v_score :=
    (case when m1 then 10 else 0 end) + (case when m2 then 10 else 0 end) +
    (case when m3 then 10 else 0 end) + (case when m4 then 10 else 0 end) +
    (case when m5 then 10 else 0 end) + (case when m6 then 10 else 0 end) +
    (case when m7 then 10 else 0 end) + (case when m8 then 10 else 0 end) +
    a_part + a_praise + a_kodr + a_cico +
    a_items + a_exch + a_votes + a_ann + a_weekly;

  select coalesce(jsonb_agg(
           jsonb_build_object('year',  growth_year_label(y.year_start),
                              'level', y.peak_level,
                              'score', y.peak_score)
           order by y.year_start desc), '[]'::jsonb)
    into v_hist
  from school_growth_year y
  where y.school_id = v_school and y.year_start < v_year;

  return jsonb_build_object(
    'school_name', v_name,
    'score', v_score,
    'days', v_days,
    'year_start', v_year,
    'year_label', growth_year_label(v_year),
    'history', v_hist,
    'missions', jsonb_build_array(
      jsonb_build_object('key','rules',   'label','우리 학교 규칙 만들기 (5개 이상)', 'done', m1),
      jsonb_build_object('key','roster',  'label','전교생 명단 등록하기',            'done', m2),
      jsonb_build_object('key','join',    'label','학생 절반 이상 가입하기',          'done', m3),
      jsonb_build_object('key','checkin', 'label','첫 일일 자기점검 받기',            'done', m4),
      jsonb_build_object('key','praise',  'label','첫 칭찬 보내기',                  'done', m5),
      jsonb_build_object('key','kodr',    'label','첫 K-ODR 기록하기',              'done', m6),
      jsonb_build_object('key','cico',    'label','첫 CICO 동행점검 시작하기',        'done', m7),
      jsonb_build_object('key','vote',    'label','수업맛집 투표 열기',              'done', m8)
    ),
    'activity', jsonb_build_object(
      'participation', v_part,       'participation_pts', a_part,
      'praise_total', v_praise,      'praise_pts', a_praise,
      'kodr_mode', v_kodr_mode,      'kodr_total', v_kodr,   'kodr_pts', a_kodr,
      'cico_graduated', v_cico_grad, 'cico_pts', a_cico,
      'store_items', v_items,        'store_pts', a_items,
      'exchanges', v_exch,           'exchange_pts', a_exch,
      'votes_cast', v_votes,         'vote_pts', a_votes,
      'announcements', v_ann,        'announce_pts', a_ann,
      'weekly_bonus', v_weekly,      'weekly_pts', a_weekly
    )
  );
end $$;
revoke all on function public.school_growth_compute(uuid) from public, anon, authenticated;

--   앱이 부르는 이름은 그대로 둔다. 구버전 앱도 바로 빨라진다.
--   (stable → volatile: 보관 값을 써야 해서. 앱은 POST 로 부르므로 영향 없음)
create or replace function public.school_growth()
returns jsonb
language plpgsql volatile security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  v_key bigint;
  v_payload jsonb;
  v_at timestamptz;
begin
  if v_school is null then
    raise exception '로그인이 필요해요.';
  end if;

  select payload, computed_at into v_payload, v_at
    from school_growth_cache where school_id = v_school;
  if v_payload is not null and v_at > now() - interval '10 minutes' then
    return v_payload;
  end if;

  -- 읽기 전용으로 불린 경우(다른 조회 함수 안) 저장하지 않고 계산만 한다
  if current_setting('transaction_read_only') = 'on' then
    return school_growth_compute(v_school);
  end if;

  v_key := hashtextextended('school_growth:' || v_school::text, 0);
  if not pg_try_advisory_xact_lock(v_key) then
    -- 누군가 이미 다시 계산하는 중. 직전 값이 있으면 그걸 준다.
    if v_payload is not null then
      return v_payload;
    end if;
    perform pg_advisory_xact_lock(v_key);
    select payload, computed_at into v_payload, v_at
      from school_growth_cache where school_id = v_school;
    if v_payload is not null and v_at > now() - interval '10 minutes' then
      return v_payload;
    end if;
  end if;

  v_payload := school_growth_compute(v_school);
  insert into school_growth_cache (school_id, payload, computed_at)
  values (v_school, v_payload, now())
  on conflict (school_id) do update
    set payload = excluded.payload, computed_at = excluded.computed_at;
  return v_payload;
end $$;
revoke all on function public.school_growth() from public;
grant execute on function public.school_growth() to authenticated;

-- ═══════════ 4) 이 주의 명예 식집사 — 5분 보관 ═══════════
create table if not exists weekly_honor_cache (
  school_id uuid not null references schools(id) on delete cascade,
  week_start date not null,
  ranks jsonb not null default '[]'::jsonb,
  computed_at timestamptz not null default now(),
  primary key (school_id, week_start)
);
alter table weekly_honor_cache enable row level security;   -- 함수로만 읽는다

create or replace function weekly_honor_rank_cached(p_school uuid, p_week date)
returns table (
  user_id uuid, grade int, class_num int, nickname text,
  days_done int, avg_pct int, praise_cnt int, score int, rn int
)
language plpgsql volatile security definer set search_path = public, auth as $$
declare
  v_this date := date_trunc('week', (now() at time zone 'Asia/Seoul')::date)::date;
  v_ttl interval;
  v_key bigint := hashtextextended('weekly_honor:' || p_school::text || ':' || p_week::text, 0);
  v_ranks jsonb;
  v_at timestamptz;
begin
  -- 지난주 순위는 바뀌지 않으니 오래 보관한다
  v_ttl := case when p_week < v_this then interval '6 hours' else interval '5 minutes' end;

  select w.ranks, w.computed_at into v_ranks, v_at
    from weekly_honor_cache w
   where w.school_id = p_school and w.week_start = p_week;

  if (v_ranks is null or v_at < now() - v_ttl)
     and current_setting('transaction_read_only') = 'on' then
    return query select * from weekly_honor_rank(p_school, p_week);
    return;
  end if;

  if v_ranks is null or v_at < now() - v_ttl then
    if v_ranks is null or pg_try_advisory_xact_lock(v_key) then
      perform pg_advisory_xact_lock(v_key);   -- 같은 트랜잭션에서 다시 잡아도 된다
      select w.ranks, w.computed_at into v_ranks, v_at
        from weekly_honor_cache w
       where w.school_id = p_school and w.week_start = p_week;
      if v_ranks is null or v_at < now() - v_ttl then
        select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into v_ranks
          from weekly_honor_rank(p_school, p_week) r;
        insert into weekly_honor_cache as w (school_id, week_start, ranks, computed_at)
        values (p_school, p_week, v_ranks, now())
        on conflict (school_id, week_start) do update
          set ranks = excluded.ranks, computed_at = excluded.computed_at;
        delete from weekly_honor_cache w
         where w.school_id = p_school and w.week_start < v_this - 14;
      end if;
    end if;
  end if;

  return query
    select (e->>'user_id')::uuid, (e->>'grade')::int, (e->>'class_num')::int,
           e->>'nickname', (e->>'days_done')::int, (e->>'avg_pct')::int,
           (e->>'praise_cnt')::int, (e->>'score')::int, (e->>'rn')::int
      from jsonb_array_elements(coalesce(v_ranks, '[]'::jsonb)) e;
end $$;
revoke all on function weekly_honor_rank_cached(uuid, date) from public, anon, authenticated;

create or replace function weekly_honor_gardeners()
returns json
language plpgsql volatile security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_this date := date_trunc('week', v_today)::date;
  v_week date;
  v_which text;
  v_items json;
begin
  if v_school is null then
    return json_build_object('ok', false);
  end if;

  if exists (select 1 from weekly_honor_rank_cached(v_school, v_this) r where r.rn = 1) then
    v_week := v_this; v_which := 'this';
  else
    v_week := v_this - 7; v_which := 'last';
  end if;

  select coalesce(json_agg(json_build_object(
           'label', r.grade || '-' || r.class_num || ' ' || mask_name(r.nickname),
           'grade', r.grade,
           'class_num', r.class_num,
           'is_me', r.user_id = auth.uid())
         order by r.grade, r.class_num), '[]'::json)
    into v_items
    from weekly_honor_rank_cached(v_school, v_week) r
   where r.rn = 1;

  return json_build_object('ok', true, 'week', v_which,
                           'week_start', v_week, 'items', v_items);
end $$;
grant execute on function weekly_honor_gardeners() to authenticated;

create or replace function my_weekly_honor()
returns json
language plpgsql volatile security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  v_this date := date_trunc('week', (now() at time zone 'Asia/Seoul')::date)::date;
  v_me record;
  v_top int;
begin
  if v_school is null then
    return json_build_object('ok', false);
  end if;

  select * into v_me
    from weekly_honor_rank_cached(v_school, v_this) r
   where r.user_id = auth.uid();
  if not found then
    return json_build_object('ok', true, 'joined', false);
  end if;

  select r.score into v_top
    from weekly_honor_rank_cached(v_school, v_this) r
   where r.grade = v_me.grade and r.class_num = v_me.class_num and r.rn = 1;

  return json_build_object(
    'ok', true, 'joined', true,
    'score', v_me.score, 'rank', v_me.rn,
    'days_done', v_me.days_done, 'avg_pct', v_me.avg_pct,
    'praise_cnt', v_me.praise_cnt,
    'gap', greatest(0, coalesce(v_top, 0) - v_me.score),
    'is_top', v_me.rn = 1);
end $$;
grant execute on function my_weekly_honor() to authenticated;

-- ═══════════ 5) 확인 ═══════════
--   select count(*) from school_growth_cache;          -- 앱을 연 학교 수만큼 생긴다
--   select school_id, week_start, computed_at, jsonb_array_length(ranks)
--     from weekly_honor_cache order by computed_at desc;
