-- 051_growth_school_year.sql
-- 학교 성장을 '학년도' 단위로 바꾼다.
--
-- 왜
--   지금까지 성장 점수는 도입일부터 전부 누적이었다. 그래서 3월이 되어도
--   지난해 기록 위에 계속 쌓였고, 정작 새로 들어온 학생들은 자기가 키우지
--   않은 나무를 물려받았다. 게다가 졸업생 프로필이 참여율 분모에 남아
--   3~4월에 점수가 무너지면서 레벨이 내려가는 이상한 일도 생겼다.
--
--   새 학생들과 새로 시작하는 편이 맞다. 3월 1일이면 다시 씨앗부터.
--
-- 무엇이 바뀌나
--   · 활동 집계 창이 '학년도(3/1 ~ 다음해 2/28)' 로 좁혀진다
--   · days 가 '도입 후 경과일' → '이번 학년도 경과일' 로 바뀐다
--   · 지난 학년도 최고 기록은 school_growth_year 에 남는다 (지워지지 않음)
--   · 학년도가 바뀌는 순간에는 레벨업 축하 팝업이 뜨지 않는다
--
-- 무엇이 그대로인가
--   · 포인트, 칭찬 기록, K-ODR 원본 데이터는 하나도 지우지 않는다.
--     '점수를 세는 기간' 만 바뀐다.

-- ═══════════ 1) 학년도 ═══════════
--   3월 1일 시작. 1~2월은 직전 학년도에 속한다.
create or replace function growth_year_start(p_date date default null)
returns date
language sql stable set search_path = public as $$
  select make_date(
           extract(year from d)::int
             - (case when extract(month from d) < 3 then 1 else 0 end),
           3, 1)
  from (select coalesce(p_date, (now() at time zone 'Asia/Seoul')::date) as d) t;
$$;

create or replace function growth_year_label(p_year_start date)
returns text
language sql immutable set search_path = public as $$
  select extract(year from p_year_start)::int || '학년도';
$$;

grant execute on function growth_year_start(date) to authenticated;
grant execute on function growth_year_label(date) to authenticated;

-- ═══════════ 2) 학년도별 최고 기록 ═══════════
--   리셋은 하되 기록은 남긴다. 3년을 가꾼 학교는 그 사실이 보여야 한다.
create table if not exists school_growth_year (
  school_id  uuid not null references schools(id) on delete cascade,
  year_start date not null,
  peak_level int  not null default 1,
  peak_score int  not null default 0,
  updated_at timestamptz not null default now(),
  primary key (school_id, year_start)
);
alter table school_growth_year enable row level security;

drop policy if exists sgy_read on school_growth_year;
create policy sgy_read on school_growth_year
  for select to authenticated using (school_id = current_profile_school());

-- ═══════════ 3) 성장 점수 — 학년도 기준 ═══════════
create or replace function public.school_growth()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_school uuid := current_profile_school();
  v_name text;
  v_started date;
  v_year date := growth_year_start();
  v_year_ts timestamptz;
  v_from date;
  v_days int;

  v_rules int;
  v_roster int;
  v_students int;
  v_checkins bigint;
  v_active30 int;
  v_praise bigint;
  v_kodr bigint;
  v_kodr30 bigint;
  v_kodr_prev30 bigint;
  v_cico int;
  v_cico_grad int;
  v_rounds int;
  v_items int;
  v_exch bigint;
  v_votes bigint;
  v_ann int;
  v_weekly bigint;

  m1 boolean; m2 boolean; m3 boolean; m4 boolean;
  m5 boolean; m6 boolean; m7 boolean; m8 boolean;

  v_part numeric;
  v_kodr_mode text;
  a_part int; a_praise int; a_kodr int; a_cico int;
  a_items int; a_exch int; a_votes int; a_ann int; a_weekly int;
  v_score int;
  v_hist jsonb;
