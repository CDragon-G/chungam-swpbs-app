-- 048_checkin_server_authority.sql
-- 자기점검 포인트 부정 취득 차단 (학생 제보로 발견).
--
-- 무엇이 뚫렸나
--   1) 날짜를 앱이 정했다. 앱은 기기 시간으로 checkin_date 를 만들어
--      daily_checkins 에 직접 insert 했다. 안드로이드에서 날짜를 바꾸고
--      캐시를 지우면 임의의 날짜로 점검이 쌓였고, 날짜마다 100P 가 나갔다.
--   2) award_checkin_points 가 user_id 와 날짜를 파라미터로 받았고
--      authenticated 에게 execute 가 열려 있었다. 앱을 고치지 않아도
--      API 를 직접 불러 아무 날짜로나, 남의 계정으로도 포인트를 넣을 수 있었다.
--   3) 점수(score_pct)도 앱이 계산해서 보냈다. 조작하면 통계와
--      명예 식집사 선정이 왜곡된다.
--
-- 어떻게 막나
--   · 날짜·점수·포인트를 전부 서버가 정한다 (submit_checkin RPC)
--   · 수업일이 아니면 아예 저장하지 않는다 (주말·공휴일·방학·재량휴업일)
--   · RLS 로 '서버 기준 오늘' 이외의 날짜는 직접 insert 도 막는다
--   · award_checkin_points 는 내부 전용으로 잠근다

-- ═══════════ 1) 포인트 함수를 내부 전용으로 ═══════════
--   SECURITY DEFINER 함수끼리는 호출되지만 앱에서는 부를 수 없다.
revoke execute on function award_checkin_points(uuid, uuid, date)
  from authenticated, anon, public;

-- ═══════════ 2) 점검 제출 — 서버가 전부 결정 ═══════════
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

  -- 수업일이 아니면 점검 자체를 받지 않는다
  if not is_school_day(v_school, v_today) then
    return json_build_object('ok', false, 'error',
      '오늘은 자기점검을 하는 날이 아니에요. 다음 수업일에 만나요!');
  end if;

  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    return json_build_object('ok', false, 'error', '점검 내용이 비어 있어요');
  end if;

  -- 우리 학교의 살아 있는 규칙만 인정한다. 앱이 보낸 규칙 id 를 그대로 믿지 않는다.
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

  -- 카테고리 평균도 서버에서 다시 센다
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

  -- 포인트도 서버가 준다. 학생 계정만 대상.
  if v_role = 'student' then
    perform award_checkin_points(auth.uid(), v_school, v_today);
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

-- ═══════════ 3) 직접 쓰기를 서버 기준 오늘로 묶는다 ═══════════
--   RPC 를 안 쓰고 테이블을 직접 건드려도 과거·미래 날짜는 들어가지 않는다.
--   (이미 쌓인 기록은 그대로 두고, 앞으로의 조작만 막는다)
drop policy if exists checkins_own on daily_checkins;

drop policy if exists checkins_own_read on daily_checkins;
create policy checkins_own_read on daily_checkins
  for select to authenticated using (user_id = auth.uid());

drop policy if exists checkins_own_insert on daily_checkins;
create policy checkins_own_insert on daily_checkins
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and checkin_date = (now() at time zone 'Asia/Seoul')::date
    and is_school_day(school_id, checkin_date)
  );

drop policy if exists checkins_own_update on daily_checkins;
create policy checkins_own_update on daily_checkins
  for update to authenticated
  using (user_id = auth.uid()
         and checkin_date = (now() at time zone 'Asia/Seoul')::date)
  with check (user_id = auth.uid()
              and checkin_date = (now() at time zone 'Asia/Seoul')::date);

--   삭제는 허용하지 않는다. 지웠다 다시 넣는 우회를 막는다.

-- ═══════════ 4) 포인트도 수업일에만 ═══════════
--   앞으로 어떤 경로로 불리든 수업일이 아니면 한 푼도 나가지 않는다.
create or replace function award_checkin_points(
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
revoke execute on function award_checkin_points(uuid, uuid, date)
  from authenticated, anon, public;

-- ═══════════ 5) 부정 취득 점검용 조회 ═══════════
--   수업일이 아닌 날에 남은 점검과, 그날 나간 포인트를 찾는다.
--   지울지 말지는 선생님이 판단하시도록 조회만 만든다.
create or replace function suspicious_checkins(p_days int default 120)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare v_school uuid; v_from date; v_out json;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 볼 수 있어요');
  end if;
  select school_id into v_school from profiles where user_id = auth.uid();
  v_from := (now() at time zone 'Asia/Seoul')::date - greatest(1, p_days);

  select coalesce(json_agg(t order by t.cnt desc), '[]'::json) into v_out
  from (
    select p.nickname, p.grade, p.class_num, p.student_num,
           count(*)::int as cnt,
           min(d.checkin_date) as first_date,
           max(d.checkin_date) as last_date
      from daily_checkins d
      join profiles p on p.user_id = d.user_id
     where d.school_id = v_school
       and d.checkin_date >= v_from
       and not is_school_day(v_school, d.checkin_date)
     group by p.nickname, p.grade, p.class_num, p.student_num
  ) t;

  return json_build_object('ok', true, 'items', v_out);
end $$;
grant execute on function suspicious_checkins(int) to authenticated;
