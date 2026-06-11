-- 005_points_system.sql
-- Points system + Point Store + School leaderboard

-- =========================================================
-- 1. Tables
-- =========================================================

create table if not exists point_store_items (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  name text not null,
  description text,
  cost_points int not null check (cost_points >= 0),
  stock int,
  is_active boolean not null default true,
  order_index int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists point_store_items_school_idx
  on point_store_items(school_id, is_active, order_index);

create table if not exists point_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  school_id uuid not null references schools(id) on delete cascade,
  amount int not null,
  reason text not null,
  period_key text,
  description text,
  created_at timestamptz not null default now(),
  unique (user_id, reason, period_key)
);
create index if not exists point_transactions_user_idx
  on point_transactions(user_id, created_at desc);
create index if not exists point_transactions_school_idx
  on point_transactions(school_id, created_at desc);

create table if not exists point_exchanges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  school_id uuid not null references schools(id) on delete cascade,
  item_id uuid references point_store_items(id) on delete set null,
  item_name text not null,
  cost_points int not null,
  status text not null default 'pending'
    check (status in ('pending', 'fulfilled', 'cancelled')),
  requested_at timestamptz not null default now(),
  fulfilled_at timestamptz,
  fulfilled_by uuid references auth.users(id),
  note text
);
create index if not exists exchanges_user_idx
  on point_exchanges(user_id, requested_at desc);
create index if not exists exchanges_school_status_idx
  on point_exchanges(school_id, status, requested_at desc);

-- =========================================================
-- 2. School Leaderboard view
-- =========================================================

create or replace view school_leaderboard as
select
  s.id,
  s.name,
  s.region,
  s.level,
  coalesce(stu.student_count, 0) as student_count,
  coalesce(ch.checkin_count_30d, 0) as checkin_count_30d,
  coalesce(ch.participants_30d, 0) as participants_30d,
  coalesce(ch.avg_score_30d, 0)::float as avg_score_30d,
  case
    when coalesce(stu.student_count, 0) = 0 then 0
    else round(
      (coalesce(ch.checkin_count_30d, 0)::numeric
        / nullif(stu.student_count * 30, 0))
      * coalesce(ch.avg_score_30d, 0)
      * 10
    )::int
  end as school_score
from schools s
left join lateral (
  select count(*)::int as student_count
  from profiles p
  where p.school_id = s.id and p.role = 'student'
) stu on true
left join lateral (
  select
    count(*)::int as checkin_count_30d,
    count(distinct user_id)::int as participants_30d,
    avg(score_pct)::numeric as avg_score_30d
  from daily_checkins
  where school_id = s.id
    and checkin_date >= current_date - interval '30 days'
) ch on true;

grant select on school_leaderboard to authenticated, anon;

-- =========================================================
-- 3. RLS
-- =========================================================

alter table point_store_items enable row level security;
alter table point_transactions enable row level security;
alter table point_exchanges enable row level security;

-- point_store_items: same school read, same-school teacher write
drop policy if exists psi_select on point_store_items;
create policy psi_select on point_store_items
  for select using (school_id = current_profile_school());

drop policy if exists psi_teacher_write on point_store_items;
create policy psi_teacher_write on point_store_items
  for all using (
    current_profile_role() = 'teacher' and school_id = current_profile_school()
  ) with check (
    current_profile_role() = 'teacher' and school_id = current_profile_school()
  );

-- point_transactions: own read; teacher read same-school
drop policy if exists pt_self on point_transactions;
create policy pt_self on point_transactions
  for select using (user_id = auth.uid());

drop policy if exists pt_teacher_view on point_transactions;
create policy pt_teacher_view on point_transactions
  for select using (
    current_profile_role() = 'teacher' and school_id = current_profile_school()
  );
-- (no direct insert by clients — use functions below)

-- point_exchanges: student see own; teacher see/manage same-school
drop policy if exists pe_student on point_exchanges;
create policy pe_student on point_exchanges
  for select using (user_id = auth.uid());

drop policy if exists pe_teacher_manage on point_exchanges;
create policy pe_teacher_manage on point_exchanges
  for all using (
    current_profile_role() = 'teacher' and school_id = current_profile_school()
  ) with check (
    current_profile_role() = 'teacher' and school_id = current_profile_school()
  );

-- =========================================================
-- 4. Functions (SECURITY DEFINER)
-- =========================================================

