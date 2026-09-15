-- 058_checkin_after_school.sql
-- 자기점검은 하교 후(오후 1시 이후)에만 연다.
--
-- 왜
--   오늘 하루를 돌아보는 점검인데 아침에 하면 아직 지키지도 않은 규칙에 O 를 친다.
--   하교 후에 해야 '오늘' 을 돌아볼 수 있다.
--
-- 어디서 막나 — 서버에서
--   앱에서만 시간을 비교하면 기기 시계를 오후로 돌리는 순간 뚫린다. 048 에서
--   날짜를 앱이 정하게 뒀다가 포인트를 반복 취득당한 것과 같은 구조다.
--   그래서 서버 시각(한국 시간)으로 판단하고, 세 곳을 모두 막는다.
--     1) submit_checkin (지금 앱이 쓰는 길)
--     2) daily_checkins 직접 쓰기 RLS (0.20.0 이하 구버전 앱이 쓰는 길)
--     3) 이 주의 명예 식집사 계산 — 열리기 전의 '오늘' 은 수업일로 세지 않는다
--
-- 선생님은 막지 않는다. 시연·확인이 오전에 필요할 수 있다.
--
-- 시각은 학교마다 바꿀 수 있다 (단축수업, 시험 기간).
--   update schools set checkin_open_time = '12:30' where id = '<school_id>';

-- ═══════════ 1) 학교별 여는 시각 ═══════════
alter table schools
  add column if not exists checkin_open_time time not null default '13:00';

create or replace function checkin_open_time(p_school uuid)
returns time
language sql stable security definer set search_path = public as $$
  select coalesce((select checkin_open_time from schools where id = p_school),
                  time '13:00');
$$;

create or replace function is_checkin_open(p_school uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select (now() at time zone 'Asia/Seoul')::time >= checkin_open_time(p_school);
$$;
grant execute on function is_checkin_open(uuid) to authenticated;

-- 13:00 → '오후 1시', 12:30 → '오후 12시 30분'
create or replace function korean_time_label(p time)
returns text
language sql immutable as $$
  select (case when extract(hour from p) < 12 then '오전 ' else '오후 ' end)
      || (case when extract(hour from p)::int % 12 = 0 then 12
               else extract(hour from p)::int % 12 end)::text || '시'
      || (case when extract(minute from p)::int > 0
               then ' ' || extract(minute from p)::int || '분' else '' end);
$$;

-- ═══════════ 2) 오늘 상태 — 앱이 버튼을 잠글지 정하는 데 쓴다 ═══════════
--   checkin_open 은 '지금 이 순간' 기준이다. 앱은 opens_at 도 받아
--   화면을 연 채 1시가 지나도 다시 물어볼 수 있게 한다.
create or replace function today_school_status()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_school uuid := current_profile_school();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_dow int := extract(isodow from v_today);
  v_name text;
  v_open time;
begin
  if v_school is null then
    return json_build_object('is_school_day', true, 'checkin_open', true);
  end if;
  v_open := checkin_open_time(v_school);

  if v_dow > 5 then
    return json_build_object('is_school_day', false, 'reason', 'weekend',
      'label', case when v_dow = 6 then '토요일' else '일요일' end,
      'checkin_open', false);
  end if;
  select name into v_name from public_holidays where holiday_date = v_today;
  if v_name is not null then
    return json_build_object('is_school_day', false, 'reason', 'holiday',
      'label', v_name, 'checkin_open', false);
  end if;
  select label into v_name from school_closures
   where school_id = v_school and v_today between start_date and end_date
   limit 1;
  if v_name is not null then
    return json_build_object('is_school_day', false, 'reason', 'closure',
      'label', v_name, 'checkin_open', false);
  end if;

  return json_build_object(
    'is_school_day', true,
    'checkin_open', is_checkin_open(v_school),
    'opens_at', to_char(v_open, 'HH24:MI'),
    'opens_label', korean_time_label(v_open));
end $$;
grant execute on function today_school_status() to authenticated;

