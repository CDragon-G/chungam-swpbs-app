-- 060_checkin_semester_compaction.sql
-- 일일 자기점검 원본을 학기가 끝나면 '학기 요약' 으로 바꾸고 원본은 지운다.
--
-- 왜
--   점검 한 건에는 규칙마다의 O/X 가 모두 들어 있다. 학생 한 명이 한 학기에
--   90~100건을 쌓는데, 학기가 지난 뒤 이 원본을 다시 볼 일은 거의 없다.
--   앱이 원본을 읽는 가장 긴 기간은 90일(규칙별 실천 현황)이다.
--
--   · 개인정보는 필요한 만큼만, 필요한 기간만 보관하는 것이 원칙이다
--   · 표가 작아지면 조회·백업·복구가 빨라진다
--   (비용 효과는 작다. 저장 공간은 서버 비용의 1% 안팎이다.)
--
-- 무엇을 남기나 (지우기 전에 먼저 만든다)
--   checkin_semester_summary    학생 × 학기: 점검 일수, 평균 점수, 영역별 평균
--   checkin_rule_semester_stats 학교 × 학기 × 규칙: O/X 건수 (규칙 문구도 함께)
--   checkin_school_daily        학교 × 날짜: 참여 인원, 평균 점수 (추이 · 갱신 보고서용)
--
-- 무엇을 지우지 않나
--   포인트(point_transactions) · 칭찬 · K-ODR · CICO · 학맞통 안건은 그대로다.
--   K-ODR 은 학맞통 근거 자료라 절대 건드리지 않는다.
--
-- 학기 구분
--   1학기 3월 1일 ~ 7월 31일 / 2학기 8월 1일 ~ 다음 해 2월 말
--   (2학기 개학이 8월 중순이라 8월 1일에 끊으면 2학기 기록이 1학기로 섞이지 않는다)
--
-- 실행
--   되돌릴 수 없는 삭제라 자동으로 돌지 않는다. SQL 에디터에서 직접 실행한다.
--     select compact_checkins();                    -- 미리보기 (아무것도 지우지 않음)
--     select compact_checkins(p_dry_run => false);  -- 실제 실행

-- ═══════════ 1) 학기 ═══════════
create or replace function semester_start(p_date date default null)
returns date
language sql stable as $$
  select case
    when extract(month from d) >= 8 then make_date(extract(year from d)::int, 8, 1)
    when extract(month from d) >= 3 then make_date(extract(year from d)::int, 3, 1)
    else make_date(extract(year from d)::int - 1, 8, 1)
  end
  from (select coalesce(p_date, (now() at time zone 'Asia/Seoul')::date) as d) t;
$$;
grant execute on function semester_start(date) to authenticated;

create or replace function semester_label(p_start date)
returns text
language sql immutable as $$
  select case when extract(month from p_start) = 3
              then extract(year from p_start)::int || '학년도 1학기'
              else extract(year from p_start)::int || '학년도 2학기' end;
$$;

-- ═══════════ 2) 요약 표 ═══════════
create table if not exists checkin_semester_summary (
  user_id uuid not null references auth.users(id) on delete cascade,
  school_id uuid not null references schools(id) on delete cascade,
  semester_start date not null,
  days_done int not null default 0,
  avg_pct numeric(5,1) not null default 0,
  category_avg jsonb not null default '{}'::jsonb,
  first_date date,
  last_date date,
  compacted_at timestamptz not null default now(),
  primary key (user_id, semester_start)
);
create index if not exists css_school_idx
  on checkin_semester_summary (school_id, semester_start);
alter table checkin_semester_summary enable row level security;
drop policy if exists css_own_read on checkin_semester_summary;
create policy css_own_read on checkin_semester_summary
  for select to authenticated using (user_id = auth.uid());

create table if not exists checkin_rule_semester_stats (
  school_id uuid not null references schools(id) on delete cascade,
  semester_start date not null,
  rule_id uuid not null,
  rule_text text,
  total int not null default 0,
  kept int not null default 0,
  primary key (school_id, semester_start, rule_id)
);
alter table checkin_rule_semester_stats enable row level security;

