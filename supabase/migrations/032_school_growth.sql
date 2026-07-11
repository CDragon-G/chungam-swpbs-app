-- 032_school_growth.sql
-- 학교 공동 새싹 성장 시스템 ("자람"의 심장).
--   교사·학생이 함께 키우는 학교 새싹 — SWPBS 활동이 양분이 된다.
--   · 미션 8개 (튜토리얼 겸, 각 10점): 규칙 → 명단 → 가입 → 점검 → 칭찬 →
--     K-ODR → CICO → 수업맛집
--   · 활동 점수: 참여율(50) + 칭찬(30) + K-ODR 문화(20) + CICO 졸업(20)
--   · K-ODR 시기 반전: 도입 90일 전엔 "작성 자체"가 + (기록 문화 형성),
--     이후엔 최근 30일이 이전 30일보다 "줄어드는 추세"가 + (예방 효과)
--   총점 200. 레벨 구간은 앱에서 해석 (7단계).

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

  m1 boolean; m2 boolean; m3 boolean; m4 boolean;
  m5 boolean; m6 boolean; m7 boolean; m8 boolean;

  v_part numeric;      -- 최근 30일 참여율(%)
  v_kodr_mode text;    -- early | down | up
  a_part int; a_praise int; a_kodr int; a_cico int;
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
    where school_id = v_school
      and occurred_date >= current_date - 30;
  select count(*) into v_kodr_prev30 from kodr_records
    where school_id = v_school
      and occurred_date >= current_date - 60
      and occurred_date <  current_date - 30;
  select count(*) into v_cico from cico_enrollments where school_id = v_school;
  select count(*) into v_cico_grad from cico_enrollments
    where school_id = v_school and status = 'graduated';
  select count(*) into v_rounds from vote_rounds where school_id = v_school;

  -- ── 미션 (각 10점) ──────────────────────────────
  m1 := v_rules >= 5;                                   -- 우리 학교 규칙 만들기
  m2 := v_roster > 0;                                   -- 전교생 명단 등록
  m3 := v_roster > 0 and v_students >= v_roster * 0.5;  -- 학생 절반 가입
  m4 := v_checkins > 0;                                 -- 첫 일일 자기점검
  m5 := v_praise > 0;                                   -- 첫 칭찬 보내기
  m6 := v_kodr > 0;                                     -- 첫 K-ODR (기록 문화 시작)
  m7 := v_cico > 0;                                     -- 첫 CICO 동행점검
  m8 := v_rounds > 0;                                   -- 수업맛집 투표 열기

  -- ── 활동 점수 ───────────────────────────────────
  v_part := case when v_students > 0
                 then round(v_active30::numeric / v_students * 100, 1)
                 else 0 end;
  a_part := least((v_part / 2)::int, 50);               -- 참여율 → 최대 50

  a_praise := least((v_praise / 10)::int, 30);          -- 칭찬 10개당 1점, 최대 30

  if v_days < 90 then
    v_kodr_mode := 'early';
    a_kodr := least((v_kodr * 2)::int, 20);             -- 초기: 작성 자체가 양분
  elsif v_kodr30 <= v_kodr_prev30 then
    v_kodr_mode := 'down';
    a_kodr := 20;                                       -- 감소 추세 = 예방이 작동
  else
    v_kodr_mode := 'up';
    a_kodr := 5;                                        -- 증가해도 기록 문화는 인정
  end if;

  a_cico := least(v_cico_grad * 5, 20);                 -- 졸업(자립) 1명당 5점

  v_score :=
    (case when m1 then 10 else 0 end) + (case when m2 then 10 else 0 end) +
    (case when m3 then 10 else 0 end) + (case when m4 then 10 else 0 end) +
    (case when m5 then 10 else 0 end) + (case when m6 then 10 else 0 end) +
    (case when m7 then 10 else 0 end) + (case when m8 then 10 else 0 end) +
    a_part + a_praise + a_kodr + a_cico;

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
      'participation', v_part,
      'participation_pts', a_part,
      'praise_total', v_praise,
      'praise_pts', a_praise,
      'kodr_mode', v_kodr_mode,
      'kodr_total', v_kodr,
      'kodr_pts', a_kodr,
      'cico_graduated', v_cico_grad,
      'cico_pts', a_cico
    )
  );
end $$;
revoke all on function public.school_growth() from public;
grant execute on function public.school_growth() to authenticated;
