-- 052_version_gate_0_23_0.sql
-- 0.23.0 (성장 12단계 + 학년도 리셋) 출시 뒤 버전 게이트를 올린다.
--
-- ⚠ 스토어에 0.23.0 이 실제로 올라간 뒤에 실행하세요.
--    심사 중에 미리 실행하면 아무도 로그인하지 못합니다.
--    Play 단계적 출시를 쓰신다면 100% 가 된 뒤에 실행하세요.
--
-- 050_version_gate_0_22_0.sql 은 실행하지 마세요.
-- 0.22.0 은 스토어에 올라가지 않고 0.23.0 에 흡수되었습니다.

update app_releases
   set latest_version = '0.23.0',
       min_version    = '0.23.0',
       updated_at     = now()
 where platform in ('android', 'ios');

-- 잠금이 부담스러우면 안내만 하고 막지 않을 수도 있습니다.
--   select set_version_gate(null, '0.21.0');   -- 0.21.0 이상이면 로그인 허용
--   select platform, latest_version, min_version, updated_at from app_releases;
