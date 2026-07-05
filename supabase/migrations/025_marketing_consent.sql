-- 025_marketing_consent.sql
-- 마케팅(광고성) 이메일 수신동의 관리. 정보통신망법 제50조 대응:
--   · 사전 opt-in 동의 + 동의 일시 기록
--   · 모든 광고성 메일에 수신거부(unsubscribe) 링크 → 토큰 기반 즉시 해지
--   · 거래성 메일(환영/갱신/신청알림/리포트)은 이 동의와 무관하게 발송한다.
--   이메일 기준으로 관리(교사 계정 + 도입신청 담당자 모두 커버).

create table if not exists marketing_consent (
  email text primary key,
  opted_in boolean not null default false,
  opted_in_at timestamptz,
  opted_out_at timestamptz,
  unsubscribe_token uuid not null default gen_random_uuid(),
  source text,                         -- app | apply_form
  updated_at timestamptz not null default now()
);
create index if not exists marketing_consent_token_idx on marketing_consent(unsubscribe_token);

alter table marketing_consent enable row level security;
-- 직접 조회는 운영자만. 나머지는 정의자 권한 RPC로만 접근.
drop policy if exists mc_operator_select on marketing_consent;
create policy mc_operator_select on marketing_consent
  for select to authenticated
  using (auth.jwt() ->> 'email' = 'toyswar987@naver.com');

-- ── 로그인 사용자(교사) 본인 동의 on/off ────────────────────
create or replace function public.set_marketing_consent(p_opt_in boolean)
returns void
language plpgsql security definer set search_path = public, auth
as $$
declare v_email text;
begin
  v_email := auth.jwt() ->> 'email';
  if coalesce(v_email, '') = '' then raise exception '로그인이 필요해요.'; end if;
  insert into marketing_consent(email, opted_in, opted_in_at, opted_out_at, source, updated_at)
  values (v_email, p_opt_in,
          case when p_opt_in then now() end,
          case when not p_opt_in then now() end,
          'app', now())
  on conflict (email) do update set
    opted_in = excluded.opted_in,
    opted_in_at = case when excluded.opted_in
                       then coalesce(marketing_consent.opted_in_at, now())
                       else marketing_consent.opted_in_at end,
    opted_out_at = case when not excluded.opted_in then now()
                        else marketing_consent.opted_out_at end,
    updated_at = now();
end $$;
revoke all on function public.set_marketing_consent(boolean) from public;
grant execute on function public.set_marketing_consent(boolean) to authenticated;

-- ── 본인 현재 동의 상태 ──────────────────────────────────────
create or replace function public.get_my_marketing_consent()
returns boolean
language sql security definer set search_path = public, auth
as $$
  select coalesce(
    (select opted_in from marketing_consent where email = auth.jwt() ->> 'email'),
    false);
$$;
revoke all on function public.get_my_marketing_consent() from public;
grant execute on function public.get_my_marketing_consent() to authenticated;

-- ── 토큰 기반 수신거부 (수신거부 링크에서 anon 호출) ─────────
create or replace function public.unsubscribe_marketing(p_token uuid)
returns text
language plpgsql security definer set search_path = public
as $$
declare v_email text;
begin
  update marketing_consent
    set opted_in = false, opted_out_at = now(), updated_at = now()
    where unsubscribe_token = p_token
    returning email into v_email;
  if v_email is null then raise exception '유효하지 않은 링크예요.'; end if;
  return v_email;
end $$;
revoke all on function public.unsubscribe_marketing(uuid) from public;
grant execute on function public.unsubscribe_marketing(uuid) to anon, authenticated;

-- ── 발송 대상(동의자) 조회: 운영자/서비스 (향후 뉴스레터용) ──
create or replace function public.marketing_recipients()
returns table (email text, unsubscribe_token uuid)
language plpgsql security definer set search_path = public, auth
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and coalesce(auth.jwt() ->> 'email', '') <> 'toyswar987@naver.com' then
    raise exception '권한이 없어요.';
  end if;
  return query
    select mc.email, mc.unsubscribe_token
    from marketing_consent mc where mc.opted_in = true;
end $$;
revoke all on function public.marketing_recipients() from public;
grant execute on function public.marketing_recipients() to authenticated, service_role;

-- ── 도입신청 폼에서 동의 함께 기록 (submit_purchase_request 확장) ──
-- 기존 9인자 버전을 대체하고 p_marketing_opt_in(선택) 추가.
drop function if exists public.submit_purchase_request(
  text, text, text, text, text, text, int, text, text);

create or replace function public.submit_purchase_request(
  p_school_name text,
  p_level text,
  p_region text,
  p_contact_name text,
  p_contact_email text,
  p_contact_phone text,
  p_student_count int,
  p_plan text,
  p_message text,
  p_marketing_opt_in boolean default false
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  new_id uuid;
  v_email text := trim(p_contact_email);
begin
  if coalesce(trim(p_school_name), '') = '' or coalesce(v_email, '') = '' then
    raise exception '학교명과 담당자 이메일은 필수입니다.';
  end if;
  insert into purchase_requests(
    school_name, level, region, contact_name, contact_email,
    contact_phone, student_count, plan, message
  ) values (
    trim(p_school_name), p_level, p_region, trim(p_contact_name), v_email,
    p_contact_phone, p_student_count, p_plan, p_message
  ) returning id into new_id;

  -- 마케팅 수신동의(선택) 기록
  if p_marketing_opt_in and coalesce(v_email, '') <> '' then
    insert into marketing_consent(email, opted_in, opted_in_at, source, updated_at)
    values (v_email, true, now(), 'apply_form', now())
    on conflict (email) do update set
      opted_in = true,
      opted_in_at = coalesce(marketing_consent.opted_in_at, now()),
      updated_at = now();
  end if;

  return new_id;
end $$;
grant execute on function public.submit_purchase_request(
  text, text, text, text, text, text, int, text, text, boolean
) to anon, authenticated;
