-- 070_kodr_roster_students.sql
-- K-ODR 을 '가입한 학생 계정' 이 아니라 '명렬표의 학생' 기준으로 기록한다.
--
-- 무엇이 문제였나
--   K-ODR 은 학생의 앱 계정(auth.users)에 붙어 있었다. 그래서
--     · 앱에 가입하지 않은 학생은 K-ODR 을 쓸 수 없었다 (검색에 안 나옴)
--     · CICO · 학맞통 판정도 가입한 학생만 했다
--   그런데 학교 적응이 어려운 학생일수록 앱에 가입하지 않았을 가능성이 크다.
--   가장 지원이 필요한 학생이 가장 먼저 빠지는 구조였다.
--
--   또 학생이 스스로 탈퇴하면 그 학생의 K-ODR 과 학맞통 안건이 계정과 함께 지워졌다.
--
-- 어떻게 바꿨나
--   · 명렬표 한 줄(student_roster.id)을 '그 학생' 으로 본다.
--     진급 처리(055)는 명렬표 줄을 지우지 않고 옮기므로, 가입 여부와 상관없이
--     학년이 바뀌어도 같은 학생을 가리킨다.
--   · 기록마다 명렬표 줄(roster_id)과, 가입했다면 계정(student_id)을 함께 둔다.
--     나중에 가입하면 그동안의 기록이 계정에 저절로 이어진다.
--   · 판정 · 안건 · 집계는 subject_id = coalesce(roster_id, student_id) 로 센다.
--   · 기록할 때의 이름 · 학년 · 반 · 번호를 함께 적어 둔다.
--     명렬표에서 빠져도(졸업 · 전출) 누구의 기록인지 알 수 있다.
--   · 탈퇴해도 K-ODR · 학맞통 안건은 지워지지 않는다 (계정 칸만 비워진다).
--
-- 구버전 앱
--   · 계정으로 기록하는 옛 방식도 그대로 된다. 명렬표 줄은 서버가 채운다.
--   · 월별 집계의 student_id 는 가입한 학생이면 계정, 아니면 명렬표 줄을 준다.
--     그래서 구버전의 'CICO 시작' · '학맞통 안건으로 올리기' 도 가입한 학생에게는 그대로 동작한다.

-- ═══════════ 0) 참조 규칙 — 계정이 지워져도 기록은 남는다 ═══════════
--   기존 제약 이름을 짐작하지 않고 실제로 걸린 것을 찾아 지운 뒤 새로 건다.
do $$
declare c record;
begin
  for c in
    select con.conname, rel.relname
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_attribute att
        on att.attrelid = con.conrelid and att.attnum = any(con.conkey)
     where con.contype = 'f'
       and rel.relnamespace = 'public'::regnamespace
       and att.attname = 'student_id'
       and rel.relname in ('kodr_records', 'support_referrals', 'kodr_tier_alerts')
  loop
    execute format('alter table public.%I drop constraint %I', c.relname, c.conname);
  end loop;
end $$;

alter table kodr_records alter column student_id drop not null;
alter table kodr_records add constraint kodr_records_student_id_fkey
  foreign key (student_id) references auth.users(id) on delete set null;

alter table support_referrals alter column student_id drop not null;
alter table support_referrals add constraint support_referrals_student_id_fkey
  foreign key (student_id) references auth.users(id) on delete set null;

alter table kodr_tier_alerts alter column student_id drop not null;
alter table kodr_tier_alerts add constraint kodr_tier_alerts_student_id_fkey
  foreign key (student_id) references auth.users(id) on delete set null;

-- ═══════════ 1) 명렬표 줄 + 기록 당시의 학생 정보 ═══════════
alter table kodr_records
  add column if not exists roster_id uuid references student_roster(id) on delete set null,
  add column if not exists student_name text,
  add column if not exists student_grade int,
  add column if not exists student_class int,
  add column if not exists student_no int;

alter table support_referrals
  add column if not exists roster_id uuid references student_roster(id) on delete set null;

alter table kodr_tier_alerts
  add column if not exists roster_id uuid references student_roster(id) on delete set null;

-- 지금까지의 기록에 명렬표 줄을 채운다 (가입할 때 차지한 자리)
update kodr_records k
   set roster_id = r.id
  from student_roster r
 where k.roster_id is null and k.student_id is not null
   and r.claimed_by = k.student_id and r.school_id = k.school_id;

update kodr_records k
   set student_name = p.nickname,
       student_grade = p.grade,
       student_class = p.class_num,
       student_no = p.student_num
  from profiles p
 where k.student_name is null and p.user_id = k.student_id;

update support_referrals s
   set roster_id = r.id
  from student_roster r
 where s.roster_id is null and s.student_id is not null
   and r.claimed_by = s.student_id and r.school_id = s.school_id;

update kodr_tier_alerts a
   set roster_id = r.id
  from student_roster r
 where a.roster_id is null and a.student_id is not null
   and r.claimed_by = a.student_id and r.school_id = a.school_id;

-- '그 학생' 을 가리키는 열쇠
alter table kodr_records
  add column if not exists subject_id uuid
  generated always as (coalesce(roster_id, student_id)) stored;
alter table support_referrals
  add column if not exists subject_id uuid
  generated always as (coalesce(roster_id, student_id)) stored;
alter table kodr_tier_alerts
  add column if not exists subject_id uuid
  generated always as (coalesce(roster_id, student_id)) stored;

create index if not exists kodr_subject_idx
  on kodr_records (school_id, subject_id, occurred_date desc);
create index if not exists kodr_tier_alerts_subject_idx
  on kodr_tier_alerts (subject_id, tier, alerted_at desc);

-- 한 학생에게 열린 안건은 하나만 (계정 기준 → 학생 기준)
drop index if exists support_referrals_one_open;
create unique index if not exists support_referrals_one_open_subject
  on support_referrals (subject_id) where status <> 'closed';