-- 4a. Award daily check-in points (called after each successful check-in)
create or replace function award_checkin_points(
  p_user_id uuid,
  p_school_id uuid,
  p_checkin_date date
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_week_start date := date_trunc('week', p_checkin_date)::date;
  v_period_key text := to_char(p_checkin_date, 'YYYY-MM-DD');
  v_week_key text := to_char(v_week_start, 'IYYY-IW');
  v_full_week boolean;
begin
  -- Daily 100P (idempotent)
  insert into point_transactions
    (user_id, school_id, amount, reason, period_key, description)
  values
    (p_user_id, p_school_id, 100, 'checkin_daily', v_period_key, '일일 자기점검 참여')
  on conflict (user_id, reason, period_key) do nothing;

  -- Weekly bonus: 500P if Mon~Fri all done this week
  select count(distinct checkin_date) >= 5 into v_full_week
  from daily_checkins
  where user_id = p_user_id
    and checkin_date >= v_week_start
    and checkin_date <  v_week_start + interval '5 days'
    and extract(isodow from checkin_date) between 1 and 5;

  if v_full_week then
    insert into point_transactions
      (user_id, school_id, amount, reason, period_key, description)
    values
      (p_user_id, p_school_id, 500, 'checkin_weekly', v_week_key, '월~금 개근 보너스')
    on conflict (user_id, reason, period_key) do nothing;
  end if;
end;
$$;
grant execute on function award_checkin_points(uuid, uuid, date)
  to authenticated;

-- 4b. Get current user's point balance
create or replace function get_user_points(p_user_id uuid)
returns int
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(sum(amount), 0)::int
  from point_transactions
  where user_id = p_user_id;
$$;
grant execute on function get_user_points(uuid) to authenticated;

-- 4c. Request exchange (atomic: deduct balance + create record + decrement stock)
create or replace function request_exchange(p_item_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_school_id uuid;
  v_item record;
  v_balance int;
  v_exchange_id uuid;
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select school_id into v_school_id
    from profiles where user_id = v_user_id;

  select * into v_item
    from point_store_items
    where id = p_item_id and is_active = true
    for update;

  if v_item is null then
    raise exception '상품을 찾을 수 없거나 비활성화 상태입니다.';
  end if;
  if v_item.school_id != v_school_id then
    raise exception '다른 학교 상품은 교환할 수 없습니다.';
  end if;
  if v_item.stock is not null and v_item.stock <= 0 then
    raise exception '재고가 모두 소진되었습니다.';
  end if;

  select get_user_points(v_user_id) into v_balance;
  if v_balance < v_item.cost_points then
    raise exception '포인트가 부족합니다. (보유 %P / 필요 %P)',
      v_balance, v_item.cost_points;
  end if;

  insert into point_exchanges
    (user_id, school_id, item_id, item_name, cost_points)
  values
    (v_user_id, v_school_id, v_item.id, v_item.name, v_item.cost_points)
  returning id into v_exchange_id;

  insert into point_transactions
    (user_id, school_id, amount, reason, period_key, description)
  values
    (v_user_id, v_school_id, -v_item.cost_points, 'exchange',
     v_exchange_id::text, '상품 교환: ' || v_item.name);

  if v_item.stock is not null then
    update point_store_items
      set stock = stock - 1, updated_at = now()
      where id = v_item.id;
  end if;

  return v_exchange_id;
end;
$$;
grant execute on function request_exchange(uuid) to authenticated;

-- 4d. Teacher fulfills exchange (marks as received)
create or replace function fulfill_exchange(p_exchange_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_school_id uuid;
begin
  if current_profile_role() != 'teacher' then
    raise exception '교사만 처리할 수 있습니다.';
  end if;
  v_school_id := current_profile_school();

  update point_exchanges
    set status = 'fulfilled',
        fulfilled_at = now(),
        fulfilled_by = auth.uid(),
        note = coalesce(p_note, note)
    where id = p_exchange_id
      and school_id = v_school_id
      and status = 'pending';

  if not found then
    raise exception '교환 요청을 찾을 수 없거나 이미 처리되었습니다.';
  end if;
end;
$$;
grant execute on function fulfill_exchange(uuid, text) to authenticated;

-- 4e. Teacher cancels exchange (refunds points)
create or replace function cancel_exchange(p_exchange_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_school_id uuid;
  v_exchange record;
begin
  if current_profile_role() != 'teacher' then
    raise exception '교사만 처리할 수 있습니다.';
  end if;
  v_school_id := current_profile_school();

  select * into v_exchange from point_exchanges
    where id = p_exchange_id
      and school_id = v_school_id
      and status = 'pending'
    for update;

  if v_exchange is null then
    raise exception '교환 요청을 찾을 수 없거나 이미 처리되었습니다.';
  end if;

  update point_exchanges
    set status = 'cancelled',
        fulfilled_at = now(),
        fulfilled_by = auth.uid(),
        note = coalesce(p_note, note)
    where id = p_exchange_id;

  -- Refund points
  insert into point_transactions
    (user_id, school_id, amount, reason, period_key, description)
  values
    (v_exchange.user_id, v_school_id, v_exchange.cost_points,
     'refund', p_exchange_id::text, '교환 취소 환불: ' || v_exchange.item_name);

  -- Restock if item still exists
  if v_exchange.item_id is not null then
    update point_store_items
      set stock = stock + 1, updated_at = now()
      where id = v_exchange.item_id and stock is not null;
  end if;
end;
$$;
grant execute on function cancel_exchange(uuid, text) to authenticated;

-- 4f. Backfill: award points for any check-ins that exist without awarded points
-- (one-time helper for existing data)
create or replace function backfill_checkin_points()
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  c record;
  n int := 0;
begin
  for c in select user_id, school_id, checkin_date from daily_checkins
  loop
    perform award_checkin_points(c.user_id, c.school_id, c.checkin_date);
    n := n + 1;
  end loop;
  return n;
end;
$$;
grant execute on function backfill_checkin_points() to authenticated;
