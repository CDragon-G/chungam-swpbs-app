-- 024_renewal_batch.sql
-- 갱신 안내 이메일 자동화의 DB 절반. (나머지 절반은 Edge Function send-renewal-reminders)
--   · renewal_batch()      : 오늘 안내를 보내야 할 학교 + 담당자 이메일 + 성과지표를 반환
--   · mark_renewal_stage() : 발송 완료 기록(중복발송 방지) + 유예/만료 상태 전이
--
--   단계(stage)와 발송 조건 (days_left = 만료일 - 오늘):
--     d30   : 8 ~ 30일 전
--     d7    : 2 ~ 7일 전
--     d1    : 0 ~ 1일 전 (오늘 만료 포함)
--     grace : 만료 후 ~ 유예 종료일(grace_until, 만료+14일)까지 — 서비스 유지
--     churn : 유예 종료 후에도 미갱신 → status='expired' + 윈백 메일
--   각 단계는 한 번만 발송(last_renewal_stage 랭크로 중복 차단).
--
--   호출 권한: service_role(크론/엣지) 또는 운영자.

-- ── 1) 발송 대상 스캔 ────────────────────────────────────────
create or replace function public.renewal_batch()
returns table (
  school_id uuid,
  school_name text,
  contact_email text,
  contact_name text,
  auto_renew boolean,
  stage text,
  days_left int,
  expires_at date,
  grace_until date,
  student_count int,
  metrics jsonb
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and coalesce(auth.jwt() ->> 'email', '') <> 'toyswar987@naver.com' then
    raise exception '권한이 없어요.';
  end if;

  return query
  with base as (
    select s.*, (s.subscription_expires_at - current_date) as dleft
    from schools s
    where s.subscription_status = 'active'
      and s.subscription_expires_at is not null
  ),
  staged as (
    select b.*,
      case
        when b.dleft between 8 and 30 then 'd30'
        when b.dleft between 2 and 7  then 'd7'
        when b.dleft between 0 and 1  then 'd1'
        when b.dleft < 0 and (b.grace_until is null or b.grace_until >= current_date) then 'grace'
        when b.dleft < 0 and b.grace_until is not null and b.grace_until < current_date then 'churn'
        else null
      end as tgt_stage
    from base b
  ),
  ranked as (
    select st.*,
      case st.tgt_stage
        when 'd30' then 1 when 'd7' then 2 when 'd1' then 3
        when 'grace' then 4 when 'churn' then 5 else 0 end as tgt_rank,
      case st.last_renewal_stage
        when 'd30' then 1 when 'd7' then 2 when 'd1' then 3
        when 'grace' then 4 when 'churn' then 5 else 0 end as sent_rank
    from staged st
  )
  select
    r.id,
    r.name,
    coalesce(
      (select pr.contact_email from purchase_requests pr
        where pr.school_id = r.id and coalesce(pr.contact_email, '') <> ''
        order by pr.created_at desc limit 1),
      (select u.email::text from auth.users u where u.id = r.created_by)
    ),
    coalesce(
      (select pr.contact_name from purchase_requests pr
        where pr.school_id = r.id and coalesce(pr.contact_name, '') <> ''
        order by pr.created_at desc limit 1),
      '담당 선생님'
    ),
    r.auto_renew,
    r.tgt_stage,
    r.dleft,
    r.subscription_expires_at,
    r.grace_until,
    (select count(*)::int from profiles p where p.school_id = r.id and p.role = 'student'),
    jsonb_build_object(
      'active', m.active,
      'checkins', m.cnt,
      'avg_score', round(m.avgp::numeric, 1),
      'praise', (select count(*) from praise pz
                   where pz.school_id = r.id and pz.created_at >= current_date - interval '1 year'),
      'kodr', (select count(*) from kodr_records kr
                 where kr.school_id = r.id and kr.occurred_date >= (current_date - interval '1 year')::date),
      'cico_grad', (select count(*) from cico_enrollments ce
                      where ce.school_id = r.id and ce.status = 'graduated')
    )
  from ranked r
  left join lateral (
    select count(distinct dcx.user_id) as active, count(*) as cnt, coalesce(avg(dcx.score_pct), 0) as avgp
    from daily_checkins dcx
    where dcx.school_id = r.id
      and dcx.checkin_date >= (current_date - interval '1 year')::date
  ) m on true
  where r.tgt_stage is not null
    and r.tgt_rank > r.sent_rank
  order by r.dleft asc;
end $$;
revoke all on function public.renewal_batch() from public;
grant execute on function public.renewal_batch() to authenticated, service_role;

-- ── 2) 발송 기록 + 상태 전이 ─────────────────────────────────
create or replace function public.mark_renewal_stage(p_school_id uuid, p_stage text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_exp date;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and coalesce(auth.jwt() ->> 'email', '') <> 'toyswar987@naver.com' then
    raise exception '권한이 없어요.';
  end if;
  if p_stage not in ('d30', 'd7', 'd1', 'grace', 'churn') then
    raise exception '허용되지 않은 단계예요.';
  end if;

  select subscription_expires_at into v_exp from schools where id = p_school_id;

  update schools set last_renewal_stage = p_stage where id = p_school_id;

  if p_stage = 'grace' then
    -- 만료 시점부터 14일 유예 (status는 active 유지 → 앱 재빌드 불필요)
    update schools
      set grace_until = coalesce(grace_until, (v_exp + interval '14 days')::date)
      where id = p_school_id;
  elsif p_stage = 'churn' then
    update schools set subscription_status = 'expired' where id = p_school_id;
  end if;

  insert into renewal_events(school_id, event_type, detail)
  values (p_school_id, 'reminder_' || p_stage, p_stage || ' 안내 발송');
end $$;
revoke all on function public.mark_renewal_stage(uuid, text) from public;
grant execute on function public.mark_renewal_stage(uuid, text) to authenticated, service_role;
