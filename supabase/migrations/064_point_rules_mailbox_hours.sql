-- 064_point_rules_mailbox_hours.sql
-- 1) 포인트 금액을 학교가 직접 정한다 (관리자 → 포인트 설정)
-- 2) 칭찬 우체통도 자기점검과 같은 시간에 연다 (수업일 · 하교 후)
-- 3) 강화물 교환 순위 (1~3위)
--
-- 지금까지 포인트 금액이 서버 함수 안에 숫자로 박혀 있어서, 바꾸려면 코드를 고치고
-- 마이그레이션을 새로 실행해야 했다. 이제 학교마다 값을 정해 두고 함수가 그 값을 읽는다.
-- 앱을 새로 빌드하지 않아도 되고, 학교마다 다르게 둘 수 있다.

-- ═══════════ 1) 포인트 금액 ═══════════
create table if not exists school_point_rules (
  school_id uuid not null references schools(id) on delete cascade,
  reason text not null,
  amount int not null check (amount >= 0 and amount <= 5000),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  primary key (school_id, reason)
);
alter table school_point_rules enable row level security;   -- 함수로만 읽고 쓴다

--   기본값 — 학교가 따로 정하지 않았을 때 쓰는 값 (지금까지 쓰던 숫자 그대로)
create or replace function point_rule_default(p_reason text)
returns int
language sql immutable as $$
  select case p_reason
    when 'checkin_daily'  then 100   -- 일일 자기점검
    when 'checkin_weekly' then 500   -- 월~금 모두 참여한 주
    when 'praise'         then 50    -- 선생님 칭찬 한 번
    when 'quiz'           then 5     -- 깜짝 퀴즈 정답
    when 'honor_gardener' then 500   -- 2주 꾸준 식집사
    else 0
  end;
$$;

--   조절할 수 있는 폭 (앱의 막대가 이 범위 안에서 움직인다)
create or replace function point_rule_range(p_reason text)
returns table (min_amount int, max_amount int, step int)
language sql immutable as $$
  select * from (values
    ('checkin_daily',  0, 300,  10),
    ('checkin_weekly', 0, 2000, 50),
    ('praise',         0, 300,  10),
    ('quiz',           0, 100,  5),
    ('honor_gardener', 0, 2000, 50)
  ) as v(reason, min_amount, max_amount, step)
  where v.reason = p_reason;
$$;

--   지금 이 학교의 금액. 서버의 지급 함수들이 이 값을 읽는다.
create or replace function point_amount(p_school uuid, p_reason text)
returns int
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select r.amount from school_point_rules r
      where r.school_id = p_school and r.reason = p_reason),
    point_rule_default(p_reason));
$$;
grant execute on function point_amount(uuid, text) to authenticated;

--   목록 (선생님이면 볼 수 있다)
create or replace function point_rules()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text;
  v_items json;
begin
  select school_id, role into v_school, v_role
    from profiles where user_id = auth.uid();
  if v_school is null or v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 볼 수 있어요');
  end if;

  select json_agg(json_build_object(
           'reason', v.reason,
           'label', v.label,
           'hint', v.hint,
           'amount', point_amount(v_school, v.reason),
           'default', point_rule_default(v.reason),
           'min', r.min_amount, 'max', r.max_amount, 'step', r.step)
         order by v.sort)
    into v_items
    from (values
      ('checkin_daily',  '일일 자기점검',   '학생이 하루 점검을 마치면',            1),
      ('checkin_weekly', '주간 개근 보너스', '월~금 수업일에 모두 점검한 주',        2),
      ('praise',         '선생님 칭찬',     '선생님이 칭찬을 보낼 때마다',          3),
      ('quiz',           '깜짝 퀴즈 정답',  '하루 한 번, 퀴즈를 맞히면',            4),
      ('honor_gardener', '2주 꾸준 식집사', '2주마다 가장 꾸준히 점검한 학생 한 명', 5)
    ) as v(reason, label, hint, sort)
    cross join lateral point_rule_range(v.reason) r;

  return json_build_object(
    'ok', true,
    'can_edit', is_admin_teacher(),
    'items', coalesce(v_items, '[]'::json));
