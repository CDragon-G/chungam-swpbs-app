-- 059_kodr_tiered_support.sql
-- K-ODR 기록을 CICO(Tier 2) · 학생맞춤통합지원(Tier 3) 으로 바로 잇는다.
--
-- 흐름
--   K-ODR 이 저장되는 순간 그 학생의 누적 건수를 센다.
--     · 최근 30일 3건 이상                          → CICO 권장     (Tier 2)
--     · 최근 30일 5건 이상 또는 학년도 누적 7건 이상  → 학맞통 안건   (Tier 3)
--   기준에 처음 닿으면 관리자(리더십팀) 선생님께 알림이 가고,
--   Tier 3 는 '학맞통 안건' 목록에 자동으로 올라간다.
--
-- 기준값의 근거
--   흔히 인용되는 PBIS(SWIS) 기준은 '한 해' 동안
--     0~1건 → Tier 1 (보편 지원), 2~5건 → Tier 2, 6건 이상 → Tier 3.
--   학년도 누적만 보면 한 달에 몰아서 생긴 위기를 늦게 알아차리고,
--   최근 30일만 보면 한 달에 1~2건씩 꾸준히 이어지는 학생을 놓친다.
--   그래서 Tier 3 는 두 창을 함께 본다 (급성: 30일 5건 / 만성: 학년도 7건).
--   학교마다 관리자가 조정할 수 있다.
--
-- 기존 CICO 권장 목록은 '이달' 기준이라 매달 1일이면 0건으로 초기화됐다.
-- 9월 30일에 3건이던 학생이 10월 1일 목록에서 사라진다. 최근 30일로 바꾼다.
--
-- 개인정보
--   학맞통 대상 여부는 매우 민감하다.
--   · 목록과 안건은 관리자 선생님만 본다 (표를 직접 읽을 수 없고 함수로만)
--   · 알림 문구에는 학생 이름을 넣지 않는다 (잠금화면에 뜰 수 있어서)
--   · 회의 내용(자유 서술)은 저장하지 않는다. 상태와 회의 날짜만 둔다.
--     회의록은 학교의 학맞통 공식 기록에 남기는 것이 맞다.

-- ═══════════ 1) 학교별 기준 ═══════════
alter table schools add column if not exists kodr_window_days int not null default 30
  check (kodr_window_days between 7 and 90);
alter table schools add column if not exists kodr_tier3_threshold int not null default 5
  check (kodr_tier3_threshold between 2 and 20);
alter table schools add column if not exists kodr_tier3_year_threshold int not null default 7
  check (kodr_tier3_year_threshold between 0 and 60);   -- 0 이면 누적 기준 끔

-- CICO 기준(036)은 1~10 이었다. Tier 3 보다 크면 순서가 뒤집히므로 확인은 설정 함수에서.

create or replace function get_support_settings()
returns json
language sql stable security definer set search_path = public, auth as $$
  select json_build_object(
    'ok', true,
    'window_days', s.kodr_window_days,
    'cico', s.kodr_cico_threshold,
    'tier3', s.kodr_tier3_threshold,
    'tier3_year', s.kodr_tier3_year_threshold)
  from schools s where s.id = current_profile_school();
$$;
grant execute on function get_support_settings() to authenticated;

create or replace function set_support_settings(
  p_window_days int, p_cico int, p_tier3 int, p_tier3_year int)
returns json
language plpgsql security definer set search_path = public, auth as $$
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 바꿀 수 있어요');
  end if;
  if p_window_days not between 7 and 90 then
    return json_build_object('ok', false, 'error', '기간은 7~90일 사이로 정해주세요');
  end if;
  if p_cico not between 1 and 10 then
    return json_build_object('ok', false, 'error', 'CICO 기준은 1~10건 사이로 정해주세요');
  end if;
  if p_tier3 not between 2 and 20 then
    return json_build_object('ok', false, 'error', '학맞통 기준은 2~20건 사이로 정해주세요');
  end if;
  if p_tier3 <= p_cico then
    return json_build_object('ok', false, 'error',
      '학맞통 기준은 CICO 기준보다 커야 해요');
  end if;
  if p_tier3_year <> 0 and p_tier3_year not between p_tier3 and 60 then
    return json_build_object('ok', false, 'error',
      '학년도 누적 기준은 0(끔) 이거나 학맞통 기준 이상이어야 해요');
  end if;

  update schools
     set kodr_window_days = p_window_days,
         kodr_cico_threshold = p_cico,
         kodr_tier3_threshold = p_tier3,
         kodr_tier3_year_threshold = p_tier3_year
   where id = current_profile_school();
  return json_build_object('ok', true);
