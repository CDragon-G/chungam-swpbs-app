-- 027_class_store.sql
-- 학급 상점: 담임교사가 자기 반 학생에게만 보이는 강화물을 등록한다.
--   · grade/class_num 이 null  → 전교 공통 상품 (관리자만 등록)
--   · grade/class_num 이 지정  → 해당 학급 학생에게만 노출 (모든 교사 등록 가능)
--   · emoji: 상품별 아이콘 (기존 🎁 고정 → 교사가 선택)
--   · created_by: 등록 교사 — 일반 교사는 자기 상품만 수정/삭제, 관리자는 전부
--   보안: 다른 반 상품 교환은 request_exchange 서버 검증으로 차단.

-- ── 1) 컬럼 확장 ─────────────────────────────────────────────
alter table point_store_items
  add column if not exists emoji text not null default '🎁';
alter table point_store_items
  add column if not exists grade int;
alter table point_store_items
  add column if not exists class_num int;
alter table point_store_items
  add column if not exists created_by uuid references auth.users(id) on delete set null;

create index if not exists psi_class_idx
  on point_store_items(school_id, grade, class_num, is_active);

-- ── 2) 쓰기 정책 세분화 ──────────────────────────────────────
-- 기존: 같은 학교 교사 전체 쓰기 허용(관리자 제한은 UI뿐) → 역할별로 정리.
drop policy if exists psi_teacher_write on point_store_items;

drop policy if exists psi_insert on point_store_items;
create policy psi_insert on point_store_items
  for insert to authenticated
  with check (
    school_id = current_profile_school()
    and current_profile_role() = 'teacher'
    and (
      -- 학급 상품: 모든 교사, 단 본인 명의로만
      (grade is not null and class_num is not null and created_by = auth.uid())
      -- 전교 상품: 관리자만
      or (grade is null and class_num is null and is_admin_teacher())
    )
  );

drop policy if exists psi_update on point_store_items;
create policy psi_update on point_store_items
  for update to authenticated
  using (
    school_id = current_profile_school()
    and current_profile_role() = 'teacher'
    and (is_admin_teacher() or created_by = auth.uid())
  )
  with check (
    school_id = current_profile_school()
    and current_profile_role() = 'teacher'
    and (
      is_admin_teacher()
      -- 일반 교사는 자기 학급 상품 범위를 벗어날 수 없음 (전교로 승격 불가)
      or (created_by = auth.uid() and grade is not null and class_num is not null)
    )
  );

drop policy if exists psi_delete on point_store_items;
create policy psi_delete on point_store_items
  for delete to authenticated
  using (
    school_id = current_profile_school()
    and current_profile_role() = 'teacher'
    and (is_admin_teacher() or created_by = auth.uid())
  );

-- ── 3) 교환 시 학급 검증 (request_exchange 갱신) ─────────────
create or replace function request_exchange(p_item_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_school_id uuid;
  v_grade int;
  v_class int;
  v_item record;
  v_balance int;
  v_exchange_id uuid;
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select school_id, grade, class_num into v_school_id, v_grade, v_class
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
  -- 학급 상품이면 학생의 학년·반이 일치해야 함
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
    update point_store_items
      set stock = stock - 1, updated_at = now()
      where id = v_item.id;
  end if;

  return v_exchange_id;
end;
$$;
grant execute on function request_exchange(uuid) to authenticated;
