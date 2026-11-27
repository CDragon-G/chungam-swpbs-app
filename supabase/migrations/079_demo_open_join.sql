-- 079_demo_open_join.sql
-- 강의 · 연수용 '체험 입장' — 체험 코드만 넣으면 PIN · 이메일 없이 학생으로 들어온다.
--
-- 왜
--   2026-12-07 대구 강의(참여자 350~400명). 지금 체험 학교는 명단 자리마다 PIN 을 나눠 줘야 하는데
--   400명에게 미리 PIN 을 나눠 주기 어렵다. 참여자가 QR 로 앱을 받고, 체험 코드 하나만 넣으면
--   '대구체험학생1', '대구체험학생2' … 처럼 번호가 자동으로 매겨져 바로 체험하게 한다.
--
-- 어떻게
--   · 로그인은 Supabase 익명 로그인(이메일 · 비밀번호 없음). 대시보드에서 켜야 한다.
--   · join_demo_school(code) — 열어 둔 체험 학교(is_demo + demo_join_open)에만 들어간다.
--       번호를 차례로 매기고, 반은 demo_join_class_size 명씩 나눈다 (칭찬 우체통이 같은 반끼리라서).
--       명단 자리와 학생 프로필을 함께 만든다.
--   · set_demo_join(school, open, …) — 열고 닫기 · 이름 앞말 · 학년 · 반 인원 · 최대 인원. SQL 에디터 전용.
--
-- 안전장치
--   · 실제 학교에는 들어갈 수 없다. is_demo 이고 선생님이 연 학교만, 최대 인원까지만.
--   · 익명 계정은 프로필을 직접 만들거나 학교 · 역할 · 반 · 이름을 바꿀 수 없다 (체험 입장 함수로만).
--     익명 로그인은 누구나 버튼 하나로 계정을 만들 수 있어서, 앱을 거치지 않은 요청을 막아 둔다.
--   · 익명 계정은 학교를 새로 만들 수 없다.
--   · 체험 학생 이름(…체험학생N)은 가려도 의미가 없어 구름 · 명예의 전당에 그대로 보인다.

-- ═══════════ 1) 체험 입장 설정 ═══════════
alter table schools add column if not exists demo_join_open boolean not null default false;
alter table schools add column if not exists demo_join_prefix text not null default '체험학생';
alter table schools add column if not exists demo_join_grade int not null default 2;
alter table schools add column if not exists demo_join_class_size int not null default 30;
alter table schools add column if not exists demo_join_max int not null default 600;
alter table schools add column if not exists demo_join_seq int not null default 0;   -- 마지막으로 매긴 번호

-- ═══════════ 2) 익명 계정 막기 ═══════════
create or replace function is_anonymous_user()
returns boolean
language sql stable set search_path = public, auth as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
$$;

create or replace function trg_profiles_anon_guard()
returns trigger
language plpgsql set search_path = public, auth as $$
begin
  if not is_anonymous_user()
     or current_setting('jaram.demo_join', true) = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    raise exception '체험 계정은 체험 코드로만 들어올 수 있어요';
  end if;
  if new.role is distinct from old.role
     or new.school_id is distinct from old.school_id
     or new.teacher_role is distinct from old.teacher_role
     or new.grade is distinct from old.grade
     or new.class_num is distinct from old.class_num
     or new.student_num is distinct from old.student_num
     or new.nickname is distinct from old.nickname then
    raise exception '체험 계정은 학교 · 반 · 이름을 바꿀 수 없어요';
  end if;
  return new;
end $$;

drop trigger if exists profiles_anon_guard on profiles;
create trigger profiles_anon_guard before insert or update on profiles
  for each row execute function trg_profiles_anon_guard();

create or replace function trg_schools_anon_guard()
returns trigger
language plpgsql set search_path = public, auth as $$
begin
  if is_anonymous_user() then
    raise exception '체험 계정은 학교를 만들 수 없어요';
  end if;
  return new;
end $$;

drop trigger if exists schools_anon_guard on schools;
create trigger schools_anon_guard before insert on schools
  for each row execute function trg_schools_anon_guard();

-- ═══════════ 3) 이름 가리기 — 체험 학생 번호는 그대로 ═══════════
--   본문은 056 과 같고 맨 앞에 '…체험학생N' 만 더했다. (대구체험학생12 → 대*****2 가 되면 번호를 알 수 없다)
create or replace function mask_name(p_name text)
returns text
language sql immutable set search_path = public as $$
  select case
    when p_name is null or btrim(p_name) = '' then ''
    when btrim(p_name) ~ '체험학생[0-9]+$' then btrim(p_name)
    when char_length(btrim(p_name)) = 1 then btrim(p_name)
    when char_length(btrim(p_name)) = 2 then left(btrim(p_name), 1) || '*'
    else left(btrim(p_name), 1)
         || repeat('*', char_length(btrim(p_name)) - 2)
         || right(btrim(p_name), 1)
  end;
$$;

