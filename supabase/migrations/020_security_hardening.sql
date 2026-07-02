-- 020_security_hardening.sql
-- 보안 감사 후속 강화.
--   verify_roster_pin: 학번 열거(enumeration) 방지.
--     기존에는 "없는 학번 / 이미 가입됨 / PIN 불일치"를 서로 다른 메시지로 반환해
--     PIN을 몰라도 학번의 존재·가입 여부를 알아낼 수 있었다.
--     → 존재 여부와 PIN 오류를 동일 메시지로 통합하고,
--       claimed(가입됨) 상태는 PIN이 확인된 뒤에만 안내한다.

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

  -- 존재 여부와 PIN 오류를 동일 메시지로 → 학번 열거 차단
  if rec.id is null or rec.pin <> p_pin then
    raise exception '학번 또는 PIN이 일치하지 않아요. 담임선생님께 받은 정보를 확인하세요.';
  end if;

  -- PIN이 확인된 뒤에만 가입 여부 안내 (PIN 없이 상태를 알 수 없게)
  if rec.claimed then
    raise exception '이미 가입에 사용된 학번이에요. 비밀번호를 잊으셨다면 선생님께 초기화를 요청하세요.';
  end if;

  return rec.name;
end;
$$;

revoke all on function public.verify_roster_pin(uuid, int, int, int, text) from public;
grant execute on function public.verify_roster_pin(uuid, int, int, int, text) to anon, authenticated;