-- ═══════════ 2) 기록할 때 빈칸 채우기 ═══════════
--   새 앱은 명렬표 줄로, 구버전 앱은 계정으로 기록한다. 어느 쪽이든 나머지를 채운다.
create or replace function trg_kodr_fill_subject() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_rid uuid;
  r student_roster;
  p profiles;
begin
  if new.roster_id is null and new.student_id is not null then
    select id into v_rid from student_roster
     where claimed_by = new.student_id and school_id = new.school_id
     limit 1;
    new.roster_id := v_rid;
  end if;

  if new.roster_id is not null then
    select * into r from student_roster where id = new.roster_id;
    if r.id is null or r.school_id is distinct from new.school_id then
      raise exception '우리 학교 명단에 없는 학생이에요';
    end if;
    if new.student_id is null then
      new.student_id := r.claimed_by;
    end if;
    new.student_name  := coalesce(new.student_name, r.name);
    new.student_grade := coalesce(new.student_grade, r.grade);
    new.student_class := coalesce(new.student_class, r.class_num);
    new.student_no    := coalesce(new.student_no, r.student_num);
  end if;

  if new.student_name is null and new.student_id is not null then
    select * into p from profiles where user_id = new.student_id;
    new.student_name  := p.nickname;
    new.student_grade := p.grade;
    new.student_class := p.class_num;
    new.student_no    := p.student_num;
  end if;

  if new.roster_id is null and new.student_id is null then
    raise exception '학생을 골라주세요';
  end if;
  return new;
end $$;

drop trigger if exists kodr_fill_subject on kodr_records;
create trigger kodr_fill_subject before insert on kodr_records
  for each row execute function trg_kodr_fill_subject();

-- ═══════════ 3) 나중에 가입하면 기록을 계정에 잇는다 ═══════════
create or replace function trg_roster_link_kodr() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.claimed_by is not null
     and new.claimed_by is distinct from old.claimed_by then
    update kodr_records set student_id = new.claimed_by
     where roster_id = new.id and student_id is null;
    update support_referrals set student_id = new.claimed_by
     where roster_id = new.id and student_id is null;
    update kodr_tier_alerts set student_id = new.claimed_by
     where roster_id = new.id and student_id is null;
  end if;
  return new;
end $$;

drop trigger if exists roster_link_kodr on student_roster;
create trigger roster_link_kodr after update of claimed_by on student_roster
  for each row execute function trg_roster_link_kodr();

-- 가입하지 않은 자리에 다른 이름이 올라오면 (명렬표를 새로 올려 사람이 바뀐 경우)
-- 앞 사람의 기록을 그 자리에서 떼어 낸다. 새로 온 학생의 기록으로 섞이지 않게.
-- 기록에는 이름이 적혀 있으므로 누구의 것인지는 계속 보인다.
create or replace function trg_roster_detach_kodr() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not old.claimed
     and roster_name_key(new.name) is distinct from roster_name_key(old.name) then
    update kodr_records set roster_id = null
     where roster_id = old.id and student_id is null;
    update support_referrals set roster_id = null
     where roster_id = old.id and student_id is null;
    update kodr_tier_alerts set roster_id = null
     where roster_id = old.id and student_id is null;
  end if;
  return new;
end $$;

drop trigger if exists roster_detach_kodr on student_roster;
create trigger roster_detach_kodr before update of name on student_roster
  for each row execute function trg_roster_detach_kodr();

-- ═══════════ 4) 학생(subject) 도우미 ═══════════
-- 그 학생의 앱 계정 (없으면 null)
create or replace function subject_student(p_subject uuid)
returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select claimed_by from student_roster where id = p_subject),
    (select user_id from profiles where user_id = p_subject));
$$;
revoke all on function subject_student(uuid) from public, anon, authenticated;

-- 알림에 쓰는 표시 (이름은 넣지 않는다 — 잠금화면에 뜰 수 있다)
create or replace function subject_label(p_subject uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select r.grade || '학년 ' || r.class_num || '반' from student_roster r where r.id = p_subject),
    (select p.grade || '학년 ' || p.class_num || '반' from profiles p
      where p.user_id = p_subject and p.grade is not null and p.class_num is not null),
    '학생');
$$;
revoke all on function subject_label(uuid) from public, anon, authenticated;

-- 지금 이 학교에 다니는 학생인가 (명렬표에 있거나, 떠나지 않은 계정)
create or replace function subject_is_current(p_school uuid, p_subject uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from student_roster r
                  where r.id = p_subject and r.school_id = p_school)
      or exists (select 1 from profiles p
                  where p.user_id = p_subject and p.school_id = p_school
                    and p.role = 'student' and p.left_at is null);
$$;
revoke all on function subject_is_current(uuid, uuid) from public, anon, authenticated;

-- 건수 (두 번째 인자는 이제 '학생' — 명렬표 줄 또는 계정)
create or replace function kodr_counts(p_school uuid, p_student uuid)
returns table (window_count int, year_count int)
language sql stable security definer set search_path = public, auth as $$
  select
    (select count(*)::int from kodr_records k, schools s
      where s.id = p_school and k.school_id = p_school and k.subject_id = p_student
        and k.occurred_date > (now() at time zone 'Asia/Seoul')::date - s.kodr_window_days),
    (select count(*)::int from kodr_records k
      where k.school_id = p_school and k.subject_id = p_student
        and k.occurred_date >= growth_year_start());
$$;
revoke all on function kodr_counts(uuid, uuid) from public, anon, authenticated;

-- ═══════════ 5) K-ODR 이 저장될 때 판정 (학생 기준) ═══════════
create or replace function evaluate_kodr_tier(p_school uuid, p_student uuid)
returns text
language plpgsql security definer set search_path = public, auth as $$
declare
  s schools;
  c record;
  v_trigger text;
  v_id uuid;
  v_roster uuid;
  v_user uuid;
  v_joined text;
