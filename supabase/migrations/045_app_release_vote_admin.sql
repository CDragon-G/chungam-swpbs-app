-- 045_app_release_vote_admin.sql
-- 1) 앱 버전 관리 — 최신 버전을 안 받은 사용자에게 업데이트 안내 팝업
-- 2) 수업맛집 관리자 확장
--      · 지난 투표 결과 삭제
--      · 진행 중인 투표 수정
--      · 학기 시작 때 투표 가능한 날(시작·종료일, 요일)을 미리 지정
--      · 투표 안내 알림을 버튼 하나로 발송

-- ═══════════ 1) 버전 비교 도우미 ═══════════
--   '0.18.0+60' 처럼 뒤에 빌드번호가 붙어도 앞의 숫자만 읽는다.
create or replace function version_num(v text)
returns int[]
language sql immutable as $$
  select coalesce(
    string_to_array(
      substring(coalesce(v, '') from '^[0-9]+(?:\.[0-9]+)*'), '.')::int[],
    array[0]);
$$;
grant execute on function version_num(text) to authenticated, anon;

-- ═══════════ 2) 스토어에 올라간 버전 ═══════════
create table if not exists app_releases (
  platform text primary key check (platform in ('android', 'ios')),
  latest_version text not null,   -- 스토어 최신 버전 → 이보다 낮으면 안내 팝업
  min_version text not null,      -- 최소 지원 버전 → 이보다 낮으면 강제 업데이트
  store_url text not null,
  updated_at timestamptz not null default now()
);
alter table app_releases enable row level security;

drop policy if exists ar_read on app_releases;
create policy ar_read on app_releases
  for select to authenticated, anon using (true);
-- 쓰기는 운영자만 (SQL 에디터에서 직접)

insert into app_releases (platform, latest_version, min_version, store_url) values
  ('android', '0.19.0', '0.19.0',
   'https://play.google.com/store/apps/details?id=com.jaram.app'),
  ('ios', '0.19.0', '0.19.0',
   'https://apps.apple.com/app/id6780309774')
on conflict (platform) do nothing;

-- ═══════════ 3) 업데이트 필요 여부 ═══════════
create or replace function app_update_check(p_platform text, p_version text)
returns json
language plpgsql stable security definer set search_path = public as $$
declare r app_releases;
begin
  select * into r from app_releases where platform = p_platform;
  if r.platform is null then
    return json_build_object('ok', false);
  end if;
  return json_build_object(
    'ok', true,
    'latest', r.latest_version,
    'min', r.min_version,
    'store_url', r.store_url,
    -- 최소 지원 버전 미만 → 계속 쓸 수 없다
    'force', version_num(p_version) < version_num(r.min_version),
    -- 최신 버전 미만 → 안내만
    'update_available', version_num(p_version) < version_num(r.latest_version));
end $$;
grant execute on function app_update_check(text, text) to authenticated, anon;

-- ═══════════ 4) 투표 가능한 날 사전 지정 ═══════════
alter table vote_rounds
  add column if not exists start_date date,      -- null = 만든 날부터
  add column if not exists end_date date,        -- null = 기한 없음
  add column if not exists vote_weekdays int[];  -- 예: {5} 금요일만, null = 모든 수업일

-- 오늘 이 라운드에 투표할 수 있는가 (학년과 무관한 일정 조건만 본다)
create or replace function vote_today_status(p_round uuid)
returns json
language plpgsql stable security definer set search_path = public as $$
declare
  r vote_rounds;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_dow int;
  v_names text;
