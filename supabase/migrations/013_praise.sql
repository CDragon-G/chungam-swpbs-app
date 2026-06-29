-- 013_praise.sql
-- 교사 즉석 칭찬 기능.
-- 교사가 학생을 칭찬하면: 칭찬 기록 + 학생 +50P + 누적 횟수별 배지 자동 부여.
-- (푸시 발송은 별도 Edge Function에서 device_tokens를 사용)

-- 1) 칭찬 테이블
create table if not exists praise (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  teacher_id uuid not null references auth.users(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists praise_student_idx on praise (student_id, created_at desc);
create index if not exists praise_teacher_idx on praise (teacher_id, created_at desc);

alter table praise enable row level security;

-- 학생: 본인이 받은 칭찬 조회/읽음표시
drop policy if exists praise_student_read on praise;
create policy praise_student_read on praise
  for select using (student_id = auth.uid());
drop policy if exists praise_student_update on praise;
create policy praise_student_update on praise
  for update using (student_id = auth.uid()) with check (student_id = auth.uid());

-- 교사: 본인이 준 칭찬 조회
drop policy if exists praise_teacher_read on praise;
create policy praise_teacher_read on praise
  for select using (teacher_id = auth.uid());

-- 2) 칭찬 단계별 배지 (1/3/5/10/20회)
insert into badges (name, description, icon_emoji, condition_type, condition_value)
select * from (values
  ('첫 칭찬',   '선생님께 처음 칭찬받았어요',  '🌱', 'praise_count', 1),
  ('자라는 중', '칭찬 3회 달성',              '🌿', 'praise_count', 3),
  ('활짝 폈어요','칭찬 5회 달성',             '🌻', 'praise_count', 5),
  ('우뚝 섰어요','칭찬 10회 달성',            '🌳', 'praise_count', 10),
  ('칭찬 스타', '칭찬 20회 달성',             '⭐', 'praise_count', 20)
) as v(name, description, icon_emoji, condition_type, condition_value)
where not exists (
  select 1 from badges b
  where b.condition_type = 'praise_count' and b.condition_value = v.condition_value
);

-- 3) 칭찬 부여 RPC (교사 전용)
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

  -- +50P (칭찬마다 고유 period_key = praise id → 중복 없이 매번 적립)
  insert into point_transactions (user_id, school_id, amount, reason, period_key, description)
  values (p_student_user_id, caller_school, 50, 'praise', v_praise_id::text, '교사 칭찬');

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

-- 4) 안 읽은 칭찬 조회 + 읽음 처리 (학생용)
create or replace function public.mark_praise_read()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  update praise set is_read = true
  where student_id = auth.uid() and is_read = false;
end;
$$;
grant execute on function public.mark_praise_read() to authenticated;