create table if not exists checkin_school_daily (
  school_id uuid not null references schools(id) on delete cascade,
  checkin_date date not null,
  participants int not null default 0,
  avg_pct numeric(5,1) not null default 0,
  primary key (school_id, checkin_date)
);
alter table checkin_school_daily enable row level security;

-- ═══════════ 3) 요약하고 지우기 ═══════════
--   SECURITY DEFINER 가 아니다. 앱 사용자는 부를 수 없고
--   SQL 에디터(postgres) 나 서비스 키로만 실행된다.
create or replace function compact_checkins(
  p_before date default null,        -- 이 날짜 '이전' 기록을 정리 (기본: 이번 학기 시작일)
  p_dry_run boolean default true,    -- true 면 세기만 한다
  p_school uuid default null         -- 학교 하나만 (학교가 많아지면 나눠서 실행)
)
returns json
language plpgsql set search_path = public as $$
declare
  v_before date := coalesce(p_before, semester_start());
  v_rows bigint; v_users bigint; v_schools bigint;
  v_bytes bigint; v_from date; v_to date;
  v_deleted bigint;
begin
  -- 이번 학기 기록은 지울 수 없다
  if v_before > semester_start() then
    raise exception '이번 학기(% 시작) 기록은 정리할 수 없어요. p_before 는 % 이전이어야 해요.',
      semester_start(), semester_start();
  end if;

  select count(*), count(distinct user_id), count(distinct school_id),
         coalesce(sum(pg_column_size(d.*)), 0), min(checkin_date), max(checkin_date)
    into v_rows, v_users, v_schools, v_bytes, v_from, v_to
    from daily_checkins d
   where checkin_date < v_before
     and (p_school is null or school_id = p_school);

  if p_dry_run or v_rows = 0 then
    return json_build_object(
      'dry_run', p_dry_run,
      'before', v_before,
      'rows', v_rows,
      'students', v_users,
      'schools', v_schools,
      'from', v_from,
      'to', v_to,
      'approx_mb', round(v_bytes / 1048576.0, 1),
      'note', case when p_dry_run
                   then '미리보기예요. 실제로 정리하려면 p_dry_run => false 로 실행하세요.'
                   else '정리할 기록이 없어요.' end);
  end if;

  -- (1) 학교 × 날짜
  insert into checkin_school_daily (school_id, checkin_date, participants, avg_pct)
  select school_id, checkin_date, count(distinct user_id), round(avg(score_pct)::numeric, 1)
    from daily_checkins
   where checkin_date < v_before and (p_school is null or school_id = p_school)
   group by school_id, checkin_date
  on conflict (school_id, checkin_date) do update
    set participants = excluded.participants, avg_pct = excluded.avg_pct;

  -- (2) 학생 × 학기 (영역별 평균 포함). 같은 학기가 이미 있으면 가중 합친다.
  insert into checkin_semester_summary
    (user_id, school_id, semester_start, days_done, avg_pct, category_avg, first_date, last_date)
  select b.user_id, b.school_id, b.sem, b.days, b.avg_pct,
         coalesce(c.cat, '{}'::jsonb), b.first_date, b.last_date
    from (
      select user_id, school_id, semester_start(checkin_date) as sem,
             count(*)::int as days, round(avg(score_pct)::numeric, 1) as avg_pct,
             min(checkin_date) as first_date, max(checkin_date) as last_date
        from daily_checkins
       where checkin_date < v_before and (p_school is null or school_id = p_school)
       group by user_id, school_id, semester_start(checkin_date)
    ) b
    left join (
      select user_id, sem, jsonb_object_agg(k, v) as cat
        from (
          select d.user_id, semester_start(d.checkin_date) as sem, e.key as k,
                 round(avg(e.value::numeric), 1) as v
            from daily_checkins d, jsonb_each_text(coalesce(d.category_scores, '{}'::jsonb)) e
           where d.checkin_date < v_before and (p_school is null or d.school_id = p_school)
             and e.value ~ '^-?[0-9.]+$'
           group by d.user_id, semester_start(d.checkin_date), e.key
        ) x
       group by user_id, sem
    ) c on c.user_id = b.user_id and c.sem = b.sem
  on conflict (user_id, semester_start) do update
    set avg_pct = round(((checkin_semester_summary.avg_pct * checkin_semester_summary.days_done)
                        + (excluded.avg_pct * excluded.days_done))
                        / nullif(checkin_semester_summary.days_done + excluded.days_done, 0), 1),
        days_done = checkin_semester_summary.days_done + excluded.days_done,
        first_date = least(checkin_semester_summary.first_date, excluded.first_date),
        last_date = greatest(checkin_semester_summary.last_date, excluded.last_date),
        compacted_at = now();

  -- (3) 학교 × 학기 × 규칙 O/X
  insert into checkin_rule_semester_stats
    (school_id, semester_start, rule_id, rule_text, total, kept)
  select d.school_id, semester_start(d.checkin_date), e.key::uuid,
         max(sr.rule_text), count(*)::int,
         count(*) filter (where e.value = 'true')::int
    from daily_checkins d
    cross join lateral jsonb_each_text(coalesce(d.answers, '{}'::jsonb)) e
    left join school_rules sr on sr.id::text = e.key
   where d.checkin_date < v_before and (p_school is null or d.school_id = p_school)
     and e.key ~ '^[0-9a-f-]{36}$'
     and e.value in ('true', 'false')
   group by d.school_id, semester_start(d.checkin_date), e.key
  on conflict (school_id, semester_start, rule_id) do update
    set total = checkin_rule_semester_stats.total + excluded.total,
        kept = checkin_rule_semester_stats.kept + excluded.kept,
        rule_text = coalesce(excluded.rule_text, checkin_rule_semester_stats.rule_text);

  -- (4) 원본 삭제 — 요약이 모두 성공해야 여기까지 온다 (한 트랜잭션)
  delete from daily_checkins
   where checkin_date < v_before and (p_school is null or school_id = p_school);
  get diagnostics v_deleted = row_count;

  return json_build_object(
    'dry_run', false,
    'before', v_before,
    'deleted', v_deleted,
    'students', v_users,
    'schools', v_schools,
    'from', v_from,
    'to', v_to,
    'freed_mb_approx', round(v_bytes / 1048576.0, 1));
