-- 040_group_rewards.sql
-- 1) 함께 키우기 — 학급 단체 강화물을 여러 학생이 포인트를 보태어 달성
--      · 과자 파티처럼 학급 전체가 누리는 강화물을 한 학생이 결제하는 구조를 없앤다
--      · 목표 포인트에 도달하면 담임에게 알림 → 지급 처리
--      · 기여도 TOP 3를 보여 참여를 드러낸다
--      · 목표 미달로 취소하면 보탠 포인트를 전액 환불
-- 2) 주간 개근 보너스: 월~금 5일이 모두 수업일인 주에만 지급

-- ═══════════ 1) 강화물 유형 ═══════════
alter table point_store_items
  add column if not exists item_type text not null default 'individual';
do $$ begin
  alter table point_store_items
    add constraint psi_item_type_chk check (item_type in ('individual','group'));
exception when duplicate_object then null; end $$;

-- 단체 강화물에서 cost_points 는 '목표 총액'으로 쓴다.
alter table point_store_items
  add column if not exists max_per_student int;      -- 1인 최대 보탤 수 있는 포인트 (null = 무제한)
alter table point_store_items
  add column if not exists achieved_at timestamptz;  -- 목표 달성 시각
alter table point_store_items
  add column if not exists closed_at timestamptz;    -- 지급 완료 또는 취소 시각

create index if not exists psi_group_idx
  on point_store_items(school_id, item_type, is_active);

-- ═══════════ 2) 기여 내역 ═══════════
create table if not exists group_contributions (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references point_store_items(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  school_id uuid not null references schools(id) on delete cascade,
  amount int not null check (amount > 0),
  refunded boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists gc_item_idx on group_contributions(item_id, created_at desc);
create index if not exists gc_user_idx on group_contributions(user_id, created_at desc);

alter table group_contributions enable row level security;

drop policy if exists gc_read on group_contributions;
create policy gc_read on group_contributions
  for select using (school_id = current_profile_school());

-- 쓰기는 RPC(SECURITY DEFINER)로만

-- ═══════════ 3) 포인트 보태기 ═══════════
create or replace function contribute_to_group_item(p_item_id uuid, p_amount int)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
  v_school uuid; v_grade int; v_class int;
  v_item record;
  v_raised int; v_mine int; v_balance int;
  v_remain int;
begin
  if v_user is null then
    return json_build_object('ok', false, 'error', '로그인이 필요합니다');
  end if;
  if p_amount is null or p_amount <= 0 then
    return json_build_object('ok', false, 'error', '보탤 포인트를 입력해주세요');
  end if;

  select school_id, grade, class_num into v_school, v_grade, v_class
    from profiles where user_id = v_user;

  select * into v_item from point_store_items
   where id = p_item_id and is_active = true for update;

  if v_item is null then
    return json_build_object('ok', false, 'error', '강화물을 찾을 수 없어요');
  end if;
  if v_item.item_type is distinct from 'group' then
    return json_build_object('ok', false, 'error', '함께 키우는 강화물이 아니에요');
  end if;
  if v_item.school_id is distinct from v_school then
    return json_build_object('ok', false, 'error', '다른 학교의 강화물이에요');
  end if;
  if v_item.grade is not null
     and (v_grade is distinct from v_item.grade
          or v_class is distinct from v_item.class_num) then
    return json_build_object('ok', false, 'error', '우리 반 강화물이 아니에요');
  end if;
  if v_item.achieved_at is not null then
    return json_build_object('ok', false, 'error', '이미 목표를 달성했어요');
  end if;
  if v_item.closed_at is not null then
    return json_build_object('ok', false, 'error', '마감된 강화물이에요');
  end if;

  -- 현재 모인 금액
  select coalesce(sum(amount), 0) into v_raised
    from group_contributions where item_id = p_item_id and refunded = false;
  v_remain := v_item.cost_points - v_raised;
  if v_remain <= 0 then
    return json_build_object('ok', false, 'error', '이미 목표를 달성했어요');
  end if;
  -- 남은 금액을 넘겨 받지 않는다
  if p_amount > v_remain then
    p_amount := v_remain;
  end if;

  -- 1인 한도
  if v_item.max_per_student is not null then
    select coalesce(sum(amount), 0) into v_mine
      from group_contributions
     where item_id = p_item_id and user_id = v_user and refunded = false;
    if v_mine + p_amount > v_item.max_per_student then
      return json_build_object('ok', false,
        'error', format('한 사람이 최대 %sP까지 보탤 수 있어요 (내가 보탠 %sP)',
                        v_item.max_per_student, v_mine));
    end if;
  end if;

  -- 잔액
  select get_user_points(v_user) into v_balance;
  if v_balance < p_amount then
    return json_build_object('ok', false,
      'error', format('포인트가 부족해요 (보유 %sP)', v_balance));
  end if;

  insert into group_contributions (item_id, user_id, school_id, amount)
  values (p_item_id, v_user, v_school, p_amount);

  insert into point_transactions
    (user_id, school_id, amount, reason, period_key, description)
  values
    (v_user, v_school, -p_amount, 'group_contribute',
     p_item_id::text || ':' || gen_random_uuid()::text,
     '함께 키우기: ' || v_item.name);

  v_raised := v_raised + p_amount;

  -- 목표 달성
  if v_raised >= v_item.cost_points then
    update point_store_items set achieved_at = now(), updated_at = now()
      where id = p_item_id;

    perform push_notification(
      v_school,
      case when v_item.grade is null then 'students' else 'class' end,
      null, v_item.grade, v_item.class_num,
      'exchange', '🎉 목표 달성!',
      v_item.name || ' — 함께 키우기 목표를 채웠어요!',
      '/student/store', 'grpdone:' || p_item_id::text);

    if v_item.created_by is not null then
      perform push_notification(
        v_school, 'user', v_item.created_by, null, null,
        'exchange', '🎉 함께 키우기 목표 달성',
        v_item.name || ' 목표가 채워졌어요. 지급 처리를 해주세요.',
        '/teacher/store', 'grpdoneT:' || p_item_id::text);
    end if;
  end if;

  return json_build_object(
    'ok', true, 'contributed', p_amount,
    'raised', v_raised, 'goal', v_item.cost_points,
    'achieved', v_raised >= v_item.cost_points);
end $$;
grant execute on function contribute_to_group_item(uuid, int) to authenticated;

-- ═══════════ 4) 현황 조회 (목표·모금액·TOP 3·내 기여) ═══════════
create or replace function group_item_status(p_item_id uuid)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
  v_item record;
  v_raised int; v_mine int; v_people int;
  v_top json;
