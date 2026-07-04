-- 023_subscription_admin.sql
-- 운영자용 구독 목록 조회 RPC.
--   021로 schools 직접 SELECT를 조였으므로, 운영자가 전체 학교의 갱신 현황을
--   보려면 정의자 권한 RPC가 필요하다. (022 컬럼에 의존 → 022 먼저 실행)

create or replace function public.list_subscriptions()
returns table (
  id uuid,
  name text,
  region text,
  level text,
  subscription_status text,
  subscription_expires_at date,
  grace_until date,
  auto_renew boolean,
  renewed_count int,
  student_count int,
  days_left int
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.jwt() ->> 'email' <> 'toyswar987@naver.com' then
    raise exception '운영자만 조회할 수 있어요.';
  end if;

  return query
  select
    s.id, s.name, s.region, s.level,
    s.subscription_status, s.subscription_expires_at,
    s.grace_until, s.auto_renew, s.renewed_count,
    (select count(*)::int from profiles p
       where p.school_id = s.id and p.role = 'student'),
    case when s.subscription_expires_at is null then null
         else (s.subscription_expires_at - current_date) end
  from schools s
  order by s.subscription_expires_at asc nulls last, s.created_at asc;
end $$;

revoke all on function public.list_subscriptions() from public;
grant execute on function public.list_subscriptions() to authenticated;
