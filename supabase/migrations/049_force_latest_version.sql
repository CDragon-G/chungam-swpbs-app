-- 049_force_latest_version.sql
-- 최신 버전이 아니면 로그인·가입을 막는다.
--
-- 이미 있는 app_releases 의 min_version 이 그 기준이다.
-- 앱은 min_version 미만이면 닫을 수 없는 안내창을 띄우고,
-- 로그인·가입 버튼도 동작하지 않는다.
--
-- 여기서는 두 가지를 한다.
--   1) min_version 을 latest_version 과 같게 맞춘다 → "최신만 허용"
--   2) 그 상태를 한 번에 되돌리거나 조절할 수 있는 함수를 둔다

-- ═══════════ 1) 최신만 허용 ═══════════
--   0.21.0 이 스토어에 올라간 뒤에 실행하세요.
--   심사 중에 미리 실행하면 아무도 로그인하지 못합니다.
update app_releases
   set latest_version = '0.21.0',
       min_version    = '0.21.0',
       updated_at     = now()
 where platform in ('android', 'ios');

-- ═══════════ 2) 운영 중 조절용 ═══════════
--   Play 단계적 출시나 iOS 심사 지연으로 아직 못 받은 사람이 생기면
--   min_version 만 낮춰 잠금을 풀 수 있다. latest_version 은 그대로 두면
--   "새 버전이 나왔어요" 안내는 계속 뜬다.
--
--   잠금 풀기 (안내만 하고 막지는 않음)
--     select set_version_gate('android', '0.20.1');
--   다시 잠그기
--     select set_version_gate('android', '0.21.0');
--   양쪽 한꺼번에
--     select set_version_gate(null, '0.21.0');
create or replace function set_version_gate(
  p_platform text,          -- 'android' | 'ios' | null(둘 다)
  p_min_version text
)
returns json
language plpgsql security definer set search_path = public as $$
declare v_rows int;
begin
  if p_min_version is null or version_num(p_min_version) = array[0] then
    return json_build_object('ok', false, 'error', '버전 형식을 확인하세요 (예: 0.20.1)');
  end if;

  update app_releases
     set min_version = p_min_version, updated_at = now()
   where p_platform is null or platform = p_platform;
  get diagnostics v_rows = row_count;

  return json_build_object('ok', true, 'updated', v_rows,
                           'min_version', p_min_version);
end $$;
revoke all on function set_version_gate(text, text) from public, anon, authenticated;
-- 운영자만 (SQL 에디터에서 직접 실행)

-- ═══════════ 3) 확인 ═══════════
--   select platform, latest_version, min_version, updated_at from app_releases;