end $$;
grant execute on function set_support_settings(int, int, int, int) to authenticated;

-- 036 의 CICO 기준 설정도 순서가 뒤집히지 않게 막는다 (CICO 화면에서 쓰는 함수)
create or replace function set_kodr_cico_threshold(p_value int)
returns json language plpgsql security definer set search_path = public as $$
declare v_t3 int;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '리더십팀(관리자)만 변경할 수 있어요');
  end if;
  if p_value < 1 or p_value > 10 then
    return json_build_object('ok', false, 'error', '1~10건 사이로 설정해주세요');
  end if;
  select kodr_tier3_threshold into v_t3 from schools where id = current_profile_school();
  if p_value >= v_t3 then
    return json_build_object('ok', false, 'error',
      'CICO 기준은 학맞통 기준(' || v_t3 || '건)보다 작아야 해요');
  end if;
  update schools set kodr_cico_threshold = p_value
   where id = current_profile_school();
  return json_build_object('ok', true);
end $$;
grant execute on function set_kodr_cico_threshold(int) to authenticated;

-- ═══════════ 2) 학맞통 안건 ═══════════
create table if not exists support_referrals (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  trigger text not null check (trigger in ('kodr_window', 'kodr_year', 'manual')),
  window_count int not null default 0,     -- 올라온 순간의 최근 N일 건수
  year_count int not null default 0,       -- 올라온 순간의 학년도 누적 건수
  status text not null default 'open'
    check (status in ('open', 'scheduled', 'supporting', 'monitoring', 'closed')),
  meeting_date date,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz
);
-- 한 학생에게 열린 안건은 하나만
create unique index if not exists support_referrals_one_open
  on support_referrals (student_id) where status <> 'closed';
create index if not exists support_referrals_school_idx
  on support_referrals (school_id, status, created_at desc);

--   읽기 정책 없음. 관리자 함수로만 접근한다.
alter table support_referrals enable row level security;

-- 알림 중복 방지 기록 (Tier 2 · 3). 같은 학생에게 기간 안에 두 번 알리지 않는다.
create table if not exists kodr_tier_alerts (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  tier int not null check (tier in (2, 3)),
  alerted_at timestamptz not null default now()
);
create index if not exists kodr_tier_alerts_idx
  on kodr_tier_alerts (student_id, tier, alerted_at desc);
alter table kodr_tier_alerts enable row level security;

-- ═══════════ 3) 건수 세기 ═══════════
create or replace function kodr_counts(p_school uuid, p_student uuid)
returns table (window_count int, year_count int)
language sql stable security definer set search_path = public, auth as $$
  select
    (select count(*)::int from kodr_records k, schools s
      where s.id = p_school and k.school_id = p_school and k.student_id = p_student
        and k.occurred_date > (now() at time zone 'Asia/Seoul')::date - s.kodr_window_days),
    (select count(*)::int from kodr_records k
      where k.school_id = p_school and k.student_id = p_student
        and k.occurred_date >= growth_year_start());
$$;
revoke all on function kodr_counts(uuid, uuid) from public, anon, authenticated;

create or replace function student_label(p_user uuid)
returns text
language sql stable security definer set search_path = public as $$
  select case when grade is not null and class_num is not null
              then grade || '학년 ' || class_num || '반' else '학생' end
    from profiles where user_id = p_user;
$$;
revoke all on function student_label(uuid) from public, anon, authenticated;

