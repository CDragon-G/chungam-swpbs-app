-- 053_checkin_points_compat.sql
-- 구버전 앱에서 자기점검 100P 가 지급되지 않던 문제를 고친다.
--
-- 무슨 일이 있었나
--   0.20.0 이하 앱은 점검을 이렇게 처리했다.
--     1) daily_checkins 에 직접 upsert
--     2) award_checkin_points RPC 호출로 포인트 지급
--   048 에서 2번의 실행 권한을 authenticated 에게서 회수했다. 부정 취득을
--   막기 위해서였는데, 그 함수를 부르던 구버전 앱이 아직 남아 있었다.
--   앱은 실패를 catch 로 삼키기 때문에 학생 화면에는 "점검 완료" 가 뜨고
--   포인트만 조용히 사라졌다.
--
-- 어떻게 고치나
--   · 진짜 로직은 award_checkin_points_internal 로 옮기고 계속 잠가 둔다
--   · award_checkin_points 는 파라미터를 '무시하는' 껍데기로 되살린다.
--     누가 무엇을 넣어 부르든 호출자 자신의 · 서버 기준 오늘 것만 지급한다.
--   · 게다가 오늘 점검 기록이 실제로 있어야만 지급한다.
--     (RLS 가 점검을 '서버 기준 오늘 + 수업일' 로 묶어 두었으므로
--      048 이 막은 구멍은 그대로 막혀 있다)
--
-- 이건 다리(bridge)다. 모두가 0.23.0 이상으로 올라오면 다시 잠가도 된다.

-- ═══════════ 1) 진짜 로직 — 내부 전용 ═══════════
create or replace function award_checkin_points_internal(
  p_user_id uuid, p_school_id uuid, p_checkin_date date)
returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  v_week_start date := date_trunc('week', p_checkin_date)::date;
  v_period_key text := to_char(p_checkin_date, 'YYYY-MM-DD');
  v_week_key text := to_char(v_week_start, 'IYYY-IW');
  v_school_days int;
  v_done int;
begin
  -- 수업일이 아니면 지급하지 않는다 (주말·공휴일·방학·재량휴업일)
  if not is_school_day(p_school_id, p_checkin_date) then
    return;
  end if;
  -- 미래 날짜도 막는다
  if p_checkin_date > (now() at time zone 'Asia/Seoul')::date then
    return;
  end if;

  insert into point_transactions
    (user_id, school_id, amount, reason, period_key, description)
  values
    (p_user_id, p_school_id, 100, 'checkin_daily', v_period_key, '일일 자기점검 참여')
  on conflict (user_id, reason, period_key) do nothing;

  -- 그 주 월~금 중 수업일 수
  select count(*) into v_school_days
    from generate_series(v_week_start, v_week_start + 4, interval '1 day') d
   where is_school_day(p_school_id, d::date);

  -- 월~금 5일이 모두 수업일인 주에만 개근 보너스
  if v_school_days = 5 then
    select count(distinct checkin_date) into v_done
      from daily_checkins
     where user_id = p_user_id
       and checkin_date >= v_week_start
       and checkin_date <= v_week_start + 4;

    if v_done >= 5 then
      insert into point_transactions
        (user_id, school_id, amount, reason, period_key, description)
      values
        (p_user_id, p_school_id, 500, 'checkin_weekly', v_week_key, '주간 개근 보너스')
      on conflict (user_id, reason, period_key) do nothing;
    end if;
  end if;
end $$;
revoke execute on function award_checkin_points_internal(uuid, uuid, date)
  from authenticated, anon, public;

-- ═══════════ 2) 구버전 호환 껍데기 ═══════════
--   파라미터는 받기만 하고 쓰지 않는다. 구버전 앱의 호출 형태를 맞추기 위한
--   자리일 뿐이다. 누구를 넣든 auth.uid() 자신에게만, 서버가 정한 오늘에만.
create or replace function award_checkin_points(
  p_user_id uuid, p_school_id uuid, p_checkin_date date)
returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
  v_school uuid;
  v_role text;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v_user is null then return; end if;

  select school_id, role into v_school, v_role
    from profiles where user_id = v_user;
  if v_school is null or v_role <> 'student' then return; end if;

  -- 오늘 점검을 실제로 한 사람에게만. 점검 없이 포인트만 받아가지 못한다.
  if not exists (select 1 from daily_checkins
                  where user_id = v_user and checkin_date = v_today) then
    return;
  end if;

  perform award_checkin_points_internal(v_user, v_school, v_today);
end $$;
grant execute on function award_checkin_points(uuid, uuid, date) to authenticated;

-- ═══════════ 3) submit_checkin 은 내부 함수를 직접 부른다 ═══════════
create or replace function submit_checkin(
  p_answers jsonb,
  p_comment text default null
)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_total int := 0; v_possible int := 0;
  v_pct float := 0;
  v_cats jsonb := '{}'::jsonb;
  v_clean jsonb := '{}'::jsonb;
  v_existing boolean;
  r record;
begin
  select school_id, role into v_school, v_role
    from profiles where user_id = auth.uid();
  if v_school is null then
    return json_build_object('ok', false, 'error', '로그인이 필요해요');
  end if;

  if not is_school_day(v_school, v_today) then
    return json_build_object('ok', false, 'error',
      '오늘은 자기점검을 하는 날이 아니에요. 다음 수업일에 만나요!');
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

-- ═══════════ 4) 못 받은 포인트 소급 지급 ═══════════
--   점검 기록은 있는데 그날 checkin_daily 거래가 없는 건을 찾아 지급한다.
--   수업일·과거 날짜만 대상이고, 이미 있는 건은 건드리지 않는다.
create or replace function backfill_missing_checkin_points(p_days int default 60)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid;
  v_from date;
  v_n int := 0;
  c record;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 실행할 수 있어요');
  end if;
  select school_id into v_school from profiles where user_id = auth.uid();
  v_from := (now() at time zone 'Asia/Seoul')::date - greatest(1, p_days);

  for c in
    select d.user_id, d.school_id, d.checkin_date
      from daily_checkins d
      join profiles p on p.user_id = d.user_id and p.role = 'student'
     where d.school_id = v_school
       and d.checkin_date >= v_from
       and d.checkin_date <= (now() at time zone 'Asia/Seoul')::date
       and is_school_day(d.school_id, d.checkin_date)
       and not exists (
             select 1 from point_transactions t
              where t.user_id = d.user_id
                and t.reason = 'checkin_daily'
                and t.period_key = to_char(d.checkin_date, 'YYYY-MM-DD'))
  loop
    perform award_checkin_points_internal(c.user_id, c.school_id, c.checkin_date);
    v_n := v_n + 1;
  end loop;

  return json_build_object('ok', true, 'awarded', v_n);
end $$;
grant execute on function backfill_missing_checkin_points(int) to authenticated;

-- ═══════════ 5) 옛 backfill 함수 잠그기 ═══════════
--   005 의 backfill_checkin_points() 는 전교생 전체 기간을 도는데
--   authenticated 아무나 부를 수 있었다. 내부 함수를 쓰도록 바꾸고 잠근다.
create or replace function backfill_checkin_points()
returns int
language plpgsql security definer set search_path = public, auth as $$
declare c record; n int := 0;
begin
  for c in select user_id, school_id, checkin_date from daily_checkins
  loop
    perform award_checkin_points_internal(c.user_id, c.school_id, c.checkin_date);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function backfill_checkin_points()
  from authenticated, anon, public;

-- ═══════════ 6) 확인 ═══════════
--   점검은 있는데 포인트가 없는 건 (지급 전에 먼저 확인)
--     select p.nickname, p.grade, p.class_num, p.student_num, d.checkin_date
--       from daily_checkins d
--       join profiles p on p.user_id = d.user_id and p.role = 'student'
--      where d.checkin_date >= current_date - 60
--        and is_school_day(d.school_id, d.checkin_date)
--        and not exists (select 1 from point_transactions t
--                         where t.user_id = d.user_id
--                           and t.reason = 'checkin_daily'
--                           and t.period_key = to_char(d.checkin_date,'YYYY-MM-DD'))
--      order by d.checkin_date desc;
--
--   소급 지급 (관리자 계정으로)
--     select backfill_missing_checkin_points(60);