begin
  select * into v_item from point_store_items where id = p_item_id;
  if v_item is null then return json_build_object('ok', false); end if;

  select coalesce(sum(amount), 0), count(distinct user_id)
    into v_raised, v_people
    from group_contributions where item_id = p_item_id and refunded = false;

  select coalesce(sum(amount), 0) into v_mine
    from group_contributions
   where item_id = p_item_id and user_id = v_user and refunded = false;

  -- 기여도 TOP 3 (닉네임 공개 — 학급 내 참여 독려 목적)
  select coalesce(json_agg(t), '[]'::json) into v_top from (
    select p.nickname, sum(g.amount)::int as amount
      from group_contributions g
      join profiles p on p.user_id = g.user_id
     where g.item_id = p_item_id and g.refunded = false
     group by p.nickname
     order by sum(g.amount) desc, min(g.created_at)
     limit 3
  ) t;

  return json_build_object(
    'ok', true,
    'goal', v_item.cost_points,
    'raised', v_raised,
    'people', v_people,
    'my_amount', v_mine,
    'max_per_student', v_item.max_per_student,
    'achieved', v_item.achieved_at is not null,
    'closed', v_item.closed_at is not null,
    'top', v_top);
end $$;
grant execute on function group_item_status(uuid) to authenticated;

-- ═══════════ 5) 교사: 지급 완료 처리 ═══════════
create or replace function fulfill_group_item(p_item_id uuid)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_item record; v_school uuid;
begin
  select school_id into v_school from profiles
   where user_id = auth.uid() and role = 'teacher';
  if v_school is null then
    return json_build_object('ok', false, 'error', '교사만 처리할 수 있어요');
  end if;

  select * into v_item from point_store_items
   where id = p_item_id and school_id = v_school for update;
  if v_item is null then
    return json_build_object('ok', false, 'error', '강화물을 찾을 수 없어요');
  end if;
  if v_item.achieved_at is null then
    return json_build_object('ok', false, 'error', '아직 목표를 달성하지 않았어요');
  end if;
  if v_item.closed_at is not null then
    return json_build_object('ok', false, 'error', '이미 처리된 강화물이에요');
  end if;

  update point_store_items
     set closed_at = now(), is_active = false, updated_at = now()
   where id = p_item_id;

  perform push_notification(
    v_school,
    case when v_item.grade is null then 'students' else 'class' end,
    null, v_item.grade, v_item.class_num,
    'exchange', '🎁 함께 키우기 완료',
    v_item.name || ' — 선생님이 준비해 주실 거예요!',
    '/student/store', 'grpfin:' || p_item_id::text);

  return json_build_object('ok', true);
end $$;
grant execute on function fulfill_group_item(uuid) to authenticated;

