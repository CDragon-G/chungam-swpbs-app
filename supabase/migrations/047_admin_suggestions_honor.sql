-- 047_admin_suggestions_honor.sql
--   1) 관리자의 교사 관리 — 비밀번호 초기화 · 계정 삭제
--   2) 규칙 건의함 — 학생이 올리고 관리자만 본다
--   3) 규칙별 O/X 통계 — 잘 지켜지는 규칙 / 안 지켜지는 규칙
--   4) 명예 식집사 — 2주마다 한 명, 500P
--   5) 성장 레벨업 감지 — 앱을 켤 때 축하 팝업을 띄우기 위한 기록

-- ═══════════ 1) 교사 관리 (관리자 전용) ═══════════
--   담임 선생님이 비밀번호를 잊는 일이 반복된다. 메일 발송은 시간당 2건
--   제한이 있어 쓸 수 없으므로, 관리자가 앱에서 바로 초기화한다.
create or replace function reset_teacher_password(
  p_profile_id uuid, p_new_password text
)
returns json
language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  v_school uuid; v_target_user uuid; v_target_school uuid; v_target_role text;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 초기화할 수 있어요');
  end if;
  if length(coalesce(p_new_password, '')) < 6 then
    return json_build_object('ok', false, 'error', '비밀번호는 6자 이상이어야 해요');
  end if;

  select school_id into v_school from profiles where user_id = auth.uid();
  select user_id, school_id, role
    into v_target_user, v_target_school, v_target_role
    from profiles where id = p_profile_id;

  if v_target_user is null then
    return json_build_object('ok', false, 'error', '선생님을 찾을 수 없어요');
  end if;
  if v_target_school is distinct from v_school then
    return json_build_object('ok', false, 'error', '우리 학교 선생님만 초기화할 수 있어요');
  end if;
  if v_target_role <> 'teacher' then
    return json_build_object('ok', false, 'error', '교사 계정이 아니에요');
  end if;
  if v_target_user = auth.uid() then
    return json_build_object('ok', false, 'error', '본인 계정은 여기서 바꿀 수 없어요');
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
         updated_at = now()
   where id = v_target_user;

  return json_build_object('ok', true);
end $$;
revoke all on function reset_teacher_password(uuid, text) from public;
grant execute on function reset_teacher_password(uuid, text) to authenticated;

--   퇴직·전근 교사 정리. 남긴 칭찬·기록은 지우지 않고 계정만 없앤다.
create or replace function delete_teacher(p_profile_id uuid)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid; v_target_user uuid; v_target_school uuid;
  v_target_role text; v_target_teacher_role text; v_name text;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 삭제할 수 있어요');
  end if;

  select school_id into v_school from profiles where user_id = auth.uid();
  select user_id, school_id, role, teacher_role, name
    into v_target_user, v_target_school, v_target_role, v_target_teacher_role, v_name
    from profiles where id = p_profile_id;

  if v_target_user is null then
    return json_build_object('ok', false, 'error', '선생님을 찾을 수 없어요');
  end if;
  if v_target_school is distinct from v_school then
    return json_build_object('ok', false, 'error', '우리 학교 선생님만 삭제할 수 있어요');
  end if;
  if v_target_role <> 'teacher' then
    return json_build_object('ok', false, 'error', '교사 계정이 아니에요');
  end if;
  if v_target_user = auth.uid() then
    return json_build_object('ok', false, 'error', '본인 계정은 삭제할 수 없어요');
  end if;
  -- 관리자가 한 명뿐인데 그 관리자를 지우면 학교가 잠긴다
  if v_target_teacher_role = 'admin' and (
       select count(*) from profiles
        where school_id = v_school and role = 'teacher' and teacher_role = 'admin') <= 1 then
    return json_build_object('ok', false, 'error', '마지막 관리자 선생님은 삭제할 수 없어요');
  end if;

  delete from auth.users where id = v_target_user;   -- profiles 는 cascade
  return json_build_object('ok', true, 'name', v_name);
end $$;
revoke all on function delete_teacher(uuid) from public;
grant execute on function delete_teacher(uuid) to authenticated;

-- ═══════════ 2) 규칙 건의함 ═══════════
--   학생이 규칙에 대해 건의한다. 관리자 선생님만 읽는다.
create table if not exists rule_suggestions (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  space text,                                   -- 어느 공간의 규칙인지 (선택)
  body text not null check (length(btrim(body)) between 5 and 1000),
  status text not null default 'new'
    check (status in ('new', 'read', 'accepted', 'declined')),
  admin_note text,
  created_at timestamptz not null default now()
);
create index if not exists rs_school_idx
  on rule_suggestions(school_id, status, created_at desc);
