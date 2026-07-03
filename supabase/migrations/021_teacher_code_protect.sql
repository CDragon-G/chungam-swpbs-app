-- 021_teacher_code_protect.sql
-- 보안 감사 후속: teacher_code 노출 차단.
--   문제: schools SELECT 정책이 using(true)라 비로그인(anon)도 전체 학교를 덤프해
--         teacher_code를 캐낼 수 있었다 → 학생이 교사로 가입 가능(008이 막으려던 위협).
--   해결:
--     1) schools 직접 SELECT를 '같은 학교의 로그인 사용자' 또는 '생성자'로 제한.
--     2) 가입용 코드→학교 조회는 SECURITY DEFINER RPC로만 (안전 컬럼만 반환).
--        - 학생용 RPC는 teacher_code를 숨긴다.

-- ── 1) schools SELECT 정책 강화 ──────────────────────────────
drop policy if exists schools_select on schools;
create policy schools_select on schools
  for select to authenticated
  using (
    id = current_profile_school()   -- 내 소속 학교
    or created_by = auth.uid()       -- 내가 만든 학교 (가입 직후 조회용)
  );

-- ── 2) 가입용 코드 조회 RPC (anon 허용, 안전 컬럼만) ─────────
-- 학생 가입: school_code로 조회. teacher_code는 반환하지 않는다(null).
create or replace function public.find_school_by_student_code(p_code text)
returns table (
  id uuid, name text, region text, level text,
  school_code text, teacher_code text, created_by uuid,
  subscription_status text, subscription_expires_at date, created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select s.id, s.name, s.region, s.level,
         s.school_code, null::text, null::uuid,
         s.subscription_status, s.subscription_expires_at, s.created_at
  from schools s
  where s.school_code = p_code
  limit 1;
$$;
revoke all on function public.find_school_by_student_code(text) from public;
grant execute on function public.find_school_by_student_code(text) to anon, authenticated;

-- 교사 가입: teacher_code로 조회. (호출자는 이미 그 코드를 알고 있음)
create or replace function public.find_school_by_teacher_code(p_code text)
returns table (
  id uuid, name text, region text, level text,
  school_code text, teacher_code text, created_by uuid,
  subscription_status text, subscription_expires_at date, created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select s.id, s.name, s.region, s.level,
         s.school_code, s.teacher_code, null::uuid,
         s.subscription_status, s.subscription_expires_at, s.created_at
  from schools s
  where s.teacher_code = p_code
  limit 1;
$$;
revoke all on function public.find_school_by_teacher_code(text) from public;
grant execute on function public.find_school_by_teacher_code(text) to anon, authenticated;

-- ── 3) 학교 중복 확인 RPC (신규 학교 등록 시, 교사 전용) ──────
-- 같은 (이름·지역·급) 학교가 이미 있으면 그 school_code를 반환.
create or replace function public.check_duplicate_school(
  p_name text, p_region text, p_level text
)
returns text
language sql
security definer
set search_path = public
as $$
  select school_code from schools
  where name = p_name and region = p_region and level = p_level
  limit 1;
$$;
revoke all on function public.check_duplicate_school(text, text, text) from public;
grant execute on function public.check_duplicate_school(text, text, text) to authenticated;

-- ── 4) 유일 학교코드 생성 RPC를 SECURITY DEFINER로 ───────────
-- schools SELECT를 조였으므로, 코드 유일성 검사는 정의자 권한으로 전체를 봐야 한다.
create or replace function public.gen_unique_school_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text; ok boolean;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(chars, floor(random() * length(chars))::int + 1, 1);
    end loop;
    select not exists(select 1 from schools where school_code = code) into ok;
    exit when ok;
  end loop;
  return code;
end $$;
revoke all on function public.gen_unique_school_code() from public;
grant execute on function public.gen_unique_school_code() to authenticated;