begin
  select * into s from schools where id = p_school;
  if s.id is null or p_student is null then return null; end if;
  if not subject_is_current(p_school, p_student) then
    return null;
  end if;

  v_roster := (select id from student_roster where id = p_student);
  v_user := subject_student(p_student);
  v_joined := case when v_user is null then ' · 앱 미가입' else '' end;

  select * into c from kodr_counts(p_school, p_student);

  -- Tier 3: 급성(최근 N일) 또는 만성(학년도 누적)
  v_trigger := case
    when c.window_count >= s.kodr_tier3_threshold then 'kodr_window'
    when s.kodr_tier3_year_threshold > 0
         and c.year_count >= s.kodr_tier3_year_threshold then 'kodr_year'
    else null end;

  if v_trigger is not null then
    if exists (select 1 from support_referrals
                where subject_id = p_student and status <> 'closed') then
      return 'tier3_open';
    end if;

    insert into support_referrals
      (school_id, roster_id, student_id, trigger, window_count, year_count)
    values (p_school, v_roster, v_user, v_trigger, c.window_count, c.year_count)
    on conflict (subject_id) where status <> 'closed' do nothing
    returning id into v_id;
    if v_id is null then
      return 'tier3_open';
    end if;

    insert into kodr_tier_alerts (school_id, roster_id, student_id, tier)
    values (p_school, v_roster, v_user, 3);

    perform push_notification(
      p_school, 'admins', null, null, null,
      'support_referral',
      '🧩 학맞통 안건 검토가 필요해요',
      subject_label(p_student) || ' 학생 1명이 기준에 닿았어요 · '
        || case v_trigger
             when 'kodr_window' then '최근 ' || s.kodr_window_days || '일 K-ODR '
                                      || c.window_count || '건'
             else '학년도 누적 K-ODR ' || c.year_count || '건' end
        || v_joined,
      '/teacher/support',
      v_id::text);
    return 'tier3_new';
  end if;

  -- Tier 2: CICO 권장. 이미 CICO 중이면 알리지 않는다.
  if c.window_count >= s.kodr_cico_threshold then
    if v_user is not null and exists (
         select 1 from cico_enrollments
          where student_id = v_user and status = 'active') then
      return 'tier2_in_cico';
    end if;
    if exists (select 1 from kodr_tier_alerts
                where subject_id = p_student and tier = 2
                  and alerted_at > now() - make_interval(days => s.kodr_window_days)) then
      return 'tier2_alerted';
    end if;

    insert into kodr_tier_alerts (school_id, roster_id, student_id, tier)
    values (p_school, v_roster, v_user, 2);

    perform push_notification(
      p_school, 'admins', null, null, null,
      'cico_recommend',
      '🔔 CICO 시작을 검토해 주세요',
      subject_label(p_student) || ' 학생 1명이 최근 ' || s.kodr_window_days
        || '일 K-ODR ' || c.window_count || '건이에요' || v_joined,
      '/teacher/cico',
      'cico:' || p_student::text || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
    return 'tier2_new';
  end if;

  return null;
end $$;
revoke all on function evaluate_kodr_tier(uuid, uuid) from public, anon, authenticated;

create or replace function trg_kodr_tier() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    perform evaluate_kodr_tier(new.school_id, coalesce(new.roster_id, new.student_id));
  exception when others then
    raise warning 'evaluate_kodr_tier failed: %', sqlerrm;
  end;
  return new;
end $$;

-- ═══════════ 6) 여러 학생을 한 번에 기록 ═══════════
--   한 사건에 여러 학생이 함께 있었을 때. 학생마다 한 건씩, 모두 같은 내용으로.
--   하나라도 문제가 있으면 아무것도 저장하지 않는다.
create or replace function create_kodr_records(
  p_roster_ids uuid[],
  p_occurred_date date,
  p_behavior text,
  p_place text default null,
  p_situation text default null,
  p_immediate text default null,
  p_secondary text default null,
  p_reaction text default null,
  p_author_role text default null,
  p_note text default null
)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid;
  v_role text;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_n int;
begin
  select school_id, role into v_school, v_role
    from profiles where user_id = auth.uid();
  if v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 기록할 수 있어요');
  end if;
  if p_roster_ids is null or coalesce(array_length(p_roster_ids, 1), 0) = 0 then
    return json_build_object('ok', false, 'error', '학생을 골라주세요');
  end if;
  if array_length(p_roster_ids, 1) > 30 then
    return json_build_object('ok', false, 'error', '한 번에 30명까지 기록할 수 있어요');
  end if;
  if coalesce(btrim(p_behavior), '') = '' then
    return json_build_object('ok', false, 'error', '행동양상을 골라주세요');
  end if;
  if p_occurred_date is null or p_occurred_date > v_today then
    return json_build_object('ok', false, 'error', '날짜를 확인해주세요');
  end if;
  if exists (select 1 from unnest(p_roster_ids) x
              where not exists (select 1 from student_roster r
                                 where r.id = x and r.school_id = v_school)) then
    return json_build_object('ok', false, 'error', '우리 학교 명단에 없는 학생이 섞여 있어요');
  end if;

  insert into kodr_records
    (school_id, roster_id, teacher_id, occurred_date, behavior, place, situation,
     immediate_response, secondary_response, student_reaction, author_role, note)
  select v_school, t.rid, auth.uid(), p_occurred_date, btrim(p_behavior),
         nullif(btrim(p_place), ''), nullif(btrim(p_situation), ''),
         nullif(btrim(p_immediate), ''), nullif(btrim(p_secondary), ''),
         nullif(btrim(p_reaction), ''), nullif(btrim(p_author_role), ''),
         nullif(btrim(p_note), '')
    from (select distinct unnest(p_roster_ids) as rid) t;
  get diagnostics v_n = row_count;

  return json_build_object('ok', true, 'count', v_n);