alter table rule_suggestions enable row level security;

--   학생은 본인이 낸 것만 본다 (남의 건의는 못 본다)
drop policy if exists rs_own on rule_suggestions;
create policy rs_own on rule_suggestions
  for select to authenticated using (user_id = auth.uid());

--   관리자만 학교 전체를 본다
drop policy if exists rs_admin_read on rule_suggestions;
create policy rs_admin_read on rule_suggestions
  for select to authenticated
  using (school_id = current_profile_school() and is_admin_teacher());

drop policy if exists rs_admin_update on rule_suggestions;
create policy rs_admin_update on rule_suggestions
  for update to authenticated
  using (school_id = current_profile_school() and is_admin_teacher());
-- 등록은 RPC로만 (도배 방지)

create or replace function submit_rule_suggestion(p_body text, p_space text default null)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare v_school uuid; v_today int;
begin
  select school_id into v_school from profiles where user_id = auth.uid();
  if v_school is null then
    return json_build_object('ok', false, 'error', '로그인이 필요해요');
  end if;
  if length(btrim(coalesce(p_body, ''))) < 5 then
    return json_build_object('ok', false, 'error', '5글자 이상 적어주세요');
  end if;

  select count(*) into v_today from rule_suggestions
   where user_id = auth.uid()
     and created_at >= (now() at time zone 'Asia/Seoul')::date;
  if v_today >= 3 then
    return json_build_object('ok', false, 'error', '하루에 3개까지 보낼 수 있어요');
  end if;

  insert into rule_suggestions (school_id, user_id, space, body)
  values (v_school, auth.uid(), nullif(btrim(p_space), ''), btrim(p_body));

  return json_build_object('ok', true);
end $$;
grant execute on function submit_rule_suggestion(text, text) to authenticated;

--   관리자용 목록 — 누가 냈는지 이름과 학반까지
create or replace function rule_suggestion_list(p_limit int default 100)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare v_out json;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 볼 수 있어요');
  end if;
  select coalesce(json_agg(t order by t.created_at desc), '[]'::json) into v_out
  from (
    select s.id, s.body, s.space, s.status, s.admin_note, s.created_at,
           p.nickname, p.grade, p.class_num, p.student_num
      from rule_suggestions s
      join profiles p on p.user_id = s.user_id
     where s.school_id = current_profile_school()
     order by s.created_at desc
     limit greatest(1, least(p_limit, 500))
  ) t;
  return json_build_object('ok', true, 'items', v_out);
end $$;
grant execute on function rule_suggestion_list(int) to authenticated;

-- ═══════════ 3) 규칙별 O/X 통계 ═══════════
--   answers 는 {규칙id: true/false}. 규칙마다 지킨 비율을 뽑아
--   잘 지켜지는 규칙과 어려운 규칙을 가른다.
create or replace function rule_compliance_stats(p_days int default 30)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_from date;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_out json;
begin
  select school_id into v_school from profiles
   where user_id = auth.uid() and role = 'teacher';
  if v_school is null then
    return json_build_object('ok', false, 'error', '교사만 볼 수 있어요');
  end if;
  v_from := v_today - (greatest(1, least(p_days, 180)) - 1);

  select coalesce(json_agg(t order by t.kept_pct, t.space, t.rule_text), '[]'::json)
    into v_out
  from (
    select r.id, r.space, r.rule_text,
           count(*)::int as total,
           count(*) filter (where a.value::text = 'true')::int as kept,
           round(100.0 * count(*) filter (where a.value::text = 'true')
                 / nullif(count(*), 0))::int as kept_pct
      from daily_checkins d
      cross join lateral jsonb_each(d.answers) as a(key, value)
      join school_rules r on r.id = a.key::uuid
     where d.school_id = v_school
       and d.checkin_date >= v_from
       and r.school_id = v_school
       and r.is_active
     group by r.id, r.space, r.rule_text
    having count(*) >= 5           -- 표본이 너무 적으면 의미가 없다
  ) t;

  return json_build_object('ok', true, 'days', p_days, 'rules', v_out);
end $$;
grant execute on function rule_compliance_stats(int) to authenticated;

-- ═══════════ 4) 명예 식집사 ═══════════
--   2주에 한 명. 기준일(2026-03-02 월요일)부터 14일 단위로 회차를 끊는다.
create table if not exists honor_gardener (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  cycle_start date not null,
  cycle_end date not null,
  winner_user_id uuid references auth.users(id) on delete set null,
  days_done int not null default 0,
  avg_score int not null default 0,
  awarded int not null default 500,
  selected_at timestamptz not null default now(),
  unique (school_id, cycle_start)
);
alter table honor_gardener enable row level security;