-- ═══════════ 6) 교사: 취소 및 전액 환불 ═══════════
create or replace function cancel_group_item(p_item_id uuid)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_item record; v_school uuid; c record; v_n int := 0;
begin
  select school_id into v_school from profiles
   where user_id = auth.uid() and role = 'teacher';
  if v_school is null then
    return json_build_object('ok', false, 'error', '교사만 처리할 수 있어요');
  end if;

  select * into v_item from point_store_items
   where id = p_item_id and school_id = v_school for update;
  if v_item is null then
    return json_build_object('ok', false, 'error', '강화물을 찾을 수 없어요');
  end if;
  if v_item.closed_at is not null then
    return json_build_object('ok', false, 'error', '이미 처리된 강화물이에요');
  end if;

  -- 보탠 포인트를 전원에게 돌려준다
  for c in
    select user_id, sum(amount)::int as amt
      from group_contributions
     where item_id = p_item_id and refunded = false
     group by user_id
  loop
    insert into point_transactions
      (user_id, school_id, amount, reason, period_key, description)
    values
      (c.user_id, v_school, c.amt, 'group_refund',
       p_item_id::text, '함께 키우기 취소 환불: ' || v_item.name);
    v_n := v_n + 1;
  end loop;

  update group_contributions set refunded = true
   where item_id = p_item_id and refunded = false;

  update point_store_items
     set closed_at = now(), achieved_at = null, is_active = false, updated_at = now()
   where id = p_item_id;

  perform push_notification(
    v_school,
    case when v_item.grade is null then 'students' else 'class' end,
    null, v_item.grade, v_item.class_num,
    'exchange', '함께 키우기 취소',
    v_item.name || ' — 보탠 포인트를 모두 돌려드렸어요.',
    '/student/store', 'grpcancel:' || p_item_id::text);

  return json_build_object('ok', true, 'refunded_users', v_n);
end $$;
grant execute on function cancel_group_item(uuid) to authenticated;

-- ═══════════ 7) 개별 교환에서 단체 강화물 차단 ═══════════
create or replace function request_exchange(p_item_id uuid)
returns uuid
language plpgsql security definer set search_path = public, auth as $$
declare
  v_user_id uuid := auth.uid();
  v_school_id uuid; v_grade int; v_class int;
  v_item record; v_balance int; v_exchange_id uuid;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;

  select school_id, grade, class_num into v_school_id, v_grade, v_class
    from profiles where user_id = v_user_id;

  select * into v_item from point_store_items
   where id = p_item_id and is_active = true for update;

  if v_item is null then
    raise exception '상품을 찾을 수 없거나 비활성화 상태입니다.';
  end if;
  -- 단체 강화물은 개별 교환 불가 (함께 키우기로만)
  if v_item.item_type = 'group' then
    raise exception '함께 키우는 강화물이에요. 포인트를 보태 목표를 채워주세요.';
  end if;
  if v_item.school_id != v_school_id then
    raise exception '다른 학교 상품은 교환할 수 없습니다.';
  end if;
  if v_item.grade is not null
     and (v_grade is distinct from v_item.grade
          or v_class is distinct from v_item.class_num) then
    raise exception '우리 반 상품이 아니에요.';
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
    update point_store_items set stock = stock - 1, updated_at = now()
     where id = v_item.id;
  end if;

  return v_exchange_id;
end $$;
grant execute on function request_exchange(uuid) to authenticated;

-- ═══════════ 8) 주간 개근 보너스: 월~금 5일이 모두 수업일인 주에만 ═══════════
-- 금요일이 재량휴업일이면 그 주는 월~목뿐이므로 보너스 대상이 아니다.
create or replace function award_checkin_points(
  p_user_id uuid, p_school_id uuid, p_checkin_date date)
returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  v_week_start date := date_trunc('week', p_checkin_date)::date;
  v_period_key text := to_char(p_checkin_date, 'YYYY-MM-DD');
  v_week_key text := to_char(v_week_start, 'IYYY-IW');
  v_school_days int;
  v_done int;
begin
  -- 일일 100P (중복 방지)
  insert into point_transactions
    (user_id, school_id, amount, reason, period_key, description)
  values
    (p_user_id, p_school_id, 100, 'checkin_daily', v_period_key, '일일 자기점검 참여')
  on conflict (user_id, reason, period_key) do nothing;

  -- 그 주 월~금 중 수업일 수
  select count(*) into v_school_days
    from generate_series(v_week_start, v_week_start + 4, interval '1 day') d
   where is_school_day(p_school_id, d::date);

  -- 월~금 5일이 모두 수업일인 주에만 개근 보너스를 준다
  if v_school_days = 5 then
    select count(distinct checkin_date) into v_done
      from daily_checkins
     where user_id = p_user_id
       and checkin_date >= v_week_start
       and checkin_date <= v_week_start + 4;

    if v_done >= 5 then
      insert into point_transactions
        (user_id, school_id, amount, reason, period_key, description)
      values
        (p_user_id, p_school_id, 500, 'checkin_weekly', v_week_key, '주간 개근 보너스')
      on conflict (user_id, reason, period_key) do nothing;
    end if;
  end if;
end $$;
grant execute on function award_checkin_points(uuid, uuid, date) to authenticated;