end $$;
grant execute on function
  create_kodr_records(uuid[], date, text, text, text, text, text, text, text, text)
  to authenticated;

-- ═══════════ 7) K-ODR 에서 고를 학생 — 가입 여부와 상관없이 명렬표 전체 ═══════════
create or replace function kodr_student_options()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare v_school uuid; v_role text; v_items json;
begin
  select school_id, role into v_school, v_role
    from profiles where user_id = auth.uid();
  if v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 볼 수 있어요');
  end if;

  select coalesce(json_agg(json_build_object(
           'roster_id', r.id,
           'name', r.name,
           'grade', r.grade,
           'class_num', r.class_num,
           'student_num', r.student_num,
           'joined', r.claimed_by is not null)
         order by r.grade, r.class_num, r.student_num), '[]'::json)
    into v_items
    from student_roster r
   where r.school_id = v_school;

  return json_build_object('ok', true, 'items', v_items);
end $$;
grant execute on function kodr_student_options() to authenticated;

-- ═══════════ 8) 월별 집계 — 가입하지 않은 학생도 ═══════════
--   구버전 앱이 쓰는 모양은 그대로 둔다.
--   student_id: 가입한 학생이면 계정, 아니면 명렬표 줄 (구버전의 CICO · 안건 버튼이 그대로 동작하도록)
create or replace function public.kodr_monthly_summary(
  p_school_id uuid,
  p_year_month text default null
)
returns table (
  student_id uuid,
  nickname text,
  grade int,
  class_num int,
  student_num int,
  record_count int,
  needs_cico boolean
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  caller_role text;
  caller_school uuid;
  ym text := coalesce(p_year_month, to_char((now() at time zone 'Asia/Seoul'), 'YYYY-MM'));
  d_start date := to_date(ym || '-01', 'YYYY-MM-DD');
  d_end date := (to_date(ym || '-01', 'YYYY-MM-DD') + interval '1 month')::date;
begin
  select role, school_id into caller_role, caller_school
  from profiles where user_id = auth.uid();
  if caller_role <> 'teacher' or caller_school is distinct from p_school_id then
    raise exception '본인 학교 교사만 조회할 수 있어요.';
  end if;

  return query
  select coalesce(max(k.student_id::text), k.subject_id::text)::uuid,
         coalesce(max(r.name), max(p.nickname), max(k.student_name), '(이름 없음)'),
         coalesce(max(r.grade), max(p.grade), max(k.student_grade), 0),
         coalesce(max(r.class_num), max(p.class_num), max(k.student_class), 0),
         coalesce(max(r.student_num), max(p.student_num), max(k.student_no), 0),
         count(k.id)::int,
         (count(k.id) >= 3)
    from kodr_records k
    left join student_roster r on r.id = k.roster_id
    left join profiles p on p.user_id = k.student_id
   where k.school_id = p_school_id
     and k.subject_id is not null
     and k.occurred_date >= d_start and k.occurred_date < d_end
   group by k.subject_id
   order by count(k.id) desc, 3, 4, 5;
end;
$$;

--   새 앱용 — 가입 여부와 명렬표 줄을 함께 준다.
create or replace function kodr_month_subjects(p_year_month text default null)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text;
  ym text := coalesce(p_year_month, to_char((now() at time zone 'Asia/Seoul'), 'YYYY-MM'));
  d_start date := to_date(ym || '-01', 'YYYY-MM-DD');
  d_end date := (to_date(ym || '-01', 'YYYY-MM-DD') + interval '1 month')::date;
  v_threshold int;
  v_items json;
begin
  select school_id, role into v_school, v_role
    from profiles where user_id = auth.uid();
  if v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 볼 수 있어요');
  end if;
  select kodr_cico_threshold into v_threshold from schools where id = v_school;

  select coalesce(json_agg(row_to_json(t) order by t.record_count desc,
                           t.grade, t.class_num, t.student_num), '[]'::json)
    into v_items
  from (
    select k.subject_id,
           max(k.roster_id::text)::uuid as roster_id,
           max(k.student_id::text)::uuid as student_id,
           coalesce(max(r.name), max(p.nickname), max(k.student_name), '(이름 없음)') as name,
           coalesce(max(r.grade), max(p.grade), max(k.student_grade), 0) as grade,
           coalesce(max(r.class_num), max(p.class_num), max(k.student_class), 0) as class_num,
           coalesce(max(r.student_num), max(p.student_num), max(k.student_no), 0) as student_num,
           count(k.id)::int as record_count,
           count(k.id) >= coalesce(v_threshold, 3) as needs_cico,
           max(k.student_id::text) is not null as joined
      from kodr_records k
      left join student_roster r on r.id = k.roster_id
      left join profiles p on p.user_id = k.student_id
     where k.school_id = v_school
       and k.subject_id is not null
       and k.occurred_date >= d_start and k.occurred_date < d_end
     group by k.subject_id
  ) t;

  return json_build_object('ok', true, 'year_month', ym, 'items', v_items);
end $$;
grant execute on function kodr_month_subjects(text) to authenticated;

--   한 학생의 기록 목록 (가입 여부와 상관없이)
create or replace function kodr_subject_records(p_subject uuid, p_limit int default 50)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare v_school uuid; v_role text; v_items json;
begin
  select school_id, role into v_school, v_role
    from profiles where user_id = auth.uid();
  if v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 볼 수 있어요');
  end if;

  select coalesce(json_agg(json_build_object(
           'id', k.id, 'occurred_date', k.occurred_date, 'behavior', k.behavior,
           'place', k.place, 'situation', k.situation, 'note', k.note,
           'created_at', k.created_at)
         order by k.occurred_date desc, k.created_at desc), '[]'::json)
    into v_items
    from (select * from kodr_records
           where school_id = v_school and subject_id = p_subject
           order by occurred_date desc, created_at desc
           limit greatest(1, least(coalesce(p_limit, 50), 200))) k;

  return json_build_object('ok', true, 'items', v_items);
end $$;
grant execute on function kodr_subject_records(uuid, int) to authenticated;

-- ═══════════ 9) 학맞통 안건 — 학생 기준 ═══════════
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
    select rf.id, rf.status, rf.trigger, rf.meeting_date, rf.created_at, rf.closed_at,
           rf.window_count as window_count_at, rf.year_count as year_count_at,
           coalesce(ro.name, p.nickname,
                    (select k.student_name from kodr_records k
                      where k.subject_id = rf.subject_id and k.student_name is not null
                      order by k.created_at desc limit 1),
                    '(명단에서 빠진 학생)') as name,
           coalesce(ro.grade, p.grade) as grade,
           coalesce(ro.class_num, p.class_num) as class_num,
           coalesce(ro.student_num, p.student_num) as student_num,
           rf.student_id is not null as joined,
           (select count(*)::int from kodr_records k
             where k.subject_id = rf.subject_id and k.school_id = v_school
               and k.occurred_date > (now() at time zone 'Asia/Seoul')::date - s.kodr_window_days)
             as window_count,
           (select count(*)::int from kodr_records k
             where k.subject_id = rf.subject_id and k.school_id = v_school
               and k.occurred_date >= growth_year_start()) as year_count,
           (select count(*)::int from kodr_records k
             where k.subject_id = rf.subject_id and k.school_id = v_school
               and k.needs_intervention
               and k.occurred_date >= growth_year_start()) as urgent_count,
           (select max(k.occurred_date) from kodr_records k
             where k.subject_id = rf.subject_id and k.school_id = v_school) as last_kodr,
           (select coalesce(json_agg(x.place order by x.n desc), '[]'::json) from (
              select k.place, count(*) n from kodr_records k
               where k.subject_id = rf.subject_id and k.school_id = v_school
                 and k.occurred_date >= growth_year_start()
                 and coalesce(k.place, '') <> ''
               group by k.place order by n desc limit 3) x) as top_places,
           (select coalesce(json_agg(x.behavior order by x.n desc), '[]'::json) from (
              select k.behavior, count(*) n from kodr_records k
               where k.subject_id = rf.subject_id and k.school_id = v_school
                 and k.occurred_date >= growth_year_start()
               group by k.behavior order by n desc limit 3) x) as top_behaviors,
           (select e.status from cico_enrollments e
             where rf.student_id is not null and e.student_id = rf.student_id
             order by e.created_at desc limit 1) as cico_status
      from support_referrals rf
      left join student_roster ro on ro.id = rf.roster_id
      left join profiles p on p.user_id = rf.student_id
     where rf.school_id = v_school
       and (p_include_closed or rf.status <> 'closed')
  ) t;

  return json_build_object(
    'ok', true,
    'window_days', s.kodr_window_days,
    'items', v_items);