begin
  select * into r from vote_rounds where id = p_round;
  if r.id is null then
    return json_build_object('ok', false, 'reason', '투표를 찾을 수 없어요.');
  end if;
  if r.status <> 'open' then
    return json_build_object('ok', false, 'reason', '이미 마감된 투표예요.');
  end if;
  if r.start_date is not null and v_today < r.start_date then
    return json_build_object('ok', false,
      'reason', to_char(r.start_date, 'FMMM"월" FMDD"일"') || '부터 투표할 수 있어요.');
  end if;
  if r.end_date is not null and v_today > r.end_date then
    return json_build_object('ok', false, 'reason', '투표 기간이 끝났어요.');
  end if;

  v_dow := extract(isodow from v_today)::int;
  if r.vote_weekdays is not null and array_length(r.vote_weekdays, 1) > 0
     and not (v_dow = any (r.vote_weekdays)) then
    select string_agg(
             ('{월,화,수,목,금,토,일}'::text[])[d] || '요일', '·' order by d)
      into v_names
      from unnest(r.vote_weekdays) d;
    return json_build_object('ok', false,
      'reason', '수업맛집 투표는 ' || v_names || '에만 할 수 있어요.');
  end if;

  return json_build_object('ok', true);
end $$;
grant execute on function vote_today_status(uuid) to authenticated;

-- ═══════════ 5) 학년별 주차 — 지정한 시작·종료일을 기준으로 ═══════════
create or replace function vote_grade_week(p_round uuid, p_grade int)
returns int
language plpgsql stable security definer set search_path = public as $$
declare
  v_school uuid; v_start date; v_end date; v_total int;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_last date; v_cur date; v_cnt int := 0;
begin
  select r.school_id,
         coalesce(r.start_date, (r.created_at at time zone 'Asia/Seoul')::date),
         r.end_date,
         coalesce((select s.total_weeks from vote_grade_settings s
                    where s.round_id = r.id and s.grade = p_grade),
                  r.total_weeks)
    into v_school, v_start, v_end, v_total
    from vote_rounds r where r.id = p_round;
  if v_school is null then return 0; end if;

  -- 종료일이 지났으면 그날까지만 센다
  v_last := least(v_today, coalesce(v_end, v_today));
  if v_last < v_start then return 0; end if;

  -- 시작일이 속한 주의 월요일부터
  v_cur := v_start - (extract(isodow from v_start)::int - 1);
  while v_cur <= v_last loop
    if exists (
      select 1
        from generate_series(v_cur, v_cur + 4, interval '1 day') d
       where d::date >= v_start
         and (v_end is null or d::date <= v_end)
         and is_school_day(v_school, d::date)
         and vote_blackout_label(v_school, p_grade, d::date) is null
    ) then
      v_cnt := v_cnt + 1;
    end if;
    v_cur := v_cur + 7;
  end loop;

  return least(greatest(v_cnt, 1), v_total);
end $$;
grant execute on function vote_grade_week(uuid, int) to authenticated;

-- ═══════════ 6) 학년별 진행 현황 + 오늘 투표 가능 여부 ═══════════
create or replace function vote_round_progress(p_round_id uuid)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_round vote_rounds;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_out json;
  v_day json;
begin
  select * into v_round from vote_rounds
    where id = p_round_id and school_id = current_profile_school();
  if v_round is null then raise exception '투표를 찾을 수 없어요.'; end if;
  if current_profile_role() <> 'teacher' then
    raise exception '교사만 볼 수 있어요.';
  end if;

  v_day := vote_today_status(p_round_id);

  select coalesce(json_agg(t.j order by t.g), '[]'::json) into v_out
  from (
    select g,
      json_build_object(
        'grade', g,
        'week_now', vote_grade_week(p_round_id, g),
        'total_weeks', coalesce(s.total_weeks, v_round.total_weeks),
        'custom_weeks', s.total_weeks is not null,
        'closed', s.closed_at is not null,
        'closed_at', s.closed_at,
        'paused_label', vote_blackout_label(v_round.school_id, g, v_today),
        'votes', (select count(*) from class_votes cv
                   where cv.round_id = p_round_id and cv.grade = g)
      ) as j
    from unnest(school_grades(v_round.school_id)) as g
    left join vote_grade_settings s
      on s.round_id = p_round_id and s.grade = g
  ) t;

  return json_build_object(
    'round_id', p_round_id,
    'today_ok', (v_day->>'ok')::boolean,
    'today_reason', v_day->>'reason',
    'start_date', v_round.start_date,
    'end_date', v_round.end_date,
    'vote_weekdays', v_round.vote_weekdays,
    'grades', v_out);