end $$;
grant execute on function point_rules() to authenticated;

--   바꾸기 (관리자만). p_amount 가 null 이면 기본값으로 되돌린다.
create or replace function set_point_rule(p_reason text, p_amount int)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid;
  v_min int; v_max int; v_step int;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 바꿀 수 있어요');
  end if;
  select school_id into v_school from profiles where user_id = auth.uid();
  if v_school is null then
    return json_build_object('ok', false, 'error', '학교를 찾을 수 없어요');
  end if;

  select r.min_amount, r.max_amount, r.step into v_min, v_max, v_step
    from point_rule_range(p_reason) r;
  if v_min is null then
    return json_build_object('ok', false, 'error', '바꿀 수 없는 항목이에요');
  end if;

  if p_amount is null then
    delete from school_point_rules
     where school_id = v_school and reason = p_reason;
    return json_build_object('ok', true, 'amount', point_rule_default(p_reason));
  end if;

  if p_amount < v_min or p_amount > v_max then
    return json_build_object('ok', false,
      'error', v_min || ' ~ ' || v_max || 'P 사이로 정해주세요');
  end if;

  insert into school_point_rules (school_id, reason, amount, updated_by)
  values (v_school, p_reason, p_amount - (p_amount % v_step), auth.uid())
  on conflict (school_id, reason) do update
    set amount = excluded.amount, updated_at = now(), updated_by = excluded.updated_by;

  return json_build_object('ok', true,
                           'amount', point_amount(v_school, p_reason));
end $$;
grant execute on function set_point_rule(text, int) to authenticated;

-- ═══════════ 2) 지급 함수들이 위 금액을 읽도록 ═══════════
create or replace function award_checkin_points_internal(
  p_user_id uuid, p_school_id uuid, p_checkin_date date)
returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  v_daily int;
  v_weekly int;
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

  v_daily := point_amount(p_school_id, 'checkin_daily');
  if v_daily > 0 then
    insert into point_transactions
      (user_id, school_id, amount, reason, period_key, description)
    values
      (p_user_id, p_school_id, v_daily, 'checkin_daily', v_period_key, '일일 자기점검 참여')
    on conflict (user_id, reason, period_key) do nothing;
  end if;

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

    v_weekly := point_amount(p_school_id, 'checkin_weekly');
    if v_done >= 5 and v_weekly > 0 then
      insert into point_transactions
        (user_id, school_id, amount, reason, period_key, description)
      values
        (p_user_id, p_school_id, v_weekly, 'checkin_weekly', v_week_key, '주간 개근 보너스')
      on conflict (user_id, reason, period_key) do nothing;
    end if;
  end if;
end $$;
revoke execute on function award_checkin_points_internal(uuid, uuid, date)
  from authenticated, anon, public;

