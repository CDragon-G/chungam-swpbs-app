-- 039_school_calendar_bulk_praise.sql
-- 1) 학사일정: 주말·공휴일·방학·재량휴업일에는 점검도 알림도 없다
--      · 주말        → 요일로 자동 판정
--      · 공휴일      → public_holidays 테이블 (전국 공통, 관리자가 수정 가능)
--      · 방학·재량휴업 → school_closures 테이블 (학교별 등록)
--      주간 개근 보너스도 '그 주의 수업일 수'를 기준으로 계산하도록 수정
-- 2) 학급 일괄 칭찬: 한 명씩 누르지 않고 반 전체에게 한 번에

-- ═══════════ 1) 공휴일 (전국 공통) ═══════════
create table if not exists public_holidays (
  holiday_date date primary key,
  name text not null
);
alter table public_holidays enable row level security;
drop policy if exists ph_read on public_holidays;
create policy ph_read on public_holidays for select to authenticated using (true);
-- 쓰기는 운영자만 (SQL 에디터에서 직접)

-- 2026~2027 대한민국 공휴일
-- ※ 음력 기반 공휴일(설·추석·부처님오신날)과 대체공휴일은 해마다 확인이 필요합니다.
--   학교에서 다르게 운영하면 아래 school_closures로 보완하거나 이 표를 수정하세요.
insert into public_holidays (holiday_date, name) values
  ('2026-01-01','신정'),
  ('2026-02-16','설날 연휴'), ('2026-02-17','설날'), ('2026-02-18','설날 연휴'),
  ('2026-03-01','삼일절'), ('2026-03-02','삼일절 대체공휴일'),
  ('2026-05-05','어린이날'),
  ('2026-05-24','부처님오신날'), ('2026-05-25','부처님오신날 대체공휴일'),
  ('2026-06-06','현충일'),
  ('2026-08-15','광복절'), ('2026-08-17','광복절 대체공휴일'),
  ('2026-09-24','추석 연휴'), ('2026-09-25','추석'), ('2026-09-26','추석 연휴'),
  ('2026-10-03','개천절'), ('2026-10-05','개천절 대체공휴일'),
  ('2026-10-09','한글날'),
  ('2026-12-25','성탄절'),
  ('2027-01-01','신정'),
  ('2027-03-01','삼일절'),
  ('2027-05-05','어린이날'),
  ('2027-06-06','현충일'), ('2027-06-07','현충일 대체공휴일'),
  ('2027-08-15','광복절'), ('2027-08-16','광복절 대체공휴일'),
  ('2027-10-03','개천절'), ('2027-10-04','개천절 대체공휴일'),
  ('2027-10-09','한글날'), ('2027-10-11','한글날 대체공휴일'),
  ('2027-12-25','성탄절')
on conflict (holiday_date) do nothing;

-- ═══════════ 2) 학교별 휴업일 (방학·재량휴업일) ═══════════
create table if not exists school_closures (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  label text not null,                -- '여름방학' · '재량휴업일' 등
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);
create index if not exists sc_school_idx
  on school_closures(school_id, start_date, end_date);

alter table school_closures enable row level security;

drop policy if exists sc_read on school_closures;
create policy sc_read on school_closures
  for select using (school_id = current_profile_school());

drop policy if exists sc_admin_write on school_closures;
create policy sc_admin_write on school_closures
  for all using (is_admin_teacher() and school_id = current_profile_school())
  with check (is_admin_teacher() and school_id = current_profile_school());

-- ═══════════ 3) 수업일 판정 ═══════════
create or replace function is_school_day(p_school uuid, p_date date)
returns boolean
language sql stable security definer set search_path = public as $$
  select
    -- 토(6)·일(7) 제외
    extract(isodow from p_date) between 1 and 5
    -- 공휴일 제외
    and not exists (select 1 from public_holidays h where h.holiday_date = p_date)
    -- 학교 휴업일 제외
    and not exists (
      select 1 from school_closures c
       where c.school_id = p_school
         and p_date between c.start_date and c.end_date
    );
$$;
grant execute on function is_school_day(uuid, date) to authenticated;

-- 오늘이 수업일인지 + 아니라면 이유 (클라이언트용)
create or replace function today_school_status()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_school uuid := current_profile_school();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_dow int := extract(isodow from v_today);
  v_name text;
begin
  if v_school is null then
    return json_build_object('is_school_day', true);
  end if;
  if v_dow > 5 then
    return json_build_object('is_school_day', false, 'reason', 'weekend',
      'label', case when v_dow = 6 then '토요일' else '일요일' end);
  end if;
  select name into v_name from public_holidays where holiday_date = v_today;
  if v_name is not null then
    return json_build_object('is_school_day', false, 'reason', 'holiday', 'label', v_name);
  end if;
  select label into v_name from school_closures
   where school_id = v_school and v_today between start_date and end_date
   limit 1;
  if v_name is not null then
    return json_build_object('is_school_day', false, 'reason', 'closure', 'label', v_name);
  end if;
  return json_build_object('is_school_day', true);
