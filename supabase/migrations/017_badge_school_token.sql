-- 017_badge_school_token.sql
-- 50회 참여 배지 이름을 학교별로 표시하기 위해 '○○인' 토큰으로 변경.
-- 앱이 '○○'를 각 학교 약칭으로 치환한다 (충암중학교 → 충암인, 대광고등학교 → 대광인).
-- 배지는 모든 학교가 공유하는 전역 테이블이므로 이름을 학교에 종속시키지 않는다.

update badges
set name = '○○인'
where condition_type = 'total_checkins' and condition_value = 50;