end $$;
revoke all on function vote_round_progress(uuid) from public;
grant execute on function vote_round_progress(uuid) to authenticated;

-- ═══════════ 7) 투표하기 — 지정한 날짜·요일도 검증 ═══════════
create or replace function public.cast_class_vote(
  p_round_id uuid, p_subject text, p_grade int, p_class_num int
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_round vote_rounds;
  v_week text := kst_week_key();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_day json;
  v_pause text;
  v_used int;
  v_id uuid;
begin
  if current_profile_role() <> 'teacher' then
    raise exception '교사만 투표할 수 있어요.';
  end if;

  select * into v_round from vote_rounds
    where id = p_round_id and school_id = current_profile_school();
  if v_round is null then raise exception '투표를 찾을 수 없어요.'; end if;

  -- 마감·시작일·종료일·요일 지정
  v_day := vote_today_status(p_round_id);
  if (v_day->>'ok')::boolean is not true then
    raise exception '%', v_day->>'reason';
  end if;

  if coalesce(trim(p_subject), '') = '' then
    raise exception '과목을 선택해주세요.';
  end if;

  -- 학년별 조기 마감
  if exists (select 1 from vote_grade_settings s
              where s.round_id = p_round_id and s.grade = p_grade
                and s.closed_at is not null) then
    raise exception '%학년은 이미 마감돼서 투표할 수 없어요.', p_grade;
  end if;

  -- 시험 기간 등 투표를 쉬는 기간
  v_pause := vote_blackout_label(v_round.school_id, p_grade, v_today);
  if v_pause is not null then
    raise exception '%학년은 지금 투표를 쉬는 기간이에요. (%)', p_grade, v_pause;
  end if;

  -- 같은 주 같은 학급 중복 방지
  if exists (select 1 from class_votes
             where round_id = p_round_id and teacher_id = auth.uid()
               and week_key = v_week
               and grade = p_grade and class_num = p_class_num) then
    raise exception '이번 주에 이미 이 학급에 투표했어요.';
  end if;

  -- 주당 투표권 검증
  select count(*) into v_used from class_votes
    where round_id = p_round_id and teacher_id = auth.uid()
      and week_key = v_week;
  if v_used >= v_round.votes_per_week then
    raise exception '이번 주 투표권(%표)을 모두 사용했어요.', v_round.votes_per_week;
  end if;

  insert into class_votes(round_id, school_id, teacher_id, subject, grade, class_num, week_key)
  values (p_round_id, v_round.school_id, auth.uid(), trim(p_subject), p_grade, p_class_num, v_week)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.cast_class_vote(uuid, text, int, int) from public;
grant execute on function public.cast_class_vote(uuid, text, int, int) to authenticated;

-- ═══════════ 8) 라운드 수정 · 삭제 (관리자) ═══════════
create or replace function update_vote_round(
  p_round_id uuid,
  p_title text,
  p_votes_per_week int,
  p_total_weeks int,
  p_start_date date,
  p_end_date date,
  p_weekdays int[]
)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare v_school uuid;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 수정할 수 있어요');
  end if;
  select school_id into v_school from vote_rounds
   where id = p_round_id and school_id = current_profile_school();
  if v_school is null then
    return json_build_object('ok', false, 'error', '투표를 찾을 수 없어요');
  end if;
  if coalesce(trim(p_title), '') = '' then
    return json_build_object('ok', false, 'error', '투표 이름을 넣어주세요');
  end if;
  if p_votes_per_week < 1 or p_votes_per_week > 20 then
    return json_build_object('ok', false, 'error', '주당 투표권은 1~20표 사이로 넣어주세요');
  end if;
  if p_total_weeks < 1 or p_total_weeks > 20 then
    return json_build_object('ok', false, 'error', '총 주차는 1~20주 사이로 넣어주세요');
  end if;
  if p_start_date is not null and p_end_date is not null
     and p_end_date < p_start_date then
    return json_build_object('ok', false, 'error', '종료일이 시작일보다 빠를 수 없어요');
  end if;
  if p_weekdays is not null and exists (
       select 1 from unnest(p_weekdays) d where d < 1 or d > 7) then
    return json_build_object('ok', false, 'error', '요일 설정을 확인해주세요');
  end if;

  update vote_rounds
     set title = trim(p_title),
         votes_per_week = p_votes_per_week,
         total_weeks = p_total_weeks,
         start_date = p_start_date,
         end_date = p_end_date,
         vote_weekdays = case
           when p_weekdays is null or array_length(p_weekdays, 1) is null
             then null else p_weekdays end
   where id = p_round_id;

  return json_build_object('ok', true);
