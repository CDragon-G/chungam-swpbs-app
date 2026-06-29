-- 015_subscription.sql
-- 학교 구독(결제) 상태 관리. 무료 체험 없이 결제 확인된 학교만 학생 가입 허용.
--   pending : 등록됐으나 결제 미확인 (학생 가입 불가)
--   active  : 결제 확인됨 (정상 사용)
--   expired : 구독 만료 (학생 가입 불가)

alter table schools add column if not exists subscription_status text not null default 'pending';
alter table schools add column if not exists subscription_expires_at date;

-- 기존 학교(충암중 등)는 활성 처리 — 운영 중이므로
update schools set subscription_status = 'active'
where subscription_status = 'pending'
  and created_at < now();

-- 학교 코드로 조회 시 구독 상태도 함께 (findByCode가 사용)
-- (별도 함수 불필요: select에 컬럼 추가됨)

-- 운영자 전용: 학교 활성화 (결제 확인 후 호출). 운영자 판단은 앱 밖에서.
-- 여기서는 RPC로 두되, 실제 운영자 권한 체크는 별도 admin 도구에서.
-- 초기에는 Supabase 대시보드에서 직접 update 해도 됨:
--   update schools set subscription_status='active',
--     subscription_expires_at='2027-03-01' where school_code='XXXXXX';