end $$;
grant execute on function support_referral_list(boolean) to authenticated;

--   직접 안건으로 올리기. 인자는 학생 계정이든 명렬표 줄이든 받는다 (구버전 앱은 계정을 보낸다).
create or replace function create_support_referral(p_student uuid)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  v_roster uuid;
  v_user uuid;
  v_subject uuid;
  c record;
  v_id uuid;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 안건을 올릴 수 있어요');
  end if;

  select id into v_roster from student_roster
   where id = p_student and school_id = v_school;
  if v_roster is null then
    select id into v_roster from student_roster
     where claimed_by = p_student and school_id = v_school limit 1;
  end if;
  select user_id into v_user from profiles
   where user_id = p_student and school_id = v_school and role = 'student';
  if v_user is null and v_roster is not null then
    select claimed_by into v_user from student_roster where id = v_roster;
  end if;

  v_subject := coalesce(v_roster, v_user);
  if v_subject is null then
    return json_build_object('ok', false, 'error', '우리 학교 학생이 아니에요');
  end if;
  if exists (select 1 from support_referrals
              where subject_id = v_subject and status <> 'closed') then
    return json_build_object('ok', false, 'error', '이미 안건에 올라 있어요');
  end if;

  select * into c from kodr_counts(v_school, v_subject);
  insert into support_referrals
    (school_id, roster_id, student_id, trigger, window_count, year_count, created_by)
  values (v_school, v_roster, v_user, 'manual', c.window_count, c.year_count, auth.uid())
  on conflict (subject_id) where status <> 'closed' do nothing
  returning id into v_id;
  if v_id is null then
    return json_build_object('ok', false, 'error', '이미 안건에 올라 있어요');
  end if;
  return json_build_object('ok', true, 'id', v_id);
end $$;
grant execute on function create_support_referral(uuid) to authenticated;