create or replace function public.give_praise(
  p_student_user_id uuid,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_praise_pts int;
  caller_role text;
  caller_school uuid;
  student_school uuid;
  v_praise_id uuid;
  v_count int;
  b record;
begin
  select role, school_id into caller_role, caller_school
  from profiles where user_id = auth.uid();
  if caller_role is null then raise exception '로그인 상태가 아닙니다.'; end if;
  if caller_role <> 'teacher' then raise exception '교사만 칭찬할 수 있어요.'; end if;

  select school_id into student_school
  from profiles where user_id = p_student_user_id and role = 'student';
  if student_school is null then raise exception '학생을 찾을 수 없어요.'; end if;
  if student_school is distinct from caller_school then
    raise exception '같은 학교 학생만 칭찬할 수 있어요.';
  end if;
  if char_length(coalesce(trim(p_message), '')) = 0 then
    raise exception '칭찬 내용을 입력해주세요.';
  end if;

  -- 칭찬 기록
  insert into praise (school_id, teacher_id, student_id, message)
  values (caller_school, auth.uid(), p_student_user_id, trim(p_message))
  returning id into v_praise_id;

  -- 칭찬마다 고유 period_key = praise id → 중복 없이 매번 적립
  -- 금액은 학교가 정한다 (관리자 → 포인트 설정, 기본 50P)
  v_praise_pts := point_amount(caller_school, 'praise');
  if v_praise_pts > 0 then
    insert into point_transactions (user_id, school_id, amount, reason, period_key, description)
    values (p_student_user_id, caller_school, v_praise_pts, 'praise', v_praise_id::text, '교사 칭찬');
  end if;

  -- 누적 칭찬 횟수
  select count(*) into v_count from praise where student_id = p_student_user_id;

  -- 조건을 충족하는 칭찬 배지 모두 부여
  for b in
    select id from badges
    where condition_type = 'praise_count' and condition_value <= v_count
  loop
    insert into user_badges (user_id, badge_id)
    values (p_student_user_id, b.id)
    on conflict (user_id, badge_id) do nothing;
  end loop;

  return jsonb_build_object('praise_id', v_praise_id, 'praise_count', v_count);
end;
$$;

revoke all on function public.give_praise(uuid, text) from public;
grant execute on function public.give_praise(uuid, text) to authenticated;

create or replace function give_praise_bulk(
  p_student_ids uuid[], p_message text)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_praise_pts int;
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

  v_praise_pts := point_amount(v_school, 'praise');

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

    if v_praise_pts > 0 then
      insert into point_transactions
        (user_id, school_id, amount, reason, period_key, description)
      values (v_sid, v_school, v_praise_pts, 'praise', v_praise_id::text, '교사 칭찬')
      on conflict do nothing;
    end if;

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

create or replace function submit_quiz(p_rule_id uuid, p_answer text)
returns json language plpgsql security definer set search_path = public, auth as $$
declare
  v_profile profiles; v_rule school_rules; v_q quiz_questions;
  v_accepted text[]; v_correct boolean; v_points int := 0; v_shown text;
begin
  select * into v_profile from profiles where user_id = auth.uid();
  if v_profile.id is null or v_profile.school_id is null then
    return json_build_object('ok', false, 'error', '프로필을 찾을 수 없어요');
  end if;
  if exists (select 1 from quiz_attempts where user_id = auth.uid()
             and quiz_date = (now() at time zone 'Asia/Seoul')::date) then
    return json_build_object('ok', false, 'error', '오늘 퀴즈는 이미 참여했어요');
  end if;

  -- 지식 퀴즈인지 규칙 퀴즈인지 id로 판별
  select * into v_q from quiz_questions
   where id = p_rule_id and school_id = v_profile.school_id and is_active;
  if v_q.id is not null then
    v_accepted := v_q.answers;
    v_shown := v_q.answers[1];
  else
    select * into v_rule from school_rules
     where id = p_rule_id and school_id = v_profile.school_id and is_active;
    if v_rule.id is null then
      return json_build_object('ok', false, 'error', '문제를 찾을 수 없어요');
    end if;
    v_shown := quiz_keyword(v_rule.rule_text);
    v_accepted := quiz_rule_answers(v_shown);
  end if;

  v_correct := quiz_is_correct(p_answer, v_accepted);
  if v_correct then
    v_points := case when v_profile.role = 'student'
                     then point_amount(v_profile.school_id, 'quiz') else 3 end;
  end if;

  insert into quiz_attempts (school_id, user_id, rule_id, correct, awarded)
  values (v_profile.school_id, auth.uid(),
          case when v_q.id is not null then null else p_rule_id end,
          v_correct, v_points);

  if v_correct then
    if v_profile.role = 'student' then
      if v_points > 0 then
        insert into point_transactions (user_id, school_id, amount, reason, period_key, description)
        values (auth.uid(), v_profile.school_id, v_points, 'quiz',
                to_char((now() at time zone 'Asia/Seoul')::date, 'YYYY-MM-DD'),
                '깜짝 퀴즈 정답')
        on conflict do nothing;
      end if;
    else
      perform award_teacher_points(auth.uid(), v_profile.school_id, 3, 'quiz', p_rule_id, 1);
    end if;
  end if;

  return json_build_object('ok', true, 'correct', v_correct,
                           'points', v_points, 'keyword', v_shown);
end $$;
grant execute on function submit_quiz(uuid, text) to authenticated;

create or replace function select_honor_gardener()
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_pts int;
  v_school uuid; v_start date; v_end date;
  v_winner uuid; v_days int; v_avg int; v_name text;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 선정할 수 있어요');
  end if;
  select school_id into v_school from profiles where user_id = auth.uid();

  -- 방금 끝난 회차를 대상으로 한다
  v_start := honor_cycle_start() - 14;
  v_end := v_start + 13;

  if exists (select 1 from honor_gardener
              where school_id = v_school and cycle_start = v_start) then
    return json_build_object('ok', false, 'error', '이번 회차는 이미 선정했어요');
  end if;

  select d.user_id,
         count(distinct d.checkin_date)::int,
         round(avg(d.score_pct))::int
    into v_winner, v_days, v_avg
    from daily_checkins d
    join profiles p on p.user_id = d.user_id and p.role = 'student'
   where d.school_id = v_school
     and d.checkin_date between v_start and v_end
   group by d.user_id
   order by count(distinct d.checkin_date) desc, avg(d.score_pct) desc, random()
   limit 1;

  if v_winner is null then
    return json_build_object('ok', false, 'error', '지난 2주에 점검 기록이 없어요');
  end if;

  insert into honor_gardener (school_id, cycle_start, cycle_end,
                              winner_user_id, days_done, avg_score)
  values (v_school, v_start, v_end, v_winner, v_days, v_avg);

  v_pts := point_amount(v_school, 'honor_gardener');
  if v_pts > 0 then
    insert into point_transactions (user_id, school_id, amount, reason, period_key, description)
    values (v_winner, v_school, v_pts, 'honor_gardener',
            to_char(v_start, 'YYYY-MM-DD'), '2주 꾸준 식집사 선정')
    on conflict do nothing;
  end if;

  select nickname into v_name from profiles where user_id = v_winner;

  perform push_notification(
    v_school, 'school', null, null, null, 'notice',
    '🌿 2주 꾸준 식집사가 선정됐어요',
    coalesce(v_name, '한 학생') || ' 학생이 지난 2주 동안 가장 꾸준히 자기점검을 했어요.'
      || case when v_pts > 0 then ' ' || v_pts || 'P를 받았습니다!' else '' end,
    '/student/points',
    'honor:' || v_school::text || ':' || to_char(v_start, 'YYYYMMDD'));

  return json_build_object('ok', true, 'name', v_name,
                           'days', v_days, 'avg', v_avg);
end $$;
grant execute on function select_honor_gardener() to authenticated;

-- ═══════════ 3) 칭찬 우체통 여는 시간 ═══════════
create or replace function send_praise_mail(
  p_recipient uuid,
  p_template text,
  p_anonymous boolean default true
)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_me profiles;
  v_to profiles;
  v_week date := praise_mail_week();
  v_used int;
  v_sentence text;
  v_id uuid;