-- ═══════════ 4) 체험 입장 ═══════════
create or replace function join_demo_school(p_code text)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_uid uuid := auth.uid();
  v_s schools;
  v_n int;
  v_class int;
  v_num int;
  v_name text;
  v_tries int := 0;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', '로그인이 필요해요');
  end if;
  if exists (select 1 from profiles where user_id = v_uid) then
    return json_build_object('ok', false, 'error', '이미 들어와 있어요. 앱을 다시 열어 주세요');
  end if;

  -- 같은 학교에 동시에 들어와도 번호가 겹치지 않게 학교 줄을 잠근다
  select * into v_s from schools
   where school_code = upper(btrim(coalesce(p_code, '')))
   for update;
  -- 실제 학교인지 · 닫힌 체험인지 알려 주지 않는다 (코드 맞혀 보기 방지)
  if v_s.id is null or not v_s.is_demo or not v_s.demo_join_open then
    return json_build_object('ok', false, 'error', '체험 코드를 다시 확인해 주세요');
  end if;
  if v_s.demo_join_seq >= v_s.demo_join_max then
    return json_build_object('ok', false, 'error', '체험 인원이 모두 찼어요. 강사님께 알려 주세요');
  end if;

  -- 다음 빈자리 (이미 명단에 있는 자리는 건너뛴다)
  v_n := v_s.demo_join_seq;
  loop
    v_n := v_n + 1;
    v_tries := v_tries + 1;
    v_class := (v_n - 1) / v_s.demo_join_class_size + 1;
    v_num := (v_n - 1) % v_s.demo_join_class_size + 1;
    exit when not exists (
      select 1 from student_roster
       where school_id = v_s.id and grade = v_s.demo_join_grade
         and class_num = v_class and student_num = v_num)
     and not exists (
      select 1 from profiles
       where school_id = v_s.id and role = 'student' and grade = v_s.demo_join_grade
         and class_num = v_class and student_num = v_num);
    if v_tries > 1000 or v_class > 30 then
      return json_build_object('ok', false, 'error', '빈자리를 찾지 못했어요. 강사님께 알려 주세요');
    end if;
  end loop;
  v_name := v_s.demo_join_prefix || v_n;

  update schools set demo_join_seq = v_n where id = v_s.id;

  insert into student_roster
    (school_id, grade, class_num, student_num, name, pin, claimed, claimed_by)
  values
    (v_s.id, v_s.demo_join_grade, v_class, v_num, v_name,
     lpad((floor(random() * 10000))::int::text, 4, '0'), true, v_uid);

  perform set_config('jaram.demo_join', 'on', true);
  insert into profiles (user_id, role, nickname, school_id, grade, class_num, student_num)
  values (v_uid, 'student', v_name, v_s.id, v_s.demo_join_grade, v_class, v_num);
  perform set_config('jaram.demo_join', 'off', true);

  return json_build_object(
    'ok', true,
    'name', v_name,
    'school', v_s.name,
    'grade', v_s.demo_join_grade,
    'class_num', v_class,
    'student_num', v_num);
end $$;
revoke all on function join_demo_school(text) from public, anon;
grant execute on function join_demo_school(text) to authenticated;

-- ═══════════ 5) 열고 닫기 (SQL 에디터 전용) ═══════════
--   select set_demo_join('<학교 id>', true, '대구체험학생');   -- 열기
--   select set_demo_join('<학교 id>', false);                   -- 닫기 (이미 들어온 사람은 그대로)
create or replace function set_demo_join(
  p_school uuid,
  p_open boolean,
  p_prefix text default null,
  p_grade int default null,
  p_class_size int default null,
  p_max int default null
)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_s schools;
begin
  select * into v_s from schools where id = p_school;
  if v_s.id is null then
    return json_build_object('ok', false, 'error', '학교를 찾을 수 없어요');
  end if;
  if not v_s.is_demo then
    return json_build_object('ok', false, 'error', '체험 학교(is_demo)에서만 열 수 있어요');
  end if;
  if p_grade is not null and (p_grade < 1 or p_grade > 6) then
    return json_build_object('ok', false, 'error', '학년은 1~6');
  end if;
  if p_class_size is not null and (p_class_size < 5 or p_class_size > 40) then
    return json_build_object('ok', false, 'error', '반 인원은 5~40명');
  end if;

  update schools
     set demo_join_open = p_open,
         demo_join_prefix = coalesce(nullif(btrim(p_prefix), ''), demo_join_prefix),
         demo_join_grade = coalesce(p_grade, demo_join_grade),
         demo_join_class_size = coalesce(p_class_size, demo_join_class_size),
         demo_join_max = coalesce(p_max, demo_join_max)
   where id = p_school
   returning * into v_s;

  return json_build_object(
    'ok', true,
    'school', v_s.name,
    'code', v_s.school_code,
    'open', v_s.demo_join_open,
    'prefix', v_s.demo_join_prefix,
    'grade', v_s.demo_join_grade,
    'class_size', v_s.demo_join_class_size,
    'max', v_s.demo_join_max,
    'joined', v_s.demo_join_seq);
end $$;
revoke all on function set_demo_join(uuid, boolean, text, int, int, int) from public, anon, authenticated;

-- ═══════════ 확인 ═══════════
--   select name, school_code, demo_join_open, demo_join_prefix, demo_join_seq from schools where is_demo;
