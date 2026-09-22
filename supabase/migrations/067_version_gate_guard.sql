-- 067_version_gate_guard.sql
-- 업데이트 안내가 '무한 루프' 가 되지 않도록 안전장치
--
-- 무슨 일이 있었나
--   학생이 "새 버전이 나왔어요" 를 보고 스토어에 갔는데 '열기' 만 있었다.
--   돌아오면 또 묻고, 또 스토어에 가면 또 '열기'. 되풀이됐다.
--
--   원인은 app_releases.latest_version 이 **스토어에 실제로 풀린 버전보다 앞서** 있어서다.
--   스토어에 올리고 '출시' 를 눌러도 심사·단계적 배포(staged rollout)·전파 때문에
--   모든 학생에게 바로 보이지는 않는다. 그동안 앱은 "새 버전이 있다" 고 믿는다.
--
-- 여기서 막을 수 있는 것과 없는 것
--   · 막을 수 있는 것: min_version 이 latest_version 보다 높아지는 것 (전원 잠김 사고)
--   · 막을 수 없는 것: latest_version 이 스토어보다 앞서는 것
--     (서버는 스토어에 뭐가 풀렸는지 알 수 없다. 사람이 확인하고 올려야 한다)
--
-- 앱 쪽에서는 0.28.2 부터 한 번 닫은 버전은 하루 동안 다시 묻지 않는다.

create or replace function trg_app_releases_guard()
returns trigger
language plpgsql as $$
begin
  if version_num(new.min_version) > version_num(new.latest_version) then
    raise exception
      '최소 지원 버전(%)이 최신 버전(%)보다 높습니다. 이렇게 두면 아직 업데이트하지 못한 사람이 앱을 쓸 수 없습니다. latest_version 을 먼저 올리세요.',
      new.min_version, new.latest_version;
  end if;
  return new;
end $$;

drop trigger if exists app_releases_guard on app_releases;
create trigger app_releases_guard
  before insert or update on app_releases
  for each row execute function trg_app_releases_guard();

-- ═══════════ 지금 상태 보기 ═══════════
--   스토어에 실제로 풀린 버전과 맞는지 눈으로 확인하는 용도.
create or replace function version_gate_status()
returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
           'platform', r.platform,
           'latest_version', r.latest_version,
           'min_version', r.min_version,
           'updated_at', r.updated_at)
         order by r.platform), '[]'::json)
    from app_releases r;
$$;
revoke all on function version_gate_status() from public, anon, authenticated;

-- ═══════════ 확인 ═══════════
--   select version_gate_status();
--
--   스토어보다 앞서 있으면 낮춰 둔다 (예: 스토어에 0.28.0 까지만 풀렸을 때)
--     update app_releases
--        set latest_version = '0.28.0', updated_at = now()
--      where platform = 'android';
--
--   min_version 은 서둘러 올리지 않는 편이 안전하다.
--   서버 변경 때문에 구버전을 반드시 끊어야 할 때만 올린다.
