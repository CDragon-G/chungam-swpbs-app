-- 028_store_item_creator_name.sql
-- 상점 상품에 등록 교사 이름을 함께 저장(비정규화) → 학생·교사 화면에서
-- 별도 조인/추가 RLS 없이 "누가 등록했는지" 바로 표시.
--   · created_by_name: 등록 시점 교사 닉네임 (이후 닉네임 변경돼도 그대로 유지 — 표시용)

alter table point_store_items
  add column if not exists created_by_name text;
