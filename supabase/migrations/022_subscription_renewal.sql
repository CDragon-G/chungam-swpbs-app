-- 022_subscription_renewal.sql
-- 구독 자동 갱신 라이프사이클 (계좌이체 기반).
--   설계:
--     · auto_renew 기본 true (해지는 능동적 행동 = opt-out)
--     · 만료 임박 시 D-30/D-7/D-1 안내 (성과 리포트 + 견적)
--     · 만료 후 grace_until 까지 서비스 유지(끊지 않음) — status는 active 유지,
--       유예 여부는 grace_until 컬럼으로만 표시 → 앱 로직/재빌드 불필요.
--     · 유예 종료 + 미갱신 시 status='expired'.
--   이번 증분은 스키마 + 갱신/자동갱신 RPC + 성과 리포트 집계 RPC.
--   (실제 이메일 발송·스캔은 Edge Function + pg_cron 증분에서.)

-- ── 1) schools 컬럼 확장 ─────────────────────────────────────
alter table schools add column if not exists auto_renew boolean not null default true;
alter table schools add column if not exists grace_until date;        -- 만료 후 유예 종료일
alter table schools add column if not exists renewed_count int not null default 0;
alter table schools add column if not exists last_renewal_stage text; -- d30|d7|d1|grace|churn (중복 발송 방지)

-- ── 2) 갱신 이벤트 로그 ──────────────────────────────────────
create table if not exists renewal_events (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  event_type text not null,  -- reminder_d30|reminder_d7|reminder_d1|grace_started|renewed|churned|winback_sent|auto_renew_changed
  detail text,
  created_at timestamptz not null default now()
);
create index if not exists renewal_events_school_idx
  on renewal_events(school_id, created_at desc);

alter table renewal_events enable row level security;
drop policy if exists renewal_events_operator on renewal_events;
create policy renewal_events_operator on renewal_events
  for select to authenticated
  using (auth.jwt() ->> 'email' = 'toyswar987@naver.com');

-- ── 3) 구독 갱신 (운영자, 계좌이체 확인 후 호출) ─────────────
create or replace function public.renew_subscription(
  p_school_id uuid, p_months int default 12
)
returns date
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_new date;
  v_base date;
begin
  if auth.jwt() ->> 'email' <> 'toyswar987@naver.com' then
    raise exception '운영자만 갱신 처리할 수 있어요.';
  end if;
  if coalesce(p_months, 0) <= 0 then
    raise exception '갱신 개월수가 올바르지 않아요.';
  end if;

  -- 만료 전이면 기존 만료일부터 연장, 만료 후면 오늘부터
  select greatest(coalesce(subscription_expires_at, current_date), current_date)
  into v_base from schools where id = p_school_id;
  if v_base is null then raise exception '학교를 찾을 수 없어요.'; end if;

  v_new := (v_base + (p_months || ' months')::interval)::date;

  update schools set
    subscription_status = 'active',
    subscription_expires_at = v_new,
    grace_until = null,
    last_renewal_stage = null,
    renewed_count = renewed_count + 1
  where id = p_school_id;

  insert into renewal_events(school_id, event_type, detail)
  values (p_school_id, 'renewed', p_months || '개월 갱신 → ' || v_new);

  return v_new;
end $$;
revoke all on function public.renew_subscription(uuid, int) from public;
grant execute on function public.renew_subscription(uuid, int) to authenticated;

-- ── 4) 자동 갱신 on/off (운영자) ────────────────────────────
create or replace function public.set_auto_renew(p_school_id uuid, p_on boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.jwt() ->> 'email' <> 'toyswar987@naver.com' then
    raise exception '운영자만 변경할 수 있어요.';
  end if;
  update schools set auto_renew = p_on where id = p_school_id;
  insert into renewal_events(school_id, event_type, detail)
  values (p_school_id, 'auto_renew_changed', case when p_on then '자동갱신 ON' else '자동갱신 OFF' end);
end $$;
revoke all on function public.set_auto_renew(uuid, boolean) from public;
grant execute on function public.set_auto_renew(uuid, boolean) to authenticated;

-- ── 5) 학교 연간 성과 리포트 (갱신 설득 핵심) ────────────────
-- 같은 학교 교사 또는 운영자만. 기간 미지정 시 최근 1년.
create or replace function public.school_annual_report(
  p_school_id uuid,
  p_from date default null,
  p_to date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  d_to date := coalesce(p_to, current_date);
  d_from date := coalesce(p_from, (current_date - interval '1 year')::date);
  v_students int;
  v_active int;
  v_checkins int;
  v_avg numeric;
  v_praise int;
  v_kodr int;
  v_cico_start int;
  v_cico_grad int;
begin
  -- 접근 권한: 같은 학교 교사 또는 운영자
  if auth.jwt() ->> 'email' <> 'toyswar987@naver.com'
     and not exists (
       select 1 from profiles p
       where p.user_id = auth.uid() and p.role = 'teacher'
         and p.school_id = p_school_id) then
    raise exception '권한이 없어요.';
  end if;

  select count(*) into v_students
  from profiles where school_id = p_school_id and role = 'student';

  select count(distinct user_id), count(*), coalesce(avg(score_pct), 0)
  into v_active, v_checkins, v_avg
  from daily_checkins
  where school_id = p_school_id
    and checkin_date >= d_from and checkin_date <= d_to;

  select count(*) into v_praise from praise
  where school_id = p_school_id and created_at >= d_from and created_at < (d_to + 1);

  select count(*) into v_kodr from kodr_records
  where school_id = p_school_id and occurred_date >= d_from and occurred_date <= d_to;

  select count(*) into v_cico_start from cico_enrollments
  where school_id = p_school_id and start_date >= d_from and start_date <= d_to;

  select count(*) into v_cico_grad from cico_enrollments
  where school_id = p_school_id and status = 'graduated'
    and end_date is not null and end_date >= d_from and end_date <= d_to;

  return jsonb_build_object(
    'from', d_from, 'to', d_to,
    'student_count', v_students,
    'active_students', v_active,
    'participation_rate',
      case when v_students > 0 then round((v_active::numeric / v_students) * 100, 1) else 0 end,
    'checkin_count', v_checkins,
    'avg_score', round(coalesce(v_avg, 0), 1),
    'praise_count', v_praise,
    'kodr_count', v_kodr,
    'cico_started', v_cico_start,
    'cico_graduated', v_cico_grad
  );
end $$;
revoke all on function public.school_annual_report(uuid, date, date) from public;
grant execute on function public.school_annual_report(uuid, date, date) to authenticated;