-- ═══════════ 4) K-ODR 이 저장될 때 바로 판정 ═══════════
create or replace function evaluate_kodr_tier(p_school uuid, p_student uuid)
returns text
language plpgsql security definer set search_path = public, auth as $$
declare
  s schools;
  c record;
  v_trigger text;
  v_id uuid;
begin
  select * into s from schools where id = p_school;
  if s.id is null then return null; end if;
  if not exists (select 1 from profiles where user_id = p_student
                   and role = 'student' and left_at is null) then
    return null;
  end if;

  select * into c from kodr_counts(p_school, p_student);

  -- Tier 3: 급성(최근 N일) 또는 만성(학년도 누적)
  v_trigger := case
    when c.window_count >= s.kodr_tier3_threshold then 'kodr_window'
    when s.kodr_tier3_year_threshold > 0
         and c.year_count >= s.kodr_tier3_year_threshold then 'kodr_year'
    else null end;

  if v_trigger is not null then
    if exists (select 1 from support_referrals
                where student_id = p_student and status <> 'closed') then
      return 'tier3_open';   -- 이미 안건에 올라 있음
    end if;

    -- 같은 학생의 K-ODR 두 건이 동시에 저장되면 둘 다 여기로 온다.
    -- 중복 안건 대신 조용히 넘어간다.
    insert into support_referrals
      (school_id, student_id, trigger, window_count, year_count)
    values (p_school, p_student, v_trigger, c.window_count, c.year_count)
    on conflict (student_id) where status <> 'closed' do nothing
    returning id into v_id;
    if v_id is null then
      return 'tier3_open';
    end if;

    insert into kodr_tier_alerts (school_id, student_id, tier)
    values (p_school, p_student, 3);

    -- 이름은 넣지 않는다. 잠금화면에 뜰 수 있다.
    perform push_notification(
      p_school, 'admins', null, null, null,
      'support_referral',
      '🧩 학맞통 안건 검토가 필요해요',
      student_label(p_student) || ' 학생 1명이 기준에 닿았어요 · '
        || case v_trigger
             when 'kodr_window' then '최근 ' || s.kodr_window_days || '일 K-ODR '
                                      || c.window_count || '건'
             else '학년도 누적 K-ODR ' || c.year_count || '건' end,
      '/teacher/support',
      v_id::text);
    return 'tier3_new';
  end if;

  -- Tier 2: CICO 권장. 이미 CICO 중이면 알리지 않는다.
  if c.window_count >= s.kodr_cico_threshold then
    if exists (select 1 from cico_enrollments
                where student_id = p_student and status = 'active') then
      return 'tier2_in_cico';
    end if;
    if exists (select 1 from kodr_tier_alerts
                where student_id = p_student and tier = 2
                  and alerted_at > now() - make_interval(days => s.kodr_window_days)) then
      return 'tier2_alerted';
    end if;

    insert into kodr_tier_alerts (school_id, student_id, tier)
    values (p_school, p_student, 2);

    perform push_notification(
      p_school, 'admins', null, null, null,
      'cico_recommend',
      '🔔 CICO 시작을 검토해 주세요',
      student_label(p_student) || ' 학생 1명이 최근 ' || s.kodr_window_days
        || '일 K-ODR ' || c.window_count || '건이에요',
      '/teacher/cico',
      'cico:' || p_student::text || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
    return 'tier2_new';
  end if;

  return null;
end $$;
revoke all on function evaluate_kodr_tier(uuid, uuid) from public, anon, authenticated;

--   판정이나 알림에서 무슨 일이 나도 K-ODR 기록은 반드시 저장한다.
--   선생님이 적은 관찰 기록을 연계 기능 때문에 잃는 일은 없어야 한다.
create or replace function trg_kodr_tier() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    perform evaluate_kodr_tier(new.school_id, new.student_id);
  exception when others then
    raise warning 'evaluate_kodr_tier failed: %', sqlerrm;
  end;
  return new;
end $$;
drop trigger if exists kodr_tier_eval on kodr_records;
create trigger kodr_tier_eval after insert on kodr_records
  for each row execute function trg_kodr_tier();

-- ═══════════ 5) CICO 후보 — '이달' → '최근 N일' ═══════════
drop function if exists cico_candidates();
create or replace function cico_candidates()
returns table (
  student_id uuid, nickname text, grade int, class_num int, student_num int,
  kodr_count bigint, threshold int
)
language sql stable security definer set search_path = public as $$
  with me as (
    select p.school_id from profiles p
     where p.user_id = auth.uid() and p.role = 'teacher'
  ),
  th as (
    select s.id as sid, s.kodr_cico_threshold as t, s.kodr_window_days as w
      from schools s join me on s.id = me.school_id
  )
  select p.user_id, p.nickname, p.grade, p.class_num, p.student_num,
         k.cnt, th.t
    from th
    join (
      select kr.student_id, kr.school_id, count(*) as cnt
        from kodr_records kr, th
       where kr.school_id = th.sid
         and kr.occurred_date > (now() at time zone 'Asia/Seoul')::date - th.w
       group by kr.student_id, kr.school_id
    ) k on k.school_id = th.sid and k.cnt >= th.t
    join profiles p on p.user_id = k.student_id and p.role = 'student'
                   and p.left_at is null
   where not exists (
     select 1 from cico_enrollments e
      where e.student_id = k.student_id and e.status = 'active'
   )
   order by k.cnt desc, p.grade, p.class_num, p.student_num;