begin
  if v_school is null then
    raise exception '로그인이 필요해요.';
  end if;

  select name, created_at::date into v_name, v_started
    from schools where id = v_school;

  v_year_ts := v_year::timestamp at time zone 'Asia/Seoul';
  -- 학년도 중간에 도입한 학교는 도입일부터 센다.
  -- (안 그러면 11월에 시작한 학교가 첫날부터 '270일 함께한 학교'가 된다)
  v_from := greatest(v_year, v_started);
  v_days := greatest((now() at time zone 'Asia/Seoul')::date - v_from, 0);

  -- ── 지금의 상태 (학년도와 무관) ──────────────────
  select count(*) into v_rules from school_rules
    where school_id = v_school and is_active = true;
  select count(*) into v_roster from student_roster
    where school_id = v_school;
  select count(*) into v_students from profiles
    where school_id = v_school and role = 'student';
  select count(*) into v_items from point_store_items
    where school_id = v_school;

  -- ── 이번 학년도의 실천 ───────────────────────────
  select count(*) into v_checkins from daily_checkins
    where school_id = v_school and checkin_date >= v_year;
  select count(distinct user_id) into v_active30 from daily_checkins
    where school_id = v_school
      and checkin_date >= current_date - interval '30 days';
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

  -- ── 미션 (각 10점) ──────────────────────────────
  m1 := v_rules >= 5;
  m2 := v_roster > 0;
  m3 := v_roster > 0 and v_students >= v_roster * 0.5;
  m4 := v_checkins > 0;
  m5 := v_praise > 0;
  m6 := v_kodr > 0;
  m7 := v_cico > 0;
  m8 := v_rounds > 0;

  -- ── 활동 점수 (9종, 합계 최대 160) ──────────────
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

  -- ── 지난 학년도 기록 ────────────────────────────
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'year',  growth_year_label(y.year_start),
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
revoke all on function public.school_growth() from public;
grant execute on function public.school_growth() to authenticated;

-- ═══════════ 4) 레벨업 축하 — 학년도 전환은 조용히 ═══════════
alter table growth_level_seen
  add column if not exists year_start date;

--   기존 행은 이번 학년도 것으로 본다 (설치 직후 축하 폭탄 방지)
update growth_level_seen
   set year_start = growth_year_start()
 where year_start is null;

drop function if exists check_growth_level(int);

create or replace function check_growth_level(
  p_level int,
  p_score int default 0
)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid;
  v_prev int;
  v_prev_year date;
  v_year date := growth_year_start();
begin
  select school_id into v_school from profiles where user_id = auth.uid();
  if v_school is null or p_level is null or p_level < 1 then
    return json_build_object('leveled_up', false);
  end if;

  select level, year_start into v_prev, v_prev_year
    from growth_level_seen where user_id = auth.uid();

  -- 학교의 학년도 최고 기록 (리셋되지 않는 명예의 기록)
  insert into school_growth_year (school_id, year_start, peak_level, peak_score)
  values (v_school, v_year, p_level, greatest(coalesce(p_score, 0), 0))
  on conflict (school_id, year_start) do update
    set peak_level = greatest(school_growth_year.peak_level, excluded.peak_level),
        peak_score = greatest(school_growth_year.peak_score, excluded.peak_score),
        updated_at = now();

  -- 학년도가 바뀌었으면 조용히 기준만 새로 잡는다.
  -- 3월 1일에 "Lv.1 씨앗이 되었어요!" 팝업이 뜨면 그건 축하가 아니다.
  if v_prev_year is null or v_prev_year < v_year then
    insert into growth_level_seen (user_id, school_id, level, year_start)
    values (auth.uid(), v_school, p_level, v_year)
    on conflict (user_id) do update
      set level = excluded.level,
          year_start = excluded.year_start,
          school_id = excluded.school_id,
          seen_at = now();
    return json_build_object('leveled_up', false, 'year_reset', true);
  end if;

  insert into growth_level_seen (user_id, school_id, level, year_start)
  values (auth.uid(), v_school, p_level, v_year)
  on conflict (user_id) do update
    set level = greatest(growth_level_seen.level, excluded.level),
        year_start = excluded.year_start,
        school_id = excluded.school_id,
        seen_at = now();

  -- 처음 기록하는 사용자는 축하하지 않는다 (가입 직후 팝업 폭탄 방지)
  return json_build_object(
    'leveled_up', v_prev is not null and p_level > v_prev,
    'from', v_prev, 'to', p_level);
end $$;
grant execute on function check_growth_level(int, int) to authenticated;

-- ═══════════ 5) 확인 ═══════════
--   select growth_year_start();                  -- 이번 학년도 시작일
--   select school_growth();                      -- 지금 점수 (학년도 기준)
--   select * from school_growth_year order by year_start desc;