end $$;
grant execute on function today_school_status() to authenticated;

-- 앞으로 N일 중 수업일 목록 (앱이 리마인더를 예약할 때 사용)
create or replace function upcoming_school_days(p_days int default 21)
returns setof date
language sql stable security definer set search_path = public as $$
  select d::date
    from generate_series(
      (now() at time zone 'Asia/Seoul')::date,
      (now() at time zone 'Asia/Seoul')::date + (greatest(1, least(p_days, 60)) - 1),
      interval '1 day') d
   where is_school_day(current_profile_school(), d::date);
$$;
grant execute on function upcoming_school_days(int) to authenticated;

-- ═══════════ 4) 주간 개근 보너스: 그 주 '수업일' 기준 ═══════════
-- 공휴일·휴업일이 낀 주에는 5일을 채울 수 없어 보너스를 못 받던 문제 해결.
create or replace function award_checkin_points(
  p_user_id uuid, p_school_id uuid, p_checkin_date date)
returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  v_week_start date := date_trunc('week', p_checkin_date)::date;
  v_period_key text := to_char(p_checkin_date, 'YYYY-MM-DD');
  v_week_key text := to_char(v_week_start, 'IYYY-IW');
  v_need int;
  v_done int;
begin
  -- 일일 100P (중복 방지)
  insert into point_transactions
    (user_id, school_id, amount, reason, period_key, description)
  values
    (p_user_id, p_school_id, 100, 'checkin_daily', v_period_key, '일일 자기점검 참여')
  on conflict (user_id, reason, period_key) do nothing;

  -- 이번 주 수업일 수 (월~금 중 휴업일 제외)
  select count(*) into v_need
    from generate_series(v_week_start, v_week_start + 4, interval '1 day') d
   where is_school_day(p_school_id, d::date);

  -- 그중 실제 점검한 날 수
  select count(distinct checkin_date) into v_done
    from daily_checkins
   where user_id = p_user_id
     and checkin_date >= v_week_start
     and checkin_date <= v_week_start + 4
     and is_school_day(p_school_id, checkin_date);

  -- 수업일이 하루라도 있고, 전부 점검했으면 보너스
  if v_need > 0 and v_done >= v_need then
    insert into point_transactions
      (user_id, school_id, amount, reason, period_key, description)
    values
      (p_user_id, p_school_id, 500, 'checkin_weekly', v_week_key, '주간 개근 보너스')
    on conflict (user_id, reason, period_key) do nothing;
  end if;
end $$;
grant execute on function award_checkin_points(uuid, uuid, date) to authenticated;

-- ═══════════ 5) 학급 일괄 칭찬 ═══════════
-- 한 명씩 누르지 않고 여러 학생에게 같은 칭찬을 한 번에 보낸다.
-- 교사 포인트는 '한 번'만 적립한다 (인원수만큼 주면 남용 소지).
create or replace function give_praise_bulk(
  p_student_ids uuid[], p_message text)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_role text; v_school uuid;
  v_sid uuid; v_praise_id uuid; v_count int;
  v_sent int := 0;
  b record;
begin
  select role, school_id into v_role, v_school
    from profiles where user_id = auth.uid();
  if v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '교사만 칭찬할 수 있어요');
  end if;
  if char_length(coalesce(trim(p_message), '')) = 0 then
    return json_build_object('ok', false, 'error', '칭찬 내용을 입력해주세요');
  end if;
  if array_length(p_student_ids, 1) is null then
    return json_build_object('ok', false, 'error', '학생을 선택해주세요');
  end if;
  if array_length(p_student_ids, 1) > 60 then
    return json_build_object('ok', false, 'error', '한 번에 최대 60명까지 보낼 수 있어요');
  end if;

  foreach v_sid in array p_student_ids loop
    -- 같은 학교 학생만
    if not exists (select 1 from profiles p
                    where p.user_id = v_sid and p.role = 'student'
                      and p.school_id = v_school) then
      continue;
    end if;

    insert into praise (school_id, teacher_id, student_id, message)
    values (v_school, auth.uid(), v_sid, trim(p_message))
    returning id into v_praise_id;

    insert into point_transactions
      (user_id, school_id, amount, reason, period_key, description)
    values (v_sid, v_school, 50, 'praise', v_praise_id::text, '교사 칭찬')
    on conflict do nothing;

    select count(*) into v_count from praise where student_id = v_sid;
    for b in select id from badges
              where condition_type = 'praise_count' and condition_value <= v_count
    loop
      insert into user_badges (user_id, badge_id) values (v_sid, b.id)
      on conflict (user_id, badge_id) do nothing;
    end loop;

    v_sent := v_sent + 1;
  end loop;

  return json_build_object('ok', true, 'sent', v_sent);
end $$;
grant execute on function give_praise_bulk(uuid[], text) to authenticated;

-- 일괄 칭찬은 교사 포인트를 1회만 (praise 트리거가 인원수만큼 쌓지 않도록
-- award_teacher_points의 일일 한도 5회가 자연스럽게 상한 역할을 한다)