$$;
grant execute on function cico_candidates() to authenticated;

-- ═══════════ 6) 관리자 — 학맞통 안건 목록 (회의 자료) ═══════════
--   숫자만 보여준다. 어디서·어떤 행동이 많았는지 상위 3개까지.
create or replace function support_referral_list(p_include_closed boolean default false)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  s schools;
  v_items json;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 볼 수 있어요');
  end if;
  select * into s from schools where id = v_school;

  select coalesce(json_agg(row_to_json(t) order by
           case t.status when 'open' then 0 when 'scheduled' then 1
                         when 'supporting' then 2 when 'monitoring' then 3 else 4 end,
           t.created_at desc), '[]'::json)
    into v_items
  from (
    select r.id, r.status, r.trigger, r.meeting_date, r.created_at, r.closed_at,
           r.window_count as window_count_at, r.year_count as year_count_at,
           p.nickname as name, p.grade, p.class_num, p.student_num,
           (select count(*)::int from kodr_records k
             where k.student_id = r.student_id and k.school_id = v_school
               and k.occurred_date > (now() at time zone 'Asia/Seoul')::date - s.kodr_window_days)
             as window_count,
           (select count(*)::int from kodr_records k
             where k.student_id = r.student_id and k.school_id = v_school
               and k.occurred_date >= growth_year_start()) as year_count,
           (select count(*)::int from kodr_records k
             where k.student_id = r.student_id and k.school_id = v_school
               and k.needs_intervention
               and k.occurred_date >= growth_year_start()) as urgent_count,
           (select max(k.occurred_date) from kodr_records k
             where k.student_id = r.student_id and k.school_id = v_school) as last_kodr,
           (select coalesce(json_agg(x.place order by x.n desc), '[]'::json) from (
              select k.place, count(*) n from kodr_records k
               where k.student_id = r.student_id and k.school_id = v_school
                 and k.occurred_date >= growth_year_start()
                 and coalesce(k.place, '') <> ''
               group by k.place order by n desc limit 3) x) as top_places,
           (select coalesce(json_agg(x.behavior order by x.n desc), '[]'::json) from (
              select k.behavior, count(*) n from kodr_records k
               where k.student_id = r.student_id and k.school_id = v_school
                 and k.occurred_date >= growth_year_start()
               group by k.behavior order by n desc limit 3) x) as top_behaviors,
           (select e.status from cico_enrollments e
             where e.student_id = r.student_id
             order by e.created_at desc limit 1) as cico_status
      from support_referrals r
      join profiles p on p.user_id = r.student_id
     where r.school_id = v_school
       and (p_include_closed or r.status <> 'closed')
  ) t;

  return json_build_object(
    'ok', true,
    'window_days', s.kodr_window_days,
    'items', v_items);
end $$;
grant execute on function support_referral_list(boolean) to authenticated;

