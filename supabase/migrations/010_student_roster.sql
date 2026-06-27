-- 010_student_roster.sql
-- 명단 기반 학생 신원 확인 시스템
-- 교사가 전교생 명단(학년/반/번호/이름)을 일괄 등록하면 각 학생에게 4자리 PIN이 발급된다.
-- 학생은 학교코드 + 학년/반/번호 + 이름확인 + PIN으로만 가입할 수 있어 사칭·중복을 막는다.
-- 기존 가입자는 영향받지 않으며, 신규 가입에만 적용한다.

-- 1) 명단 테이블
create table if not exists student_roster (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  grade int not null,
  class_num int not null,
  student_num int not null,
  name text not null,
  pin text not null,
  claimed boolean not null default false,        -- 이미 가입에 사용됐는지
  claimed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (school_id, grade, class_num, student_num)
);

create index if not exists student_roster_school_idx
  on student_roster (school_id, grade, class_num, student_num);

alter table student_roster enable row level security;

-- 같은 학교 교사만 명단 조회 가능 (PIN 포함)
drop policy if exists roster_teacher_select on student_roster;
create policy roster_teacher_select on student_roster
  for select using (
    exists (
      select 1 from profiles p
      where p.user_id = auth.uid()
        and p.role = 'teacher'
        and p.school_id = student_roster.school_id
    )
  );

-- 2) 명단 일괄 업로드 RPC (교사 전용)
-- p_rows: [{"grade":1,"class_num":1,"student_num":1,"name":"홍길동"}, ...]
-- 이미 있는 학번은 이름만 갱신(미가입 시), 새 학번은 PIN과 함께 추가.
create or replace function public.upload_roster(
  p_school_id uuid,
  p_rows jsonb
)
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  caller_role text;
  caller_school uuid;
  r jsonb;
  cnt int := 0;
  new_pin text;
begin
  select role, school_id into caller_role, caller_school
  from profiles where user_id = auth.uid();

  if caller_role is null then raise exception '로그인 상태가 아닙니다.'; end if;
  if caller_role <> 'teacher' then raise exception '교사만 명단을 등록할 수 있어요.'; end if;
  if caller_school is distinct from p_school_id then
    raise exception '본인 학교 명단만 등록할 수 있어요.';
  end if;

  for r in select * from jsonb_array_elements(p_rows)
  loop
    new_pin := lpad((floor(random() * 10000))::int::text, 4, '0');
    insert into student_roster (school_id, grade, class_num, student_num, name, pin)
    values (
      p_school_id,
      (r->>'grade')::int,
      (r->>'class_num')::int,
      (r->>'student_num')::int,
      r->>'name',
      new_pin
    )
    on conflict (school_id, grade, class_num, student_num)
    do update set name = excluded.name
      where student_roster.claimed = false;  -- 이미 가입한 학번은 건드리지 않음
    cnt := cnt + 1;
  end loop;

  return cnt;
end;
$$;

revoke all on function public.upload_roster(uuid, jsonb) from public;
grant execute on function public.upload_roster(uuid, jsonb) to authenticated;

-- 3) 가입 전 명단·PIN 검증 RPC (가입 전이라 anon도 호출 가능)
-- 일치하면 학생 이름을 반환, 불일치/중복이면 예외.
create or replace function public.verify_roster_pin(
  p_school_id uuid,
  p_grade int,
  p_class_num int,
  p_student_num int,
  p_pin text
)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  rec record;
begin
  select * into rec from student_roster
  where school_id = p_school_id
    and grade = p_grade
    and class_num = p_class_num
    and student_num = p_student_num;

  if rec.id is null then
    raise exception '명단에 없는 학번이에요. 담임선생님께 문의하세요.';
  end if;
  if rec.claimed then
    raise exception '이미 가입에 사용된 학번이에요. 비밀번호를 잊으셨다면 선생님께 초기화를 요청하세요.';
  end if;
  if rec.pin <> p_pin then
    raise exception 'PIN이 일치하지 않아요. 담임선생님께 받은 PIN을 확인하세요.';
  end if;

  return rec.name;
end;
$$;

revoke all on function public.verify_roster_pin(uuid, int, int, int, text) from public;
grant execute on function public.verify_roster_pin(uuid, int, int, int, text) to anon, authenticated;

-- 4) 가입 완료 후 명단 잠금 RPC (로그인 상태에서 호출)
-- 해당 학번을 claimed 처리하여 재가입을 막는다.
create or replace function public.claim_roster(
  p_school_id uuid,
  p_grade int,
  p_class_num int,
  p_student_num int,
  p_pin text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  rec record;
begin
  if auth.uid() is null then raise exception '로그인 상태가 아닙니다.'; end if;

  select * into rec from student_roster
  where school_id = p_school_id
    and grade = p_grade
    and class_num = p_class_num
    and student_num = p_student_num
  for update;

  if rec.id is null then raise exception '명단에 없는 학번이에요.'; end if;
  if rec.claimed then raise exception '이미 가입에 사용된 학번이에요.'; end if;
  if rec.pin <> p_pin then raise exception 'PIN이 일치하지 않아요.'; end if;

  update student_roster
  set claimed = true, claimed_by = auth.uid()
  where id = rec.id;
end;
$$;

revoke all on function public.claim_roster(uuid, int, int, int, text) from public;
grant execute on function public.claim_roster(uuid, int, int, int, text) to authenticated;
