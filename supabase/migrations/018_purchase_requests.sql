-- 018_purchase_requests.sql
-- 학교 도입(구매) 신청 → 운영자 승인 → 학교코드 자동 발급 워크플로우.
--   1) 학교가 웹 신청 폼 제출 (익명 insert)
--   2) 운영자가 입금 확인 후 approve → 학교 생성(active) + 코드 발급
--   3) 발급된 코드/견적 정보로 환영 이메일 발송(Edge Function)

create table if not exists purchase_requests (
  id uuid primary key default gen_random_uuid(),
  school_name text not null,
  level text,                       -- 초등학교 | 중학교 | 고등학교
  region text,
  contact_name text not null,
  contact_email text not null,
  contact_phone text,
  student_count int,
  plan text,                        -- 요금제(예: 100명 미만)
  message text,                     -- 문의사항
  status text not null default 'pending',  -- pending | paid | approved | rejected
  school_code text,                 -- 승인 시 발급된 학생 코드
  teacher_code text,                -- 승인 시 발급된 교사 코드
  school_id uuid references schools(id) on delete set null,
  created_at timestamptz not null default now(),
  approved_at timestamptz
);

create index if not exists pr_status_idx on purchase_requests(status, created_at desc);

alter table purchase_requests enable row level security;

-- 익명(웹 폼)도 신청 제출 가능
drop policy if exists pr_insert on purchase_requests;
create policy pr_insert on purchase_requests
  for insert to anon, authenticated with check (true);

-- 조회/수정은 운영자만 (아래 RPC로만 접근). 직접 select는 막고 RPC 사용.
drop policy if exists pr_admin_select on purchase_requests;
create policy pr_admin_select on purchase_requests
  for select to authenticated
  using (auth.jwt() ->> 'email' = 'toyswar987@naver.com');

-- ── 코드 생성 헬퍼 (혼동 문자 제외) ──────────────────────────
create or replace function gen_unique_school_code()
returns text language plpgsql as $$
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

create or replace function gen_teacher_code()
returns text language plpgsql as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text;
begin
  code := '';
  for i in 1..8 loop
    code := code || substr(chars, floor(random() * length(chars))::int + 1, 1);
  end loop;
  return code;
end $$;

-- ── 신청 제출 (익명 호출 가능) ───────────────────────────────
create or replace function submit_purchase_request(
  p_school_name text,
  p_level text,
  p_region text,
  p_contact_name text,
  p_contact_email text,
  p_contact_phone text,
  p_student_count int,
  p_plan text,
  p_message text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if coalesce(trim(p_school_name), '') = '' or coalesce(trim(p_contact_email), '') = '' then
    raise exception '학교명과 담당자 이메일은 필수입니다.';
  end if;
  insert into purchase_requests(
    school_name, level, region, contact_name, contact_email,
    contact_phone, student_count, plan, message
  ) values (
    trim(p_school_name), p_level, p_region, trim(p_contact_name), trim(p_contact_email),
    p_contact_phone, p_student_count, p_plan, p_message
  ) returning id into new_id;
  return new_id;
end $$;

grant execute on function submit_purchase_request(
  text, text, text, text, text, text, int, text, text
) to anon, authenticated;

-- ── 신청 목록 조회 (운영자 전용) ─────────────────────────────
create or replace function list_purchase_requests()
returns setof purchase_requests
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.jwt() ->> 'email' <> 'toyswar987@naver.com' then
    raise exception '운영자만 조회할 수 있습니다.';
  end if;
  return query select * from purchase_requests order by
    case status when 'pending' then 0 when 'paid' then 1 else 2 end,
    created_at desc;
end $$;

grant execute on function list_purchase_requests() to authenticated;

-- ── 상태 변경: 입금확인(paid) / 반려(rejected) ──────────────
create or replace function set_purchase_status(p_request_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.jwt() ->> 'email' <> 'toyswar987@naver.com' then
    raise exception '운영자만 변경할 수 있습니다.';
  end if;
  if p_status not in ('pending', 'paid', 'rejected') then
    raise exception '허용되지 않은 상태입니다.';
  end if;
  update purchase_requests set status = p_status where id = p_request_id;
end $$;

grant execute on function set_purchase_status(uuid, text) to authenticated;

-- ── 승인: 학교 생성(active) + 코드 발급 ─────────────────────
create or replace function approve_purchase_request(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  req purchase_requests;
  new_school_id uuid;
  s_code text;
  t_code text;
  lvl text;
begin
  if auth.jwt() ->> 'email' <> 'toyswar987@naver.com' then
    raise exception '운영자만 승인할 수 있습니다.';
  end if;

  select * into req from purchase_requests where id = p_request_id;
  if req.id is null then raise exception '신청을 찾을 수 없습니다.'; end if;
  if req.status = 'approved' then
    -- 이미 승인됨 → 기존 코드 반환
    return jsonb_build_object('school_code', req.school_code,
      'teacher_code', req.teacher_code, 'school_id', req.school_id,
      'already', true);
  end if;

  s_code := gen_unique_school_code();
  t_code := gen_teacher_code();
  lvl := case when req.level in ('초등학교', '중학교', '고등학교')
              then req.level else '중학교' end;

  insert into schools(name, region, level, school_code, teacher_code,
                      subscription_status, subscription_expires_at)
  values (req.school_name, coalesce(req.region, '-'), lvl, s_code, t_code,
          'active', (now() + interval '1 year')::date)
  returning id into new_school_id;

  update purchase_requests
  set status = 'approved', school_code = s_code, teacher_code = t_code,
      school_id = new_school_id, approved_at = now()
  where id = p_request_id;

  return jsonb_build_object('school_code', s_code, 'teacher_code', t_code,
    'school_id', new_school_id, 'already', false);
end $$;

grant execute on function approve_purchase_request(uuid) to authenticated;