create or replace function update_support_referral(
  p_id uuid, p_status text, p_meeting_date date default null)
returns json
language plpgsql security definer set search_path = public, auth as $$
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 바꿀 수 있어요');
  end if;
  if p_status not in ('open', 'scheduled', 'supporting', 'monitoring', 'closed') then
    return json_build_object('ok', false, 'error', '상태를 확인해 주세요');
  end if;

  update support_referrals
     set status = p_status,
         meeting_date = coalesce(p_meeting_date, meeting_date),
         updated_at = now(),
         closed_at = case when p_status = 'closed' then now() else null end
   where id = p_id and school_id = current_profile_school();

  if not found then
    return json_build_object('ok', false, 'error', '안건을 찾을 수 없어요');
  end if;
  return json_build_object('ok', true);
end $$;
grant execute on function update_support_referral(uuid, text, date) to authenticated;

-- 기준에 닿지 않았어도 리더십팀이 판단해 직접 올린다 (한 번의 심각한 사건 등)
create or replace function create_support_referral(p_student uuid)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare v_school uuid := current_profile_school(); c record; v_id uuid;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 안건을 올릴 수 있어요');
  end if;
  if not exists (select 1 from profiles where user_id = p_student
                   and school_id = v_school and role = 'student') then
    return json_build_object('ok', false, 'error', '우리 학교 학생이 아니에요');
  end if;
  if exists (select 1 from support_referrals
              where student_id = p_student and status <> 'closed') then
    return json_build_object('ok', false, 'error', '이미 안건에 올라 있어요');
  end if;

  select * into c from kodr_counts(v_school, p_student);
  insert into support_referrals
    (school_id, student_id, trigger, window_count, year_count, created_by)
  values (v_school, p_student, 'manual', c.window_count, c.year_count, auth.uid())
  on conflict (student_id) where status <> 'closed' do nothing
  returning id into v_id;
  if v_id is null then
    return json_build_object('ok', false, 'error', '이미 안건에 올라 있어요');
  end if;
  return json_build_object('ok', true, 'id', v_id);
end $$;
grant execute on function create_support_referral(uuid) to authenticated;

-- 기준을 바꿨거나 이 기능을 처음 켰을 때, 지금 기준으로 전교생을 다시 본다.
-- 알림은 학생마다 보내지 않고 한 건으로 묶는다.
create or replace function scan_support_referrals()
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  s schools;
  r record;
  c record;
  v_new int := 0;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 실행할 수 있어요');
  end if;
  select * into s from schools where id = v_school;

  for r in
    select distinct k.student_id from kodr_records k
      join profiles p on p.user_id = k.student_id
                     and p.role = 'student' and p.left_at is null
     where k.school_id = v_school and k.occurred_date >= growth_year_start()
  loop
    if exists (select 1 from support_referrals
                where student_id = r.student_id and status <> 'closed') then
      continue;
    end if;
    select * into c from kodr_counts(v_school, r.student_id);
    if c.window_count >= s.kodr_tier3_threshold
       or (s.kodr_tier3_year_threshold > 0
           and c.year_count >= s.kodr_tier3_year_threshold) then
      insert into support_referrals
        (school_id, student_id, trigger, window_count, year_count, created_by)
      values (v_school, r.student_id,
              case when c.window_count >= s.kodr_tier3_threshold
                   then 'kodr_window' else 'kodr_year' end,
              c.window_count, c.year_count, auth.uid())
      on conflict (student_id) where status <> 'closed' do nothing;
      if found then
        insert into kodr_tier_alerts (school_id, student_id, tier)
        values (v_school, r.student_id, 3);
        v_new := v_new + 1;
      end if;
    end if;
  end loop;

  return json_build_object('ok', true, 'added', v_new);
end $$;
grant execute on function scan_support_referrals() to authenticated;

-- ═══════════ 7) 확인 ═══════════
--   select name, kodr_window_days, kodr_cico_threshold,
--          kodr_tier3_threshold, kodr_tier3_year_threshold from schools;
--   select status, count(*) from support_referrals group by status;