end $$;
revoke all on function update_vote_round(uuid, text, int, int, date, date, int[]) from public;
grant execute on function update_vote_round(uuid, text, int, int, date, date, int[])
  to authenticated;

-- 라운드를 지우면 그 라운드의 투표와 학년 설정도 함께 사라진다 (FK cascade).
create or replace function delete_vote_round(p_round_id uuid)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare v_votes int;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 삭제할 수 있어요');
  end if;
  if not exists (select 1 from vote_rounds
                  where id = p_round_id and school_id = current_profile_school()) then
    return json_build_object('ok', false, 'error', '투표를 찾을 수 없어요');
  end if;

  select count(*) into v_votes from class_votes where round_id = p_round_id;
  delete from vote_rounds where id = p_round_id;

  return json_build_object('ok', true, 'deleted_votes', v_votes);
end $$;
revoke all on function delete_vote_round(uuid) from public;
grant execute on function delete_vote_round(uuid) to authenticated;

-- ═══════════ 9) 투표 안내 알림 발송 (관리자) ═══════════
create or replace function send_vote_notice(p_round_id uuid, p_body text default null)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_round vote_rounds;
  v_open int[];
  v_body text;
  v_teachers int;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 보낼 수 있어요');
  end if;
  select * into v_round from vote_rounds
   where id = p_round_id and school_id = current_profile_school();
  if v_round is null then
    return json_build_object('ok', false, 'error', '투표를 찾을 수 없어요');
  end if;

  v_body := nullif(trim(coalesce(p_body, '')), '');
  if v_body is null then
    -- 기본 문구: 오늘 투표할 수 있는 학년까지 알려준다
    select coalesce(array_agg(g order by g), '{}'::int[]) into v_open
      from unnest(school_grades(v_round.school_id)) g
     where vote_blackout_label(v_round.school_id, g,
             (now() at time zone 'Asia/Seoul')::date) is null
       and not exists (select 1 from vote_grade_settings s
                        where s.round_id = p_round_id and s.grade = g
                          and s.closed_at is not null);

    v_body := '이번 주 수업 규칙을 가장 잘 지킨 학급에 투표해주세요. '
      || '(주 ' || v_round.votes_per_week || '표)';
    if array_length(v_open, 1) is not null
       and array_length(v_open, 1)
           < array_length(school_grades(v_round.school_id), 1) then
      v_body := v_body || E'\n오늘은 '
        || array_to_string(v_open, '·') || '학년만 투표할 수 있어요.';
    end if;
  end if;

  perform push_notification(
    v_round.school_id, 'teachers', null, null, null,
    'notice', '🍽️ 수업맛집 투표 안내', v_body, '/teacher/vote',
    'vote_notice:' || p_round_id::text || ':'
      || to_char(now() at time zone 'Asia/Seoul', 'YYYYMMDDHH24MI'));

  select count(*) into v_teachers from profiles
   where school_id = v_round.school_id and role = 'teacher';

  return json_build_object('ok', true, 'body', v_body, 'teachers', v_teachers);
end $$;
revoke all on function send_vote_notice(uuid, text) from public;
grant execute on function send_vote_notice(uuid, text) to authenticated;
