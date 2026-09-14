-- 056_weekly_honor_gardener.sql
-- 이 주의 명예 식집사 — 반마다 한 명, 실시간.
--
-- 왜
--   명예의 전당은 한 달 단위라 한 번 정해지면 거의 안 바뀐다. 학생 입장에서는
--   "이번 달은 이미 끝났다" 가 되기 쉽다. 일주일 단위로 끊고, 앱을 열 때마다
--   그 순간의 점수로 다시 계산하면 월요일마다 모두에게 기회가 새로 생긴다.
--
-- 점수 (100점 만점, 이번 주 월요일부터)
--   꾸준함  40  이번 주 '지금까지의 수업일' 중 점검한 날의 비율
--              월요일 아침 첫 점검이면 1/1 = 40점. 휴일이 낀 주도 불리하지 않다.
--   실천    30  이번 주 자기점검 O/X 평균 점수 × 0.3
--   칭찬    30  이번 주 받은 칭찬 1회당 10점, 3회까지
--              한 학생이 칭찬을 몰아 받아도 점검을 안 하면 못 이긴다.
--
--   이번 주에 한 번이라도 점검한 학생만 후보다. '식집사' 는 매일 돌보는 사람이다.
--
-- 동점
--   만점 가까이에 동점이 자주 나온다. 칭찬 → 점검일수 → 평균점수 순으로 가르고,
--   그래도 같으면 '이번 주 안에서만 고정된' 무작위로 정한다.
--   random() 을 쓰면 새로고침할 때마다 1위가 바뀌어 보인다.
--
-- 개인정보
--   이름 가운데를 서버에서 가려서 보낸다. 앱에서 가리면 네트워크 응답에는
--   실명이 그대로 담겨, 마음먹은 학생은 다른 반 친구 실명을 볼 수 있다.

-- ═══════════ 1) 이름 가리기 ═══════════
--   김민수 → 김*수 · 이서 → 이* · 남궁민수 → 남**수
create or replace function mask_name(p_name text)
returns text
language sql immutable set search_path = public as $$
  select case
    when p_name is null or btrim(p_name) = '' then ''
    when char_length(btrim(p_name)) = 1 then btrim(p_name)
    when char_length(btrim(p_name)) = 2 then left(btrim(p_name), 1) || '*'
    else left(btrim(p_name), 1)
         || repeat('*', char_length(btrim(p_name)) - 2)
         || right(btrim(p_name), 1)
  end;
$$;

-- ═══════════ 2) 한 주의 순위 (내부용) ═══════════
create or replace function weekly_honor_rank(p_school uuid, p_week_start date)
returns table (
  user_id uuid,
  grade int,
  class_num int,
  nickname text,
  days_done int,
  avg_pct int,
  praise_cnt int,
  score int,
  rn int
)
language sql stable security definer set search_path = public, auth as $$
  with bounds as (
    select p_week_start as ws,
           least((now() at time zone 'Asia/Seoul')::date, p_week_start + 4) as upto
  ),
  -- 이번 주 '지금까지' 의 수업일 수 (월~금 중 오늘까지)
  school_days as (
    select count(*)::int as n
      from bounds b,
           generate_series(b.ws, b.upto, interval '1 day') d
     where d::date <= b.upto
       and is_school_day(p_school, d::date)
  ),
  ck as (
    select d.user_id,
           count(distinct d.checkin_date)::int as days_done,
           round(avg(d.score_pct))::int       as avg_pct
      from daily_checkins d, bounds b
     where d.school_id = p_school
       and d.checkin_date between b.ws and b.ws + 6
       -- 048 이전 날짜 조작으로 남은 주말 기록은 세지 않는다
       and is_school_day(p_school, d.checkin_date)
     group by d.user_id
  ),
  pr as (
    select pz.student_id as user_id, count(*)::int as praise_cnt
      from praise pz, bounds b
     where pz.school_id = p_school
       and pz.created_at >= (b.ws::timestamp at time zone 'Asia/Seoul')
       and pz.created_at <  ((b.ws + 7)::timestamp at time zone 'Asia/Seoul')
     group by pz.student_id
  ),
  scored as (
    select p.user_id, p.grade, p.class_num, p.nickname,
           ck.days_done, ck.avg_pct,
           coalesce(pr.praise_cnt, 0) as praise_cnt,
           ( case when sd.n > 0
                  then round(least(ck.days_done, sd.n)::numeric / sd.n * 40)
                  else 0 end
           + round(coalesce(ck.avg_pct, 0) * 0.3)
           + least(coalesce(pr.praise_cnt, 0), 3) * 10
           )::int as score
      from profiles p
      join ck on ck.user_id = p.user_id
      left join pr on pr.user_id = p.user_id
      cross join school_days sd
     where p.school_id = p_school
       and p.role = 'student'
       and p.left_at is null
       and p.grade is not null and p.class_num is not null
       and ck.days_done >= 1
  )
  select s.user_id, s.grade, s.class_num, s.nickname,
         s.days_done, s.avg_pct, s.praise_cnt, s.score,
         (row_number() over (
            partition by s.grade, s.class_num
            order by s.score desc, s.praise_cnt desc, s.days_done desc,
                     s.avg_pct desc,
                     md5(s.user_id::text || p_week_start::text)))::int as rn
    from scored s;