-- ═══════════ 3) 점검 제출 — 학생은 여는 시각 이후에만 ═══════════
create or replace function submit_checkin(
  p_answers jsonb,
  p_comment text default null
)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text; v_left timestamptz;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_total int := 0; v_possible int := 0;
  v_pct float := 0;
  v_cats jsonb := '{}'::jsonb;
  v_clean jsonb := '{}'::jsonb;
  v_existing boolean;
  r record;
begin
  select school_id, role, left_at into v_school, v_role, v_left
    from profiles where user_id = auth.uid();
  if v_school is null then
    return json_build_object('ok', false, 'error', '로그인이 필요해요');
  end if;
  if v_left is not null then
    return json_build_object('ok', false, 'error',
      '졸업·전출 처리된 계정이에요. 선생님께 문의해 주세요.');
  end if;

  if not is_school_day(v_school, v_today) then
    return json_build_object('ok', false, 'error',
      '오늘은 자기점검을 하는 날이 아니에요. 다음 수업일에 만나요!');
  end if;

  -- 하교 후에만. 서버 시각으로 판단한다.
  if v_role = 'student' and not is_checkin_open(v_school) then
    return json_build_object('ok', false, 'error',
      '자기점검은 ' || korean_time_label(checkin_open_time(v_school))
      || '부터 할 수 있어요. 하교 후에 오늘을 돌아봐요!',
      'reason', 'not_open_yet');
  end if;

  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    return json_build_object('ok', false, 'error', '점검 내용이 비어 있어요');
  end if;

  for r in
    select sr.id, sr.category, (p_answers ->> sr.id::text) as raw
      from school_rules sr
     where sr.school_id = v_school and sr.is_active
       and p_answers ? sr.id::text
  loop
    if r.raw not in ('true', 'false') then continue; end if;
    v_possible := v_possible + 1;
    if r.raw = 'true' then v_total := v_total + 1; end if;
    v_clean := v_clean || jsonb_build_object(r.id::text, (r.raw = 'true'));
  end loop;

  if v_possible = 0 then
    return json_build_object('ok', false, 'error', '점검한 규칙이 없어요');
  end if;
  v_pct := (v_total::float / v_possible) * 100.0;

  select coalesce(jsonb_object_agg(t.category, t.avg_pct), '{}'::jsonb)
    into v_cats
  from (
    select sr.category,
           avg(case when v_clean ->> sr.id::text = 'true' then 100.0 else 0.0 end) as avg_pct
      from school_rules sr
     where sr.school_id = v_school and sr.is_active
       and v_clean ? sr.id::text
     group by sr.category
  ) t;

  select exists (select 1 from daily_checkins
                  where user_id = auth.uid() and checkin_date = v_today)
    into v_existing;

  insert into daily_checkins
    (user_id, school_id, checkin_date, answers,
     total_score, total_possible, score_pct, category_scores, comment)
  values
    (auth.uid(), v_school, v_today, v_clean,
     v_total, v_possible, v_pct, v_cats, nullif(btrim(coalesce(p_comment, '')), ''))
  on conflict (user_id, checkin_date) do update
    set answers = excluded.answers,
        total_score = excluded.total_score,
        total_possible = excluded.total_possible,
        score_pct = excluded.score_pct,
        category_scores = excluded.category_scores,
        comment = excluded.comment,
        updated_at = now();

  if v_role = 'student' then
    perform award_checkin_points_internal(auth.uid(), v_school, v_today);
  end if;

  return json_build_object(
    'ok', true,
    'checkin_date', v_today,
    'total_score', v_total,
    'total_possible', v_possible,
    'score_pct', v_pct,
    'is_overwrite', v_existing);
end $$;
grant execute on function submit_checkin(jsonb, text) to authenticated;

-- ═══════════ 4) 구버전 앱의 직접 쓰기도 막는다 ═══════════
--   0.20.0 이하 앱은 submit_checkin 을 거치지 않고 테이블에 바로 upsert 한다.
--   RLS 에 시간 조건이 없으면 구버전 앱으로 오전에 점검할 수 있다.
--   (053 의 포인트 껍데기는 '오늘 점검 기록이 있어야' 지급하므로,
--    여기서 기록을 막으면 포인트도 함께 막힌다)
drop policy if exists checkins_own_insert on daily_checkins;
create policy checkins_own_insert on daily_checkins
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and checkin_date = (now() at time zone 'Asia/Seoul')::date
    and is_school_day(school_id, checkin_date)
    and (current_profile_role() <> 'student' or is_checkin_open(school_id))
  );

