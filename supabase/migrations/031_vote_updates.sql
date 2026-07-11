-- 031_vote_updates.sql
-- 수업맛집 보완:
--   1) 라운드에 총 진행 주차(total_weeks) — "3/6주차 진행 중" 표시용
--   2) 라운드 개설 시 '수업' 규칙 필수 (수업맛집은 학교 수업 규칙 기준 투표)
--   3) vote_hint(): 교사·학생 모두 볼 수 있는 재미 힌트
--      — 순위·학급명은 감추고 "1등과 2등의 표차"만 공개 (마감 전 흥미 유지)

-- ── 1) 총 주차 ───────────────────────────────────────────────
alter table vote_rounds
  add column if not exists total_weeks int not null default 5
  check (total_weeks between 1 and 20);

-- ── 2) 개설 조건: '수업' 규칙 존재 (서버 강제) ───────────────
create or replace function public.check_class_rules_before_round()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from school_rules
    where school_id = new.school_id
      and space = '수업'
      and is_active = true
  ) then
    raise exception '수업 규칙을 먼저 설정해주세요. 수업맛집은 우리 학교의 수업 규칙을 기준으로 투표하는 프로그램이에요. (규칙 탭 → 수업)';
  end if;
  return new;
end $$;

drop trigger if exists trg_vote_round_needs_rules on vote_rounds;
create trigger trg_vote_round_needs_rules
  before insert on vote_rounds
  for each row execute function public.check_class_rules_before_round();

-- ── 3) 재미 힌트 (교사·학생 공용, 학급명 비공개) ─────────────
create or replace function public.vote_hint()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_school uuid := current_profile_school();
  v_round vote_rounds;
  v_week_now int;
  v_grades jsonb;
begin
  if v_school is null then
    raise exception '로그인이 필요해요.';
  end if;

  select * into v_round from vote_rounds
    where school_id = v_school and status = 'open'
    order by created_at desc limit 1;
  if v_round is null then
    return jsonb_build_object('has_round', false);
  end if;

  -- 시작일 기준 몇 주차인지 (KST, 1부터 시작, 총 주차로 클램프)
  v_week_now := least(
    greatest(
      (((now() at time zone 'Asia/Seoul')::date
        - (v_round.created_at at time zone 'Asia/Seoul')::date) / 7) + 1,
      1),
    v_round.total_weeks);

  -- 학년별 1위·2위 득표수만 (학급명은 비공개)
  select coalesce(jsonb_agg(g order by g->'grade'), '[]'::jsonb) into v_grades
  from (
    select jsonb_build_object(
      'grade', t.grade,
      'top', max(t.votes),
      'second', coalesce(
        (array_agg(t.votes order by t.votes desc))[2], 0),
      'classes', count(*)
    ) as g
    from (
      select cv.grade, cv.class_num, count(*)::int as votes
      from class_votes cv
      where cv.round_id = v_round.id
      group by cv.grade, cv.class_num
    ) t
    group by t.grade
  ) s;

  return jsonb_build_object(
    'has_round', true,
    'title', v_round.title,
    'votes_per_week', v_round.votes_per_week,
    'week_now', v_week_now,
    'total_weeks', v_round.total_weeks,
    'grades', v_grades
  );
end $$;
revoke all on function public.vote_hint() from public;
grant execute on function public.vote_hint() to authenticated;