$$;
revoke all on function weekly_honor_rank(uuid, date) from public, anon, authenticated;

-- ═══════════ 3) 학생 화면용 — 반별 1위, 이름은 가려서 ═══════════
create or replace function weekly_honor_gardeners()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_this date := date_trunc('week', v_today)::date;   -- 이번 주 월요일
  v_week date;
  v_which text;
  v_items json;
begin
  if v_school is null then
    return json_build_object('ok', false);
  end if;

  -- 이번 주에 아직 아무도 점검하지 않았으면 (월요일 새벽, 휴일 주간)
  -- 빈 배너 대신 지난주 최종 결과를 보여준다.
  if exists (select 1 from weekly_honor_rank(v_school, v_this) where rn = 1) then
    v_week := v_this; v_which := 'this';
  else
    v_week := v_this - 7; v_which := 'last';
  end if;

  select coalesce(json_agg(json_build_object(
           'label', r.grade || '-' || r.class_num || ' ' || mask_name(r.nickname),
           'grade', r.grade,
           'class_num', r.class_num,
           'is_me', r.user_id = auth.uid())
         order by r.grade, r.class_num), '[]'::json)
    into v_items
    from weekly_honor_rank(v_school, v_week) r
   where r.rn = 1;

  return json_build_object(
    'ok', true,
    'week', v_which,
    'week_start', v_week,
    'items', v_items);
end $$;
grant execute on function weekly_honor_gardeners() to authenticated;

-- ═══════════ 4) 내 점수 — 본인에게만 ═══════════
--   "우리 반 1위까지 몇 점?" 을 알아야 이번 주에 뭘 더 할지 보인다.
--   다른 학생의 점수는 주지 않는다.
create or replace function my_weekly_honor()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  v_this date := date_trunc('week', (now() at time zone 'Asia/Seoul')::date)::date;
  v_me record;
  v_top int;
begin
  if v_school is null then
    return json_build_object('ok', false);
  end if;

  select * into v_me
    from weekly_honor_rank(v_school, v_this) r
   where r.user_id = auth.uid();

  -- 이번 주에 아직 점검하지 않았으면 후보가 아니다
  if not found then
    return json_build_object('ok', true, 'joined', false);
  end if;

  select r.score into v_top
    from weekly_honor_rank(v_school, v_this) r
   where r.grade = v_me.grade and r.class_num = v_me.class_num and r.rn = 1;

  return json_build_object(
    'ok', true,
    'joined', true,
    'score', v_me.score,
    'rank', v_me.rn,
    'days_done', v_me.days_done,
    'avg_pct', v_me.avg_pct,
    'praise_cnt', v_me.praise_cnt,
    'gap', greatest(0, coalesce(v_top, 0) - v_me.score),
    'is_top', v_me.rn = 1);
end $$;
grant execute on function my_weekly_honor() to authenticated;

-- ═══════════ 5) 확인 ═══════════
--   (SQL 에디터는 로그인 사용자가 없어 weekly_honor_gardeners() 가 비어 보인다.
--    학교 id 를 넣어 내부 함수로 확인)
--   select grade, class_num, mask_name(nickname), score, days_done, avg_pct, praise_cnt
--     from weekly_honor_rank('<school_id>', date_trunc('week', now())::date)
--    where rn = 1 order by grade, class_num;