--   지금 기준으로 전교생 다시 보기 (학생 기준)
create or replace function scan_support_referrals()
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  s schools;
  r record;
  c record;
  v_new int := 0;
  v_id uuid;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 실행할 수 있어요');
  end if;
  select * into s from schools where id = v_school;

  for r in
    select distinct k.subject_id from kodr_records k
     where k.school_id = v_school and k.subject_id is not null
       and k.occurred_date >= growth_year_start()
  loop
    if not subject_is_current(v_school, r.subject_id) then
      continue;
    end if;
    if exists (select 1 from support_referrals
                where subject_id = r.subject_id and status <> 'closed') then
      continue;
    end if;
    select * into c from kodr_counts(v_school, r.subject_id);
    if c.window_count >= s.kodr_tier3_threshold
       or (s.kodr_tier3_year_threshold > 0
           and c.year_count >= s.kodr_tier3_year_threshold) then
      v_id := null;
      insert into support_referrals
        (school_id, roster_id, student_id, trigger, window_count, year_count, created_by)
      values (v_school,
              (select id from student_roster where id = r.subject_id),
              subject_student(r.subject_id),
              case when c.window_count >= s.kodr_tier3_threshold
                   then 'kodr_window' else 'kodr_year' end,
              c.window_count, c.year_count, auth.uid())
      on conflict (subject_id) where status <> 'closed' do nothing
      returning id into v_id;
      if v_id is not null then
        insert into kodr_tier_alerts (school_id, roster_id, student_id, tier)
        values (v_school,
                (select id from student_roster where id = r.subject_id),
                subject_student(r.subject_id), 3);
        v_new := v_new + 1;
      end if;
    end if;
  end loop;

  return json_build_object('ok', true, 'added', v_new);
end $$;
grant execute on function scan_support_referrals() to authenticated;

-- ═══════════ 10) 체험 부스 초기화 — 가입 전 자리에 적은 K-ODR 도 ═══════════
-- 069 의 reset_demo_school 은 K-ODR 을 '가입한 학생' 기준으로만 지웠다.
-- 이제 가입하지 않은 명렬표 자리에도 K-ODR 을 적을 수 있으므로,
-- 초기화하는 반(또는 학교 전체)의 명렬표 자리에 붙은 기록도 함께 지운다.
-- 나머지는 069 와 똑같다. 체험용 학교(is_demo)가 아니면 아무것도 하지 않는다.
create or replace function reset_demo_school(
  p_school uuid default null,
  p_with_kodr boolean default true,
  p_scope text default 'class'
)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_my_grade int;
  v_my_class int;
  v_school uuid;
  v_scope text := coalesce(p_scope, 'class');
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_all uuid[];
  v_targets uuid[];
  v_teachers uuid[];
  v_teacher uuid;
  v_teacher_name text;
  s record;
  r record;
  d date;
  v_rate int;
  v_ok boolean;
  v_answers jsonb;
  v_total int;
  v_possible int;
  v_cats jsonb;
  v_ts timestamptz;
  v_praise_id uuid;
  v_praise_pts int;
  v_item_id uuid;
  v_checkins int := 0;
  v_students int := 0;
  v_note text := null;
