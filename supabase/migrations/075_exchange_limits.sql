-- 075_exchange_limits.sql
-- 강화물마다 학생 1인당 교환 횟수를 정한다.
--
-- 왜
--   '따뜻한 어묵' 처럼 매일 나눠주는 강화물은 한 학생이 포인트를 모아 하루에 여러 개를
--   가져가면 다른 학생 몫이 없어진다. '자리 바꾸기 이용권' 은 한 달에 한 번이면 충분하다.
--   지금은 재고로만 막을 수 있어서, 한 사람이 재고를 다 가져가도 막을 수 없었다.
--
-- 무엇이 바뀌나
--   point_store_items.limit_per_student — 1인 최대 교환 횟수 (null = 제한 없음)
--   point_store_items.limit_period      — 그 횟수를 세는 기간
--       'total' 강화물이 있는 동안 전체 · 'day' 하루 · 'week' 이번 주(월~일) · 'month' 이번 달
--   request_exchange() — 040 과 같고, 횟수 확인만 더했다. 취소된 교환은 세지 않는다.
--   my_exchange_limits() — 학생 교환소에 "오늘 1/1" 처럼 보여주려고 내 사용 횟수를 준다.
--
--   기간은 한국 시간으로 자른다. 하루는 자정, 이번 주는 월요일 자정부터.
--   함께 키우기(단체 강화물)는 해당 없다 — 그쪽은 1인 최대 포인트(max_per_student)가 있다.
--
-- 구버전 앱
--   제한을 넘으면 서버가 막고 이유를 말해 준다. 화면에 제한 표시가 없을 뿐이다.

alter table point_store_items
  add column if not exists limit_per_student int;
alter table point_store_items
  add column if not exists limit_period text not null default 'total';
do $$ begin
  alter table point_store_items
    add constraint psi_limit_per_student_chk
    check (limit_per_student is null or limit_per_student between 1 and 100);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table point_store_items
    add constraint psi_limit_period_chk
    check (limit_period in ('total', 'day', 'week', 'month'));
exception when duplicate_object then null; end $$;

create index if not exists exchanges_user_item_idx
  on point_exchanges (user_id, item_id, requested_at desc);

-- ═══════════ 1) 기간 시작 시각 (한국 시간) ═══════════
create or replace function exchange_period_start(p_period text)
returns timestamptz
language sql stable set search_path = public as $$
  select case p_period
    when 'day'   then date_trunc('day',   now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
    when 'week'  then date_trunc('week',  now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
    when 'month' then date_trunc('month', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
    else '-infinity'::timestamptz
  end;
$$;

create or replace function exchange_period_label(p_period text)
returns text
language sql immutable as $$
  select case p_period
    when 'day'   then '하루에'
    when 'week'  then '한 주에'
    when 'month' then '한 달에'
    else '한 사람당'
  end;
$$;

-- ═══════════ 2) 교환 신청 — 040 과 같고 횟수 확인만 더했다 ═══════════
create or replace function request_exchange(p_item_id uuid)
returns uuid
language plpgsql security definer set search_path = public, auth as $$
declare
  v_user_id uuid := auth.uid();
  v_school_id uuid; v_grade int; v_class int;
  v_item record; v_balance int; v_exchange_id uuid;
  v_used int;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;

  select school_id, grade, class_num into v_school_id, v_grade, v_class
    from profiles where user_id = v_user_id;

  -- 같은 강화물을 동시에 누르면 차례로 (횟수 · 재고를 정확히 세려고)
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

  -- 1인 교환 횟수
  if v_item.limit_per_student is not null then
    select count(*) into v_used
      from point_exchanges e
     where e.user_id = v_user_id
       and e.item_id = v_item.id
       and e.status <> 'cancelled'
       and e.requested_at >= exchange_period_start(v_item.limit_period);
    if v_used >= v_item.limit_per_student then
      raise exception '이 강화물은 % %번까지 교환할 수 있어요.',
        exchange_period_label(v_item.limit_period), v_item.limit_per_student;
    end if;
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

-- ═══════════ 3) 내 사용 횟수 (학생 교환소 표시용) ═══════════
create or replace function my_exchange_limits()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
  v_school uuid;
begin
  select school_id into v_school from profiles where user_id = v_user;
  if v_school is null then
    return '[]'::json;
  end if;
  return coalesce((
    select json_agg(json_build_object(
             'item_id', i.id,
             'limit', i.limit_per_student,
             'period', i.limit_period,
             'used', (select count(*) from point_exchanges e
                       where e.user_id = v_user and e.item_id = i.id
                         and e.status <> 'cancelled'
                         and e.requested_at >= exchange_period_start(i.limit_period))))
      from point_store_items i
     where i.school_id = v_school
       and i.is_active
       and i.limit_per_student is not null), '[]'::json);
end $$;
grant execute on function my_exchange_limits() to authenticated;

-- ═══════════ 확인 ═══════════
--   select name, limit_per_student, limit_period from point_store_items
--    where limit_per_student is not null;
--   앱에서: 선생님 교환소 → 강화물 편집 → '1인 교환 횟수 제한'
