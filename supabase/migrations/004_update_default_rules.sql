-- 004_update_default_rules.sql
-- Replace default rule template with the finalized 충암중 rule set
-- and refresh all existing schools' rules.

-- 1) Update the seed function
create or replace function seed_default_rules(p_school_id uuid)
returns void language plpgsql security definer as $$
begin
  insert into school_rules (school_id, space, category, rule_text, order_index) values
    -- 수업 (수업3끝)
    (p_school_id, '수업', '수업3끝', '입실끝: 8:25까지 교실에 들어왔어요', 1),
    (p_school_id, '수업', '수업3끝', '준비끝: 타종 후 교과서를 펼치고 자리에 앉았어요', 2),
    (p_school_id, '수업', '수업3끝', '수행끝: 선생님이 과제를 주시면 3초 안에 시작하고 약속한 시간까지 과제를 수행했어요', 3),
    -- 교실
    (p_school_id, '교실', 'M예의', '친구를 이름으로 불렀어요', 4),
    (p_school_id, '교실', 'R책임', '수업시간에 음식물을 섭취하지 않았어요', 5),
    (p_school_id, '교실', 'S안전', '창문 밖으로 손·발·물건을 내밀지 않았어요', 6),
    -- 복도
    (p_school_id, '복도', 'M예의', '복도에서 어른을 만나면 인사했어요', 7),
    (p_school_id, '복도', 'R책임', '복도 오른쪽으로 걸었어요', 8),
    (p_school_id, '복도', 'S안전', '복도와 계단에서 걸어 다녔어요', 9),
    -- 급식실
    (p_school_id, '급식실', 'M예의', '음식을 다 삼킨 후에 말했어요', 10),
    (p_school_id, '급식실', 'R책임', '배식 줄 맨 뒤에서 기다렸어요', 11),
    (p_school_id, '급식실', 'S안전', '식판은 두 손으로 잡고 이동했어요', 12),
    -- 화장실
    (p_school_id, '화장실', 'M예의', '칸에 들어가기 전에 노크했어요', 13),
    (p_school_id, '화장실', 'R책임', '사용한 휴지를 휴지통에 버렸어요', 14),
    (p_school_id, '화장실', 'S안전', '변기 물을 끝까지 내렸어요', 15);
end;
$$;

-- 2) Clear existing rules + dependent checkins
-- (daily_checkins.answers references rule_ids; rules are about to change)
delete from daily_checkins;
delete from school_rules;

-- 3) Re-seed all existing schools with the new rule set
do $$
declare
  s record;
begin
  for s in select id from schools loop
    perform seed_default_rules(s.id);
  end loop;
end;
$$;
