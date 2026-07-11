-- 033_growth_sources.sql
-- 새싹 양분 다변화: 자람의 모든 기능이 성장 점수가 된다.
--   활동 점수 9종 (최대 160) + 미션 80 = 만점 240.
--   Lv.7 기준(앱: 160) 대비 여유 80점 — 학교마다 자기 방식으로 키울 수 있다.

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
  v_items int;          -- 강화물(상점 상품) 등록 수
  v_exch bigint;        -- 교환 수령 처리 수
  v_votes bigint;       -- 수업맛집 투표 참여 수
  v_ann int;            -- 공지 작성 수
  v_weekly bigint;      -- 주간 개근 보너스 달성 수

  m1 boolean; m2 boolean; m3 boolean; m4 boolean;
  m5 boolean; m6 boolean; m7 boolean; m8 boolean;

  v_part numeric;
  v_kodr_mode text;
  a_part int; a_praise int; a_kodr int; a_cico int;
  a_items int; a_exch int; a_votes int; a_ann int; a_weekly int;
  v_score int;
begin
  if v_school is null then
    raise exception '로그인이 필요해요.';
  end if;

  select name, created_at::date into v_name, v_started
    from schools where id = v_school;
  v_days := greatest((now() at time zone 'Asia/Seoul')::date - v_started, 0);

  select count(*) into v_rules from school_rules
    where school_id = v_school and is_active = true;
  select count(*) into v_roster from student_roster
    where school_id = v_school;
  select count(*) into v_students from profiles
    where school_id = v_school and role = 'student';
  select count(*) into v_checkins from daily_checkins
    where school_id = v_school;
  select count(distinct user_id) into v_active30 from daily_checkins
    where school_id = v_school
      and checkin_date >= current_date - interval '30 days';
  select count(*) into v_praise from praise where school_id = v_school;
  select count(*) into v_kodr from kodr_records where school_id = v_school;
  select count(*) into v_kodr30 from kodr_records
    where school_id = v_school and occurred_date >= current_date - 30;
  select count(*) into v_kodr_prev30 from kodr_records
    where school_id = v_school
      and occurred_date >= current_date - 60
      and occurred_date <  current_date - 30;
  select count(*) into v_cico from cico_enrollments where school_id = v_school;
  select count(*) into v_cico_grad from cico_enrollments
    where school_id = v_school and status = 'graduated';
  select count(*) into v_rounds from vote_rounds where school_id = v_school;
  select count(*) into v_items from point_store_items
    where school_id = v_school;
  select count(*) into v_exch from point_exchanges
    where school_id = v_school and status = 'fulfilled';
  select count(*) into v_votes from class_votes where school_id = v_school;
  select count(*) into v_ann from announcements where school_id = v_school;
  select count(*) into v_weekly from point_transactions
    where school_id = v_school and reason = 'checkin_weekly';

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
  a_part := least((v_part / 2.5)::int, 40);      -- 참여율 → 40

  a_praise := least((v_praise / 10)::int, 25);   -- 칭찬 → 25

  if v_days < 90 then
    v_kodr_mode := 'early';
    a_kodr := least((v_kodr * 2)::int, 20);      -- 초기: 작성이 양분
  elsif v_kodr30 <= v_kodr_prev30 then
    v_kodr_mode := 'down';
    a_kodr := 20;                                -- 감소 추세 = 예방 작동
  else
    v_kodr_mode := 'up';
    a_kodr := 5;
  end if;

  a_cico   := least(v_cico_grad * 5, 15);        -- CICO 졸업 → 15
  a_items  := least(v_items * 2, 10);            -- 강화물 등록 → 10
  a_exch   := least((v_exch / 5)::int, 15);      -- 교환 수령 → 15
  a_votes  := least((v_votes / 10)::int, 15);    -- 수업맛집 참여 → 15
  a_ann    := least(v_ann * 2, 10);              -- 공지 → 10
  a_weekly := least((v_weekly / 10)::int, 10);   -- 주간 개근 → 10

  v_score :=
    (case when m1 then 10 else 0 end) + (case when m2 then 10 else 0 end) +
    (case when m3 then 10 else 0 end) + (case when m4 then 10 else 0 end) +
    (case when m5 then 10 else 0 end) + (case when m6 then 10 else 0 end) +
    (case when m7 then 10 else 0 end) + (case when m8 then 10 else 0 end) +
    a_part + a_praise + a_kodr + a_cico +
    a_items + a_exch + a_votes + a_ann + a_weekly;

  return jsonb_build_object(
    'school_name', v_name,
    'score', v_score,
    'days', v_days,
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