begin
  select * into v_me from profiles where user_id = auth.uid();
  if v_me.user_id is null or v_me.role <> 'student' or v_me.left_at is not null then
    return json_build_object('ok', false, 'error', '학생만 칭찬을 보낼 수 있어요');
  end if;

  -- 자기점검과 같은 시간에 연다 (수업일 · 하교 후).
  -- 수업 중에 주고받느라 수업을 방해하지 않도록.
  if not is_school_day(v_me.school_id, (now() at time zone 'Asia/Seoul')::date) then
    return json_build_object('ok', false, 'error', '칭찬 우체통은 수업일에만 열려요');
  end if;
  if not is_checkin_open(v_me.school_id) then
    return json_build_object('ok', false, 'error',
      '칭찬 우체통은 ' || to_char(checkin_open_time(v_me.school_id), 'HH24:MI') || ' 부터 열려요');
  end if;

  select * into v_to from profiles where user_id = p_recipient;
  if v_to.user_id is null or v_to.role <> 'student' or v_to.left_at is not null
     or v_to.school_id is distinct from v_me.school_id then
    return json_build_object('ok', false, 'error', '칭찬할 친구를 찾을 수 없어요');
  end if;
  if v_to.user_id = v_me.user_id then
    return json_build_object('ok', false, 'error', '나에게는 보낼 수 없어요');
  end if;
  -- 같은 반만
  if v_to.grade is distinct from v_me.grade
     or v_to.class_num is distinct from v_me.class_num then
    return json_build_object('ok', false, 'error', '같은 반 친구에게만 보낼 수 있어요');
  end if;

  -- 문장은 서버 목록에서만 꺼낸다
  select sentence into v_sentence from praise_mail_templates
   where id = p_template and is_active;
  if v_sentence is null then
    return json_build_object('ok', false, 'error', '문장을 다시 골라주세요');
  end if;

  -- 같은 학생이 두 번 눌러 4번째가 끼어드는 일을 막는다
  perform pg_advisory_xact_lock(hashtextextended('praise_mail:' || auth.uid()::text, 0));

  select count(*)::int into v_used
    from praise_mail where sender_id = auth.uid() and week_start = v_week;
  if v_used >= 3 then
    return json_build_object('ok', false, 'error',
      '이번 주 칭찬 3번을 모두 보냈어요. 월요일에 다시 보낼 수 있어요');
  end if;

  if exists (select 1 from praise_mail
              where sender_id = auth.uid() and recipient_id = p_recipient
                and week_start = v_week) then
    return json_build_object('ok', false, 'error',
      '이번 주에 이미 이 친구에게 보냈어요. 다른 친구를 칭찬해 주세요');
  end if;

  insert into praise_mail
    (school_id, sender_id, recipient_id, template_id, is_anonymous, week_start)
  values
    (v_me.school_id, auth.uid(), p_recipient, p_template,
     coalesce(p_anonymous, true), v_week)
  returning id into v_id;

  perform push_notification(
    v_me.school_id, 'user', p_recipient, null, null,
    'praise_mail',
    '💌 칭찬 우체통에 편지가 도착했어요',
    v_sentence,
    '/student/praise-mail',
    v_id::text);

  return json_build_object('ok', true, 'remaining', greatest(0, 2 - v_used));