drop policy if exists hg_read on honor_gardener;
create policy hg_read on honor_gardener
  for select to authenticated using (school_id = current_profile_school());
-- 쓰기는 RPC로만

create or replace function honor_cycle_start(p_date date default null)
returns date
language sql immutable as $$
  select date '2026-03-02'
       + (floor((coalesce(p_date, (now() at time zone 'Asia/Seoul')::date)
                 - date '2026-03-02') / 14.0) * 14)::int;
$$;
grant execute on function honor_cycle_start(date) to authenticated;

--   선정 — 지난 회차에서 점검을 가장 성실히 한 학생.
--   1순위 참여일수, 2순위 평균점수, 동점이면 무작위.
create or replace function select_honor_gardener()
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
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

  insert into point_transactions (user_id, school_id, amount, reason, period_key, description)
  values (v_winner, v_school, 500, 'honor_gardener',
          to_char(v_start, 'YYYY-MM-DD'), '명예 식집사 선정')
  on conflict do nothing;

  select nickname into v_name from profiles where user_id = v_winner;

  perform push_notification(
    v_school, 'school', null, null, null, 'notice',
    '🌿 명예 식집사가 선정됐어요',
    coalesce(v_name, '한 학생') || ' 학생이 지난 2주 동안 가장 꾸준히 자기점검을 했어요. 500P를 받았습니다!',
    '/student/points',
    'honor:' || v_school::text || ':' || to_char(v_start, 'YYYYMMDD'));

  return json_build_object('ok', true, 'name', v_name,
                           'days', v_days, 'avg', v_avg);
end $$;
grant execute on function select_honor_gardener() to authenticated;

--   현재 명예 식집사 + 다음 선정까지 남은 시간
create or replace function honor_gardener_status()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  v_cur date := honor_cycle_start();
  v_next_at timestamptz;
  v_row honor_gardener;
  v_name text;
begin
  if v_school is null then return json_build_object('ok', false); end if;

  -- 지금 회차의 명예 식집사는 '직전 회차'에서 뽑힌 사람
  select * into v_row from honor_gardener
   where school_id = v_school and cycle_start = v_cur - 14;
  if v_row.winner_user_id is not null then
    select nickname into v_name from profiles where user_id = v_row.winner_user_id;
  end if;

  -- 다음 회차 시작 = 지금 회차 시작 + 14일 00:00 (KST)
  v_next_at := ((v_cur + 14)::timestamp at time zone 'Asia/Seoul');

  return json_build_object(
    'ok', true,
    'cycle_start', v_cur,
    'next_at', v_next_at,
    'seconds_left', greatest(0, extract(epoch from (v_next_at - now()))::bigint),
    'winner', v_name,
    'winner_days', v_row.days_done,
    'winner_avg', v_row.avg_score,
    'is_me', v_row.winner_user_id = auth.uid(),
    'pending', not exists (select 1 from honor_gardener
                            where school_id = v_school and cycle_start = v_cur - 14));
end $$;
grant execute on function honor_gardener_status() to authenticated;

-- ═══════════ 5) 성장 레벨업 감지 ═══════════
--   레벨 계산은 앱에서 한다(점수 + 관문). 앱이 계산한 레벨을 넘기면
--   이전에 본 레벨과 비교해 '처음 보는 레벨'인지 알려준다.
create table if not exists growth_level_seen (
  user_id uuid primary key references auth.users(id) on delete cascade,
  school_id uuid not null references schools(id) on delete cascade,
  level int not null,
  seen_at timestamptz not null default now()
);
alter table growth_level_seen enable row level security;

drop policy if exists gls_own on growth_level_seen;
create policy gls_own on growth_level_seen
  for select to authenticated using (user_id = auth.uid());

create or replace function check_growth_level(p_level int)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare v_school uuid; v_prev int;
begin
  select school_id into v_school from profiles where user_id = auth.uid();
  if v_school is null or p_level is null or p_level < 1 then
    return json_build_object('leveled_up', false);
  end if;

  select level into v_prev from growth_level_seen where user_id = auth.uid();

  insert into growth_level_seen (user_id, school_id, level)
  values (auth.uid(), v_school, p_level)
  on conflict (user_id) do update
    set level = greatest(growth_level_seen.level, excluded.level),
        school_id = excluded.school_id,
        seen_at = now();

  -- 처음 기록하는 사용자는 축하하지 않는다 (가입 직후 팝업 폭탄 방지)
  return json_build_object(
    'leveled_up', v_prev is not null and p_level > v_prev,
    'from', v_prev, 'to', p_level);
end $$;
grant execute on function check_growth_level(int) to authenticated;
