-- 012_fcm_tokens.sql
-- FCM 원격 푸시를 위한 기기 토큰 저장.
-- 한 사용자가 여러 기기(폰+태블릿)를 쓸 수 있으므로 별도 테이블로 관리.

create table if not exists device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text,                       -- 'ios' | 'android' | 'web'
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

create index if not exists device_tokens_user_idx on device_tokens (user_id);

alter table device_tokens enable row level security;

-- 본인 토큰만 등록/조회/삭제
drop policy if exists dt_own on device_tokens;
create policy dt_own on device_tokens
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 토큰 upsert RPC (앱에서 로그인 시 호출)
create or replace function public.register_device_token(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then raise exception '로그인 상태가 아닙니다.'; end if;
  insert into device_tokens (user_id, token, platform, updated_at)
  values (auth.uid(), p_token, p_platform, now())
  on conflict (user_id, token)
  do update set platform = excluded.platform, updated_at = now();
end;
$$;

revoke all on function public.register_device_token(text, text) from public;
grant execute on function public.register_device_token(text, text) to authenticated;