end $$;
grant execute on function send_praise_mail(uuid, text, boolean) to authenticated;

-- ═══════════ 4) 강화물 교환 순위 ═══════════
--   수령까지 끝난 교환만 센다. 이름은 가운데를 가린다.
create or replace function exchange_leaders(p_limit int default 3, p_days int default 90)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid;
  v_items json;
begin
  select school_id into v_school from profiles where user_id = auth.uid();
  if v_school is null then
    return json_build_object('ok', false);
  end if;

  select coalesce(json_agg(json_build_object(
           'label', t.grade || '-' || t.class_num || ' ' || mask_name(t.nickname),
           'count', t.cnt,
           'points', t.spent,
           'is_me', t.user_id = auth.uid())
         order by t.cnt desc, t.spent desc), '[]'::json)
    into v_items
    from (
      select p.user_id, p.grade, p.class_num, p.nickname,
             count(*)::int as cnt,
             coalesce(sum(e.cost_points), 0)::int as spent
        from point_exchanges e
        join profiles p on p.user_id = e.user_id
       where e.school_id = v_school
         and e.status = 'fulfilled'
         and e.requested_at >= now() - make_interval(days => greatest(1, coalesce(p_days, 90)))
         and p.role = 'student' and p.left_at is null
         and p.grade is not null and p.class_num is not null
       group by p.user_id, p.grade, p.class_num, p.nickname
       order by count(*) desc, sum(e.cost_points) desc
       limit greatest(1, least(p_limit, 10))
    ) t;

  return json_build_object('ok', true, 'days', p_days, 'items', v_items);
end $$;
grant execute on function exchange_leaders(int, int) to authenticated;

-- ═══════════ 확인 ═══════════
--   select * from point_rules();                    -- 선생님으로 로그인한 앱에서
--   select reason, amount from school_point_rules;  -- 학교가 따로 정한 값만 들어 있다
