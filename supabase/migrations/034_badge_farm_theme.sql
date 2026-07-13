-- 034_badge_farm_theme.sql
-- 뱃지 농장 테마 개편: 이름·설명·이모지를 "새싹 키우기" 세계관으로 통일.
--   · id·조건은 유지 → 학생들이 이미 획득한 뱃지(user_badges) 그대로 보존
--   · 신규: 단골 농부(누적10) + 첫 수확/수확왕(보상 교환 1/5회)

-- ── 1) 기존 뱃지 리네이밍 (조건으로 매칭) ────────────────────
update badges set name='첫 씨앗',           description='첫 점검으로 우리 학교 밭에 씨앗을 심었어요!', icon_emoji='🌰' where condition_type='first_checkin';
update badges set name='물주기 3일차',       description='3일 연속 참여 — 새싹이 시원하게 목을 축였어요!', icon_emoji='💧' where condition_type='streak_3';
update badges set name='7일 연속 물주기',    description='일주일 내내 참여! 뿌리가 튼튼해졌어요',        icon_emoji='🚿' where condition_type='streak_7';
update badges set name='한 달 풀케어 식집사', description='30일 연속 돌봄 — 프로 식집사 인정!',           icon_emoji='🪴' where condition_type='streak_30';
update badges set name='반짝반짝 만점 잎',    description='오늘 100점! 잎이 반짝반짝 빛나요',             icon_emoji='✨' where condition_type='perfect_score';
update badges set name='주간 성실 농부',     description='월~금 모두 참여한 성실 농부!',                 icon_emoji='🧑‍🌾' where condition_type='full_week';
update badges set name='○○ 대표 식집사',    description='누적 50회 참여 — 우리 학교 대표 식집사!',       icon_emoji='🎖️' where condition_type='total_checkins' and condition_value=50;

-- 칭찬 계열 (식물 성장 스토리로)
update badges set name='칭찬 씨앗',   description='선생님의 첫 칭찬 — 마음에 씨앗이 심겼어요',   icon_emoji='🌱' where condition_type='praise_count' and condition_value=1;
update badges set name='자라는 중',   description='칭찬 3회 — 무럭무럭 자라는 중!',            icon_emoji='🌿' where condition_type='praise_count' and condition_value=3;
update badges set name='활짝 폈어요', description='칭찬 5회 — 꽃이 활짝 피었어요!',            icon_emoji='🌸' where condition_type='praise_count' and condition_value=5;
update badges set name='우뚝 섰어요', description='칭찬 10회 — 나무처럼 우뚝!',               icon_emoji='🌳' where condition_type='praise_count' and condition_value=10;
update badges set name='칭찬 열매 스타', description='칭찬 20회 — 주렁주렁 열매 맺는 스타!',     icon_emoji='🍎' where condition_type='praise_count' and condition_value=20;

-- ── 2) 신규 뱃지 ─────────────────────────────────────────────
insert into badges (name, description, icon_emoji, condition_type, condition_value)
select * from (values
  ('단골 농부',   '누적 10회 참여 — 밭에 자주 들르는 단골!', '🧺', 'total_checkins', 10),
  ('첫 수확',     '모은 포인트로 첫 보상을 수확했어요!',      '🍓', 'exchange_count', 1),
  ('수확왕',      '보상 5회 수확 — 부지런한 수확왕!',        '🌽', 'exchange_count', 5)
) as v(name, description, icon_emoji, condition_type, condition_value)
where not exists (
  select 1 from badges b
  where b.condition_type = v.condition_type
    and b.condition_value = v.condition_value
);