begin
  -- ── 누가 어느 학교를 ──
  if v_uid is not null then
    select school_id, role, grade, class_num
      into v_school, v_role, v_my_grade, v_my_class
      from profiles where user_id = v_uid;
    if v_role is distinct from 'teacher' then
      return json_build_object('ok', false, 'error', '선생님만 초기화할 수 있어요');
    end if;
    if p_school is not null and p_school is distinct from v_school then
      return json_build_object('ok', false, 'error', '우리 학교만 초기화할 수 있어요');
    end if;
  else
    v_school := p_school;   -- SQL 에디터에서 학교를 지정
  end if;

  -- ── 핵심 안전장치: 체험 학교가 아니면 아무것도 하지 않는다 ──
  if v_school is null
     or not coalesce((select is_demo from schools where id = v_school), false) then
    return json_build_object('ok', false, 'error', '체험용 학교에서만 초기화할 수 있어요');
  end if;

  if v_scope not in ('class', 'all') then
    v_scope := 'class';
  end if;
  if v_scope = 'class' and (v_my_grade is null or v_my_class is null) then
    v_scope := 'all';   -- 담임 반이 없으면 (SQL 에디터 포함) 학교 전체
  end if;

  -- 두 태블릿에서 동시에 눌러도 차례로
  perform pg_advisory_xact_lock(hashtextextended('demo_reset:' || v_school::text, 0));

  select coalesce(array_agg(user_id), '{}') into v_all
    from profiles where school_id = v_school;
  select coalesce(array_agg(user_id order by created_at), '{}') into v_teachers
    from profiles where school_id = v_school and role = 'teacher';
  select coalesce(array_agg(user_id), '{}') into v_targets
    from profiles
   where school_id = v_school and role = 'student' and left_at is null
     and (v_scope = 'all' or (grade = v_my_grade and class_num = v_my_class));

  -- ── 1. 이 학생들의 기록 지우기 ──
  delete from point_exchanges where school_id = v_school and user_id = any(v_targets);
  delete from group_contributions where school_id = v_school and user_id = any(v_targets);
  delete from point_transactions where school_id = v_school and user_id = any(v_targets);
  delete from daily_checkins where school_id = v_school and user_id = any(v_targets);
  delete from checkin_streaks where user_id = any(v_targets);
  delete from checkin_semester_summary where user_id = any(v_targets);
  delete from praise where school_id = v_school and student_id = any(v_targets);
  delete from praise_mail
   where school_id = v_school
     and (sender_id = any(v_targets) or recipient_id = any(v_targets));
  delete from support_referrals
   where school_id = v_school
     and (student_id = any(v_targets)
          or roster_id in (select ro.id from student_roster ro where ro.school_id = v_school and (v_scope = 'all' or (ro.grade = v_my_grade and ro.class_num = v_my_class))));
  delete from kodr_tier_alerts
   where school_id = v_school
     and (student_id = any(v_targets)
          or roster_id in (select ro.id from student_roster ro where ro.school_id = v_school and (v_scope = 'all' or (ro.grade = v_my_grade and ro.class_num = v_my_class))));
  delete from kodr_records
   where school_id = v_school
     and (student_id = any(v_targets)
          or roster_id in (select ro.id from student_roster ro where ro.school_id = v_school and (v_scope = 'all' or (ro.grade = v_my_grade and ro.class_num = v_my_class))));
  delete from cico_enrollments where school_id = v_school and student_id = any(v_targets);
  delete from quiz_attempts where school_id = v_school and user_id = any(v_targets);
  delete from notifications where school_id = v_school and target_user_id = any(v_targets);
  delete from user_badges where user_id = any(v_targets);
  delete from growth_level_seen where school_id = v_school and user_id = any(v_targets);

  if v_scope = 'class' then
    -- 이 반의 알림 · 함께 키우기 · 누른 선생님의 퀴즈와 새싹 팝업
    delete from notifications
     where school_id = v_school and audience = 'class'
       and grade = v_my_grade and class_num = v_my_class;
    delete from point_store_items
     where school_id = v_school and item_type = 'group'
       and grade = v_my_grade and class_num = v_my_class;
    delete from quiz_attempts where school_id = v_school and user_id = v_uid;
    delete from growth_level_seen where school_id = v_school and user_id = v_uid;
  else
    -- 학교 전체
    delete from point_exchanges where school_id = v_school;
    delete from group_contributions where school_id = v_school;
    delete from point_store_items where school_id = v_school;
    delete from point_transactions where school_id = v_school;
    delete from notifications where school_id = v_school;
    delete from quiz_attempts where school_id = v_school;
    delete from user_badges where user_id = any(v_all);
    delete from growth_level_seen where school_id = v_school;
    delete from checkin_school_daily where school_id = v_school;
    delete from checkin_rule_semester_stats where school_id = v_school;
    delete from school_growth_year where school_id = v_school;
    delete from honor_gardener where school_id = v_school;
    delete from rule_suggestions where school_id = v_school;
    delete from class_votes where school_id = v_school;
    delete from teacher_exchanges where school_id = v_school;
    delete from teacher_point_transactions where school_id = v_school;
    delete from announcements where school_id = v_school;
    delete from school_point_rules where school_id = v_school;   -- 포인트는 기본값으로
    update schools set notified_growth_level = 0 where id = v_school;
  end if;

  -- 새싹 · 명예 식집사 숫자는 다시 계산되게
  delete from school_growth_cache where school_id = v_school;
  delete from weekly_honor_cache where school_id = v_school;

  -- ── 2. 학교 전체일 때만: 강화물 4개 · 환영 공지 ──
  if v_scope = 'all' then
    select nickname into v_teacher_name from profiles where user_id = v_teachers[1];
    insert into point_store_items
      (school_id, name, description, cost_points, stock, is_active, order_index,
       emoji, grade, class_num, created_by, created_by_name, item_type)
    values
      (v_school, '점심시간 신청곡', '방송실에서 내가 고른 노래 한 곡', 200, null, true, 1, '🎵', null, null, v_teachers[1], v_teacher_name, 'individual'),
      (v_school, '간식 교환권',     '매점 간식 하나',               300, null, true, 2, '🍭', null, null, v_teachers[1], v_teacher_name, 'individual'),
      (v_school, '예쁜 문구 세트',   '볼펜 · 메모지 세트',            500, 20,   true, 3, '✏️', null, null, v_teachers[1], v_teacher_name, 'individual'),
      (v_school, '원하는 자리 앉기', '하루 동안 원하는 자리에 앉기',   800, null, true, 4, '🪑', null, null, v_teachers[1], v_teacher_name, 'individual');

    insert into announcements (school_id, title, body, created_by)
    values (v_school, '🌱 자람 체험에 오신 걸 환영해요',
            '오늘의 자기점검을 해보고, 친구에게 칭찬 편지도 보내보세요. '
            || '모은 포인트로 교환소에서 강화물을 신청할 수 있어요!',
            v_teachers[1]);
  end if;

  -- ── 3. 학생마다 예시 기록 ──
  --   학교에서 몇 번째 학생인지(1·2·3반 순)로 모습을 정한다. 반 하나만 초기화해도
  --   그 학생은 늘 같은 모습으로 돌아온다.
  for s in
    select x.user_id, x.grade, x.class_num, x.idx
      from (
        select p.user_id, p.grade, p.class_num,
               row_number() over (
                 order by p.grade, p.class_num, p.student_num nulls last, p.created_at
               )::int as idx
          from profiles p
         where p.school_id = v_school and p.role = 'student' and p.left_at is null
      ) x
     where x.user_id = any(v_targets)
     order by x.idx
  loop
    v_students := v_students + 1;
    -- 꾸준한 학생 / 한 번 빠진 학생 / 들쭉날쭉한 학생
    v_rate := case s.idx when 1 then 92 when 2 then 82 else 68 end;

    -- 3-1. 최근 14일 자기점검
    for d in
      select g::date from generate_series(v_today - 14, v_today - 1, interval '1 day') g
    loop
      if (s.idx = 2 and d = v_today - 6)
         or (s.idx >= 3 and d in (v_today - 3, v_today - 9)) then
        continue;
      end if;

      v_answers := '{}'::jsonb; v_total := 0; v_possible := 0;
      for r in
        select sr.id from school_rules sr
         where sr.school_id = v_school and sr.is_active
         order by sr.order_index
      loop
        v_possible := v_possible + 1;
        -- 매번 같은 결과가 나오도록 해시로 정한다 (hashtext 는 음수도 나오므로 두 번 나눈다)
        v_ok := ((hashtext(r.id::text || d::text || s.user_id::text)::bigint % 100) + 100) % 100
                < v_rate;
        if v_ok then v_total := v_total + 1; end if;
        v_answers := v_answers || jsonb_build_object(r.id::text, v_ok);
      end loop;
      if v_possible = 0 then
        continue;   -- 규칙이 없으면 점검도 만들지 않는다
      end if;

      select coalesce(jsonb_object_agg(t.category, t.avg_pct), '{}'::jsonb) into v_cats
        from (
          select sr.category,
                 avg(case when v_answers ->> sr.id::text = 'true' then 100.0 else 0.0 end) as avg_pct
            from school_rules sr
           where sr.school_id = v_school and sr.is_active
             and v_answers ? sr.id::text
           group by sr.category
        ) t;

      v_ts := ((d::timestamp + time '15:40') at time zone 'Asia/Seoul');
      insert into daily_checkins
        (user_id, school_id, checkin_date, answers, total_score, total_possible,
         score_pct, category_scores, created_at, updated_at)
      values
        (s.user_id, v_school, d, v_answers, v_total, v_possible,
         (v_total::float / v_possible) * 100.0, v_cats, v_ts, v_ts);
      v_checkins := v_checkins + 1;

      -- 포인트 (실제와 같은 함수로 — 주간 개근 보너스도 붙는다)
      perform award_checkin_points_internal(s.user_id, v_school, d);
      update point_transactions
         set created_at = v_ts
       where user_id = s.user_id and school_id = v_school
         and period_key = to_char(d, 'YYYY-MM-DD') and reason = 'checkin_daily';
    end loop;

    -- 이 학생의 담임 선생님 (없으면 처음 가입한 선생님)
    select p.user_id, p.nickname into v_teacher, v_teacher_name
      from profiles p
     where p.school_id = v_school and p.role = 'teacher'
       and p.grade = s.grade and p.class_num = s.class_num
     order by p.created_at
     limit 1;
    if v_teacher is null and array_length(v_teachers, 1) is not null then
      v_teacher := v_teachers[1];
      select nickname into v_teacher_name from profiles where user_id = v_teacher;
    end if;

    -- 3-2. 선생님 칭찬 2개
    if v_teacher is not null then
      v_praise_pts := point_amount(v_school, 'praise');
      for r in
        select * from (values
          (8, '급식실에서 차례를 잘 지키고 친구에게 먼저 양보했어요.'),
          (2, '수업 준비를 꼼꼼히 해 와서 모둠 활동이 순조로웠어요.')
        ) as x(ago, msg)
      loop
        v_ts := (((v_today - r.ago)::timestamp + time '12:20') at time zone 'Asia/Seoul');
        insert into praise (school_id, teacher_id, student_id, message, created_at)
        values (v_school, v_teacher, s.user_id, r.msg, v_ts)
        returning id into v_praise_id;
        if v_praise_pts > 0 then
          insert into point_transactions
            (user_id, school_id, amount, reason, period_key, description, created_at)
          values
            (s.user_id, v_school, v_praise_pts, 'praise', v_praise_id::text, '교사 칭찬', v_ts);
        end if;
      end loop;
    end if;

    -- 3-3. 반의 '함께 키우기' (600P 모인 상태)
    if s.grade is not null and s.class_num is not null
       and not exists (select 1 from point_store_items i
                        where i.school_id = v_school and i.item_type = 'group'
                          and i.grade = s.grade and i.class_num = s.class_num) then
      insert into point_store_items
        (school_id, name, description, cost_points, stock, is_active, order_index,
         emoji, grade, class_num, created_by, created_by_name, item_type)
      values
        (v_school, '우리 반 간식 파티', '반 친구들이 포인트를 모아 다 함께!', 2000, null, true, 10,
         '🍕', s.grade, s.class_num, v_teacher, v_teacher_name, 'group')
      returning id into v_item_id;

      insert into group_contributions (item_id, user_id, school_id, amount)
      values (v_item_id, s.user_id, v_school, 600);
      insert into point_transactions
        (user_id, school_id, amount, reason, period_key, description)
      values
        (s.user_id, v_school, -600, 'group_contribute',
         v_item_id::text || ':' || gen_random_uuid()::text, '함께 키우기: 우리 반 간식 파티');
    end if;

    -- 3-4. (선택) 세 번째 학생의 K-ODR → CICO · 학맞통 연계
    --   기록이 저장되면 059 의 판정이 돌아 CICO 권장 알림과 학맞통 안건이 자동으로 생긴다.
    --   실패해도 초기화는 계속한다.
    if p_with_kodr and s.idx = 3 and v_teacher is not null then
      begin
        for r in
          select * from (values
            (18, '교실', '수업 준비물 미지참'),
            (12, '교실', '잡담·수업 무관한 말'),
            (8,  '복도', '수업시간 큰 소리로 말하기'),
            (5,  '교실', '디지털 기기 사용'),
            (2,  '교실', '과제 비참여')
          ) as x(ago, place, behavior)
        loop
          insert into kodr_records
            (school_id, student_id, teacher_id, occurred_date, place, behavior,
             author_role, created_at)
          values
            (v_school, s.user_id, v_teacher, v_today - r.ago, r.place, r.behavior,
             '담임교사',
             (((v_today - r.ago)::timestamp + time '11:00') at time zone 'Asia/Seoul'));
        end loop;
      exception when others then
        v_note := 'K-ODR 예시는 건너뛰었어요: ' || sqlerrm;
      end;
    end if;

    v_teacher := null;
    v_teacher_name := null;
  end loop;

  return json_build_object(
    'ok', true,
    'scope', v_scope,
    'class', case when v_scope = 'class' then v_my_grade || '-' || v_my_class end,
    'students', v_students,
    'teachers', coalesce(array_length(v_teachers, 1), 0),
    'checkins_seeded', v_checkins,
    'note', v_note);
end $$;
revoke all on function reset_demo_school(uuid, boolean, text) from public, anon;
grant execute on function reset_demo_school(uuid, boolean, text) to authenticated;

-- ═══════════ 확인 ═══════════
--   -- 모든 기록에 '학생' 이 붙었는지 (0 이어야 정상)
--   select count(*) from kodr_records where subject_id is null;
--   -- 가입하지 않은 학생의 기록
--   select student_name, student_grade, student_class, count(*)
--     from kodr_records where student_id is null group by 1, 2, 3;