end $$;
revoke all on function compact_checkins(date, boolean, uuid) from public, anon, authenticated;

-- ═══════════ 4) 갱신 안내 보고서 — 요약도 함께 센다 ═══════════
--   renewal_batch() 는 최근 1년 참여 현황을 보고서에 넣는다. 원본이 학기마다 정리되면
--   숫자가 줄어들므로 학기 요약을 더해서 센다.
create or replace function public.renewal_batch()
returns table (
  school_id uuid,
  school_name text,
  contact_email text,
  contact_name text,
  auto_renew boolean,
  stage text,
  days_left int,
  expires_at date,
  grace_until date,
  student_count int,
  metrics jsonb
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and coalesce(auth.jwt() ->> 'email', '') <> 'toyswar987@naver.com' then
    raise exception '권한이 없어요.';
  end if;

  return query
  with base as (
    select s.*, (s.subscription_expires_at - current_date) as dleft
    from schools s
    where s.subscription_status = 'active'
      and s.subscription_expires_at is not null
  ),
  staged as (
    select b.*,
      case
        when b.dleft between 8 and 30 then 'd30'
        when b.dleft between 2 and 7  then 'd7'
        when b.dleft between 0 and 1  then 'd1'
        when b.dleft < 0 and (b.grace_until is null or b.grace_until >= current_date) then 'grace'
        when b.dleft < 0 and b.grace_until is not null and b.grace_until < current_date then 'churn'
        else null
      end as tgt_stage
    from base b
  ),
  ranked as (
    select st.*,
      case st.tgt_stage
        when 'd30' then 1 when 'd7' then 2 when 'd1' then 3
        when 'grace' then 4 when 'churn' then 5 else 0 end as tgt_rank,
      case st.last_renewal_stage
        when 'd30' then 1 when 'd7' then 2 when 'd1' then 3
        when 'grace' then 4 when 'churn' then 5 else 0 end as sent_rank
    from staged st
  )
  select
    r.id,
    r.name,
    coalesce(
      (select pr.contact_email from purchase_requests pr
        where pr.school_id = r.id and coalesce(pr.contact_email, '') <> ''
        order by pr.created_at desc limit 1),
      (select u.email::text from auth.users u where u.id = r.created_by)
    ),
    coalesce(
      (select pr.contact_name from purchase_requests pr
        where pr.school_id = r.id and coalesce(pr.contact_name, '') <> ''
        order by pr.created_at desc limit 1),
      '담당 선생님'
    ),
    r.auto_renew,
    r.tgt_stage,
    r.dleft,
    r.subscription_expires_at,
    r.grace_until,
    (select count(*)::int from profiles p where p.school_id = r.id and p.role = 'student'),
    jsonb_build_object(
      'active', m.active,
      'checkins', m.cnt,
      'avg_score', round(m.avgp::numeric, 1),
      'praise', (select count(*) from praise pz
                   where pz.school_id = r.id and pz.created_at >= current_date - interval '1 year'),
      'kodr', (select count(*) from kodr_records kr
                 where kr.school_id = r.id and kr.occurred_date >= (current_date - interval '1 year')::date),
      'cico_grad', (select count(*) from cico_enrollments ce
                      where ce.school_id = r.id and ce.status = 'graduated')
    )
  from ranked r
  left join lateral (
    select count(distinct x.u) as active,
           coalesce(sum(x.n), 0) as cnt,
           coalesce(sum(x.n * x.pct) / nullif(sum(x.n), 0), 0) as avgp
    from (
      select dcx.user_id as u, 1 as n, dcx.score_pct::numeric as pct
        from daily_checkins dcx
       where dcx.school_id = r.id
         and dcx.checkin_date >= (current_date - interval '1 year')::date
      union all
      select cs.user_id, cs.days_done, cs.avg_pct
        from checkin_semester_summary cs
       where cs.school_id = r.id
         and cs.last_date >= (current_date - interval '1 year')::date
    ) x
  ) m on true
  where r.tgt_stage is not null
    and r.tgt_rank > r.sent_rank
  order by r.dleft asc;
end $$;
revoke all on function public.renewal_batch() from public;
grant execute on function public.renewal_batch() to authenticated, service_role;

-- ═══════════ 5) 학교 새싹 '첫 점검' 미션 — 요약도 센다 ═══════════
--   8월에 1학기 원본을 정리하면 2학기 첫 점검 전까지 '첫 일일 자기점검 받기'
--   미션이 꺼져 새싹이 한 단계 내려가 보일 수 있다. 아래에서 school_growth() 를
--   다시 정의하며 학기 요약의 점검 일수도 함께 센다. (본문은 055 와 같다)

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
    raise exception '로그인이 필요해요.';
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
revoke all on function public.school_growth() from public;
grant execute on function public.school_growth() to authenticated;

-- ═══════════ 6) 매 학기 자동 실행 (선택) ═══════════
--   처음 한 번은 미리보기로 숫자를 확인하고 직접 실행하세요.
--   괜찮으면 아래를 실행해 매년 3월 2일 · 8월 2일 새벽 3시(한국)에 자동으로 돌게 합니다.
--   (pg_cron 은 UTC 기준 → 한국 03:00 = UTC 18:00 전날)
--
--   create extension if not exists pg_cron;
--   select cron.schedule('compact-checkins-mar', '0 18 1 3 *',
--          $$select compact_checkins(p_dry_run => false)$$);
--   select cron.schedule('compact-checkins-aug', '0 18 1 8 *',
--          $$select compact_checkins(p_dry_run => false)$$);
--
--   끄기: select cron.unschedule('compact-checkins-mar');
--         select cron.unschedule('compact-checkins-aug');