drop policy if exists checkins_own_update on daily_checkins;
create policy checkins_own_update on daily_checkins
  for update to authenticated
  using (user_id = auth.uid()
         and checkin_date = (now() at time zone 'Asia/Seoul')::date)
  with check (user_id = auth.uid()
              and checkin_date = (now() at time zone 'Asia/Seoul')::date
              and (current_profile_role() <> 'student' or is_checkin_open(school_id)));

-- ═══════════ 5) 이 주의 명예 식집사 — 열리기 전의 오늘은 세지 않는다 ═══════════
--   꾸준함 = 점검한 날 / 지금까지의 수업일. 화요일 오전에 '오늘' 을 수업일로 세면
--   아무도 점검할 수 없는데 분모만 늘어서, 모두의 점수가 오전에 반토막 났다가
--   오후에 돌아온다. 056 과 같은 함수이고 bounds 만 다르다.
--   ※ 056 을 먼저 실행한 뒤에 이 파일을 실행하세요.
create or replace function weekly_honor_rank(p_school uuid, p_week_start date)
returns table (
  user_id uuid,
  grade int,
  class_num int,
  nickname text,
  days_done int,
  avg_pct int,
  praise_cnt int,
  score int,
  rn int
)
language sql stable security definer set search_path = public, auth as $$
  with bounds as (
    select p_week_start as ws,
           least((now() at time zone 'Asia/Seoul')::date
                   - case when is_checkin_open(p_school) then 0 else 1 end,
                 p_week_start + 4) as upto
  ),
  school_days as (
    select count(*)::int as n
      from bounds b,
           generate_series(b.ws, b.upto, interval '1 day') d
     where d::date <= b.upto
       and is_school_day(p_school, d::date)
  ),
  ck as (
    select d.user_id,
           count(distinct d.checkin_date)::int as days_done,
           round(avg(d.score_pct))::int       as avg_pct
      from daily_checkins d, bounds b
     where d.school_id = p_school
       and d.checkin_date between b.ws and b.ws + 6
       and is_school_day(p_school, d.checkin_date)
     group by d.user_id
  ),
  pr as (
    select pz.student_id as user_id, count(*)::int as praise_cnt
      from praise pz, bounds b
     where pz.school_id = p_school
       and pz.created_at >= (b.ws::timestamp at time zone 'Asia/Seoul')
       and pz.created_at <  ((b.ws + 7)::timestamp at time zone 'Asia/Seoul')
     group by pz.student_id
  ),
  scored as (
    select p.user_id, p.grade, p.class_num, p.nickname,
           ck.days_done, ck.avg_pct,
           coalesce(pr.praise_cnt, 0) as praise_cnt,
           ( case when sd.n > 0
                  then round(least(ck.days_done, sd.n)::numeric / sd.n * 40)
                  else 0 end
           + round(coalesce(ck.avg_pct, 0) * 0.3)
           + least(coalesce(pr.praise_cnt, 0), 3) * 10
           )::int as score
      from profiles p
      join ck on ck.user_id = p.user_id
      left join pr on pr.user_id = p.user_id
      cross join school_days sd
     where p.school_id = p_school
       and p.role = 'student'
       and p.left_at is null
       and p.grade is not null and p.class_num is not null
       and ck.days_done >= 1
  )
  select s.user_id, s.grade, s.class_num, s.nickname,
         s.days_done, s.avg_pct, s.praise_cnt, s.score,
         (row_number() over (
            partition by s.grade, s.class_num
            order by s.score desc, s.praise_cnt desc, s.days_done desc,
                     s.avg_pct desc,
                     md5(s.user_id::text || p_week_start::text)))::int as rn
    from scored s;
$$;
revoke all on function weekly_honor_rank(uuid, date) from public, anon, authenticated;

-- ═══════════ 6) 확인 ═══════════
--   select name, checkin_open_time from schools;
--   select korean_time_label(time '13:00');          -- 오후 1시
--   오전에 학생 계정으로 앱에서 점검 → "오후 1시부터 할 수 있어요"
