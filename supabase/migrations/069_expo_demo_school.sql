-- 069_expo_demo_school.sql
-- 교육 엑스포 체험 부스용 '체험 학교'
--
-- 왜 따로 학교를 만드나
--   체험용 계정을 충암중 안에 만들면 충암중 통계·명예의 전당·학교 새싹에 섞인다.
--   자람은 모든 데이터를 학교 단위로 나누므로, 체험 학교를 따로 두면 서로 절대 섞이지 않는다.
--
-- 체험 학교만 다르게 동작하는 것
--   · 매일이 수업일이고, 자기점검·칭찬 우체통이 하루 종일 열린다 (주말·오전 부스 대비)
--   · 선생님 화면의 '체험 초기화' 한 번으로 모든 기록을 지우고 예시 데이터를 다시 채운다
--     → 다음 관람객이 처음부터 점검·칭찬·교환을 해볼 수 있다
--   · 체험용 계정은 탈퇴할 수 없다 (관람객이 실수로 누르는 것 방지)
--   · 전국 학교 순위에 나오지 않는다
--
-- 안전장치
--   · 초기화는 is_demo = true 인 학교에서만 동작한다. 충암중에는 아무 일도 하지 않는다.
--   · 학생이 10명 넘는 학교는 체험 학교로 바꿀 수 없다 (운영 중인 학교를 실수로 바꾸는 것 방지)

alter table schools add column if not exists is_demo boolean not null default false;

-- ═══════════ 1) 체험 학교는 매일이 수업일 ═══════════
--   본문은 039 와 같고 맨 앞에 체험 학교 조건만 더했다.
create or replace function is_school_day(p_school uuid, p_date date)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select s.is_demo from schools s where s.id = p_school), false)
      or (
        -- 토(6)·일(7) 제외
        extract(isodow from p_date) between 1 and 5
        -- 공휴일 제외
        and not exists (select 1 from public_holidays h where h.holiday_date = p_date)
        -- 학교 휴업일 제외
        and not exists (
          select 1 from school_closures c
           where c.school_id = p_school
             and p_date between c.start_date and c.end_date
        )
      );
$$;
grant execute on function is_school_day(uuid, date) to authenticated;

-- ═══════════ 2) 전국 학교 순위에서 빼기 ═══════════
--   본문은 005 와 같고 마지막에 체험 학교 제외만 더했다.
create or replace view school_leaderboard as
select
  s.id,
  s.name,
  s.region,
  s.level,
  coalesce(stu.student_count, 0) as student_count,
  coalesce(ch.checkin_count_30d, 0) as checkin_count_30d,
  coalesce(ch.participants_30d, 0) as participants_30d,
  coalesce(ch.avg_score_30d, 0)::float as avg_score_30d,
  case
    when coalesce(stu.student_count, 0) = 0 then 0
    else round(
      (coalesce(ch.checkin_count_30d, 0)::numeric
        / nullif(stu.student_count * 30, 0))
      * coalesce(ch.avg_score_30d, 0)
      * 10
    )::int
  end as school_score
from schools s
left join lateral (
  select count(*)::int as student_count
  from profiles p
  where p.school_id = s.id and p.role = 'student'
) stu on true
left join lateral (
  select
    count(*)::int as checkin_count_30d,
    count(distinct user_id)::int as participants_30d,
    avg(score_pct)::numeric as avg_score_30d
  from daily_checkins
  where school_id = s.id
    and checkin_date >= current_date - interval '30 days'
) ch on true
where not s.is_demo;

grant select on school_leaderboard to authenticated, anon;

-- ═══════════ 3) 체험용 계정은 탈퇴 불가 ═══════════
--   본문은 068 과 같고 체험 학교 확인만 더했다.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception '로그인 상태가 아닙니다.';
  end if;

  if exists (select 1 from profiles p join schools s on s.id = p.school_id
              where p.user_id = uid and s.is_demo) then
    raise exception '체험용 계정은 탈퇴할 수 없어요.';
  end if;

  update student_roster
     set claimed = false, claimed_by = null
   where claimed_by = uid;

  delete from auth.users where id = uid;
end;
$$;
revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- ═══════════ 4) 체험 초기화 ═══════════
--   p_scope
--     'class' (기본) — 누른 선생님의 담임 반만. 부스 세트 하나만 처음으로 돌아가고
--                     다른 세트에서 체험 중인 관람객 기록은 그대로 둔다.
--     'all'          — 학교 전체. 준비할 때, 또는 SQL 에디터에서.
--                     (담임 반이 없는 선생님이 누르거나 SQL 에디터에서 부르면 자동으로 전체)
--
--   그 반 학생마다 지우고 다시 채우는 것
--     · 최근 14일 자기점검 (학생마다 다르게 → 연속 참여 14일 · 5일 · 2일)
--     · 담임 선생님 칭찬 2개
--     · 반의 '함께 키우기' 1개 (600P 모인 상태)
--     · (선택) 세 번째 학생의 K-ODR 5건 → CICO 권장 · 학맞통 안건이 자동으로 생긴다
--   학교 전체일 때만: 강화물 4개, 환영 공지, 투표·명예 식집사·교사 라운지 기록
--   오늘 기록은 비워 두므로 관람객이 바로 오늘 점검을 해볼 수 있다.
--
--   앱(선생님): rpc('reset_demo_school')                       ← 우리 반
--               rpc('reset_demo_school', {p_scope: 'all'})     ← 학교 전체
--   SQL 에디터:  select reset_demo_school('<학교 id>');          ← 학교 전체
drop function if exists reset_demo_school(uuid, boolean);
create or replace function reset_demo_school(
  p_school uuid default null,
  p_with_kodr boolean default true,
  p_scope text default 'class'
)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_my_grade int;
  v_my_class int;
  v_school uuid;
  v_scope text := coalesce(p_scope, 'class');
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_all uuid[];
  v_targets uuid[];
  v_teachers uuid[];
  v_teacher uuid;
  v_teacher_name text;
  s record;
  r record;
  d date;
  v_rate int;
  v_ok boolean;
  v_answers jsonb;
  v_total int;
  v_possible int;
  v_cats jsonb;
  v_ts timestamptz;
  v_praise_id uuid;
  v_praise_pts int;
  v_item_id uuid;
  v_checkins int := 0;
  v_students int := 0;
  v_note text := null;
begin
  -- ── 누가 어느 학교를 ──
  if v_uid is not null then
    select school_id, role, grade, class_num
      into v_school, v_role, v_my_grade, v_my_class
      from profiles where user_id = v_uid;
    if v_role is distinct from 'teacher' then
      return json_build_object('ok', false, 'error', '선생님만 초기화할 수 있어요');
    end if;
    if p_school is not null and p_school is distinct from v_school then
      return json_build_object('ok', false, 'error', '우리 학교만 초기화할 수 있어요');
    end if;
  else
    v_school := p_school;   -- SQL 에디터에서 학교를 지정
  end if;

  -- ── 핵심 안전장치: 체험 학교가 아니면 아무것도 하지 않는다 ──
  if v_school is null
     or not coalesce((select is_demo from schools where id = v_school), false) then
    return json_build_object('ok', false, 'error', '체험용 학교에서만 초기화할 수 있어요');
  end if;

  if v_scope not in ('class', 'all') then
    v_scope := 'class';
  end if;
  if v_scope = 'class' and (v_my_grade is null or v_my_class is null) then
    v_scope := 'all';   -- 담임 반이 없으면 (SQL 에디터 포함) 학교 전체
  end if;

  -- 두 태블릿에서 동시에 눌러도 차례로
  perform pg_advisory_xact_lock(hashtextextended('demo_reset:' || v_school::text, 0));

  select coalesce(array_agg(user_id), '{}') into v_all
    from profiles where school_id = v_school;
  select coalesce(array_agg(user_id order by created_at), '{}') into v_teachers
    from profiles where school_id = v_school and role = 'teacher';
  select coalesce(array_agg(user_id), '{}') into v_targets
    from profiles
   where school_id = v_school and role = 'student' and left_at is null
     and (v_scope = 'all' or (grade = v_my_grade and class_num = v_my_class));

  -- ── 1. 이 학생들의 기록 지우기 ──
  delete from point_exchanges where school_id = v_school and user_id = any(v_targets);
  delete from group_contributions where school_id = v_school and user_id = any(v_targets);
  delete from point_transactions where school_id = v_school and user_id = any(v_targets);
  delete from daily_checkins where school_id = v_school and user_id = any(v_targets);
  delete from checkin_streaks where user_id = any(v_targets);
  delete from checkin_semester_summary where user_id = any(v_targets);
  delete from praise where school_id = v_school and student_id = any(v_targets);
  delete from praise_mail
   where school_id = v_school
     and (sender_id = any(v_targets) or recipient_id = any(v_targets));
  delete from support_referrals where school_id = v_school and student_id = any(v_targets);
  delete from kodr_tier_alerts where school_id = v_school and student_id = any(v_targets);
  delete from kodr_records where school_id = v_school and student_id = any(v_targets);
  delete from cico_enrollments where school_id = v_school and student_id = any(v_targets);
  delete from quiz_attempts where school_id = v_school and user_id = any(v_targets);
  delete from notifications where school_id = v_school and target_user_id = any(v_targets);
  delete from user_badges where user_id = any(v_targets);
  delete from growth_level_seen where school_id = v_school and user_id = any(v_targets);

  if v_scope = 'class' then
    -- 이 반의 알림 · 함께 키우기 · 누른 선생님의 퀴즈와 새싹 팝업
    delete from notifications
     where school_id = v_school and audience = 'class'
       and grade = v_my_grade and class_num = v_my_class;
    delete from point_store_items
     where school_id = v_school and item_type = 'group'
       and grade = v_my_grade and class_num = v_my_class;
    delete from quiz_attempts where school_id = v_school and user_id = v_uid;
    delete from growth_level_seen where school_id = v_school and user_id = v_uid;
  else
    -- 학교 전체
    delete from point_exchanges where school_id = v_school;
    delete from group_contributions where school_id = v_school;
    delete from point_store_items where school_id = v_school;
    delete from point_transactions where school_id = v_school;
    delete from notifications where school_id = v_school;
    delete from quiz_attempts where school_id = v_school;
    delete from user_badges where user_id = any(v_all);
    delete from growth_level_seen where school_id = v_school;
    delete from checkin_school_daily where school_id = v_school;
    delete from checkin_rule_semester_stats where school_id = v_school;
    delete from school_growth_year where school_id = v_school;
    delete from honor_gardener where school_id = v_school;
    delete from rule_suggestions where school_id = v_school;
    delete from class_votes where school_id = v_school;
    delete from teacher_exchanges where school_id = v_school;
    delete from teacher_point_transactions where school_id = v_school;
    delete from announcements where school_id = v_school;
    delete from school_point_rules where school_id = v_school;   -- 포인트는 기본값으로
    update schools set notified_growth_level = 0 where id = v_school;
  end if;

  -- 새싹 · 명예 식집사 숫자는 다시 계산되게
  delete from school_growth_cache where school_id = v_school;
  delete from weekly_honor_cache where school_id = v_school;

  -- ── 2. 학교 전체일 때만: 강화물 4개 · 환영 공지 ──
  if v_scope = 'all' then
    select nickname into v_teacher_name from profiles where user_id = v_teachers[1];
    insert into point_store_items
      (school_id, name, description, cost_points, stock, is_active, order_index,
       emoji, grade, class_num, created_by, created_by_name, item_type)
    values
      (v_school, '점심시간 신청곡', '방송실에서 내가 고른 노래 한 곡', 200, null, true, 1, '🎵', null, null, v_teachers[1], v_teacher_name, 'individual'),
      (v_school, '간식 교환권',     '매점 간식 하나',               300, null, true, 2, '🍭', null, null, v_teachers[1], v_teacher_name, 'individual'),
      (v_school, '예쁜 문구 세트',   '볼펜 · 메모지 세트',            500, 20,   true, 3, '✏️', null, null, v_teachers[1], v_teacher_name, 'individual'),
      (v_school, '원하는 자리 앉기', '하루 동안 원하는 자리에 앉기',   800, null, true, 4, '🪑', null, null, v_teachers[1], v_teacher_name, 'individual');

    insert into announcements (school_id, title, body, created_by)
    values (v_school, '🌱 자람 체험에 오신 걸 환영해요',
            '오늘의 자기점검을 해보고, 친구에게 칭찬 편지도 보내보세요. '
            || '모은 포인트로 교환소에서 강화물을 신청할 수 있어요!',
            v_teachers[1]);
  end if;

  -- ── 3. 학생마다 예시 기록 ──
  --   학교에서 몇 번째 학생인지(1·2·3반 순)로 모습을 정한다. 반 하나만 초기화해도
  --   그 학생은 늘 같은 모습으로 돌아온다.
  for s in
    select x.user_id, x.grade, x.class_num, x.idx
      from (
        select p.user_id, p.grade, p.class_num,
               row_number() over (
                 order by p.grade, p.class_num, p.student_num nulls last, p.created_at
               )::int as idx
          from profiles p
         where p.school_id = v_school and p.role = 'student' and p.left_at is null
      ) x
     where x.user_id = any(v_targets)
     order by x.idx
  loop
    v_students := v_students + 1;
    -- 꾸준한 학생 / 한 번 빠진 학생 / 들쭉날쭉한 학생
    v_rate := case s.idx when 1 then 92 when 2 then 82 else 68 end;

    -- 3-1. 최근 14일 자기점검
    for d in
      select g::date from generate_series(v_today - 14, v_today - 1, interval '1 day') g
    loop
      if (s.idx = 2 and d = v_today - 6)
         or (s.idx >= 3 and d in (v_today - 3, v_today - 9)) then
        continue;
      end if;

      v_answers := '{}'::jsonb; v_total := 0; v_possible := 0;
      for r in
        select sr.id from school_rules sr
         where sr.school_id = v_school and sr.is_active
         order by sr.order_index
      loop
        v_possible := v_possible + 1;
        -- 매번 같은 결과가 나오도록 해시로 정한다 (hashtext 는 음수도 나오므로 두 번 나눈다)
        v_ok := ((hashtext(r.id::text || d::text || s.user_id::text)::bigint % 100) + 100) % 100
                < v_rate;
        if v_ok then v_total := v_total + 1; end if;
        v_answers := v_answers || jsonb_build_object(r.id::text, v_ok);
      end loop;
      if v_possible = 0 then
        continue;   -- 규칙이 없으면 점검도 만들지 않는다
      end if;

      select coalesce(jsonb_object_agg(t.category, t.avg_pct), '{}'::jsonb) into v_cats
        from (
          select sr.category,
                 avg(case when v_answers ->> sr.id::text = 'true' then 100.0 else 0.0 end) as avg_pct
            from school_rules sr
           where sr.school_id = v_school and sr.is_active
             and v_answers ? sr.id::text
           group by sr.category
        ) t;

      v_ts := ((d::timestamp + time '15:40') at time zone 'Asia/Seoul');
      insert into daily_checkins
        (user_id, school_id, checkin_date, answers, total_score, total_possible,
         score_pct, category_scores, created_at, updated_at)
      values
        (s.user_id, v_school, d, v_answers, v_total, v_possible,
         (v_total::float / v_possible) * 100.0, v_cats, v_ts, v_ts);
      v_checkins := v_checkins + 1;

      -- 포인트 (실제와 같은 함수로 — 주간 개근 보너스도 붙는다)
      perform award_checkin_points_internal(s.user_id, v_school, d);
      update point_transactions
         set created_at = v_ts
       where user_id = s.user_id and school_id = v_school
         and period_key = to_char(d, 'YYYY-MM-DD') and reason = 'checkin_daily';
    end loop;

    -- 이 학생의 담임 선생님 (없으면 처음 가입한 선생님)
    select p.user_id, p.nickname into v_teacher, v_teacher_name
      from profiles p
     where p.school_id = v_school and p.role = 'teacher'
       and p.grade = s.grade and p.class_num = s.class_num
     order by p.created_at
     limit 1;
    if v_teacher is null and array_length(v_teachers, 1) is not null then
      v_teacher := v_teachers[1];
      select nickname into v_teacher_name from profiles where user_id = v_teacher;
    end if;

    -- 3-2. 선생님 칭찬 2개
    if v_teacher is not null then
      v_praise_pts := point_amount(v_school, 'praise');
      for r in
        select * from (values
          (8, '급식실에서 차례를 잘 지키고 친구에게 먼저 양보했어요.'),
          (2, '수업 준비를 꼼꼼히 해 와서 모둠 활동이 순조로웠어요.')
        ) as x(ago, msg)
      loop
        v_ts := (((v_today - r.ago)::timestamp + time '12:20') at time zone 'Asia/Seoul');
        insert into praise (school_id, teacher_id, student_id, message, created_at)
        values (v_school, v_teacher, s.user_id, r.msg, v_ts)
        returning id into v_praise_id;
        if v_praise_pts > 0 then
          insert into point_transactions
            (user_id, school_id, amount, reason, period_key, description, created_at)
          values
            (s.user_id, v_school, v_praise_pts, 'praise', v_praise_id::text, '교사 칭찬', v_ts);
        end if;
      end loop;
    end if;

    -- 3-3. 반의 '함께 키우기' (600P 모인 상태)
    if s.grade is not null and s.class_num is not null
       and not exists (select 1 from point_store_items i
                        where i.school_id = v_school and i.item_type = 'group'
                          and i.grade = s.grade and i.class_num = s.class_num) then
      insert into point_store_items
        (school_id, name, description, cost_points, stock, is_active, order_index,
         emoji, grade, class_num, created_by, created_by_name, item_type)
      values
        (v_school, '우리 반 간식 파티', '반 친구들이 포인트를 모아 다 함께!', 2000, null, true, 10,
         '🍕', s.grade, s.class_num, v_teacher, v_teacher_name, 'group')
      returning id into v_item_id;

      insert into group_contributions (item_id, user_id, school_id, amount)
      values (v_item_id, s.user_id, v_school, 600);
      insert into point_transactions
        (user_id, school_id, amount, reason, period_key, description)
      values
        (s.user_id, v_school, -600, 'group_contribute',
         v_item_id::text || ':' || gen_random_uuid()::text, '함께 키우기: 우리 반 간식 파티');
    end if;

    -- 3-4. (선택) 세 번째 학생의 K-ODR → CICO · 학맞통 연계
    --   기록이 저장되면 059 의 판정이 돌아 CICO 권장 알림과 학맞통 안건이 자동으로 생긴다.
    --   실패해도 초기화는 계속한다.
    if p_with_kodr and s.idx = 3 and v_teacher is not null then
      begin
        for r in
          select * from (values
            (18, '교실', '수업 준비물 미지참'),
            (12, '교실', '잡담·수업 무관한 말'),
            (8,  '복도', '수업시간 큰 소리로 말하기'),
            (5,  '교실', '디지털 기기 사용'),
            (2,  '교실', '과제 비참여')
          ) as x(ago, place, behavior)
        loop
          insert into kodr_records
            (school_id, student_id, teacher_id, occurred_date, place, behavior,
             author_role, created_at)
          values
            (v_school, s.user_id, v_teacher, v_today - r.ago, r.place, r.behavior,
             '담임교사',
             (((v_today - r.ago)::timestamp + time '11:00') at time zone 'Asia/Seoul'));
        end loop;
      exception when others then
        v_note := 'K-ODR 예시는 건너뛰었어요: ' || sqlerrm;
      end;
    end if;

    v_teacher := null;
    v_teacher_name := null;
  end loop;

  return json_build_object(
    'ok', true,
    'scope', v_scope,
    'class', case when v_scope = 'class' then v_my_grade || '-' || v_my_class end,
    'students', v_students,
    'teachers', coalesce(array_length(v_teachers, 1), 0),
    'checkins_seeded', v_checkins,
    'note', v_note);
end $$;
revoke all on function reset_demo_school(uuid, boolean, text) from public, anon;
grant execute on function reset_demo_school(uuid, boolean, text) to authenticated;

-- ═══════════ 5) 체험 학교 준비 (SQL 에디터에서 한 번) ═══════════
--   · 체험 학교로 표시, 결제 상태 활성, 점검 시간 0시
--   · 명렬표 3명 (1학년 1·2·3반 1번) — PIN 을 돌려준다
--   · 가입한 선생님을 가입 순서대로 1·2·3반 담임으로, 모두 관리자로
--   · 예시 데이터 채우기
--   선생님·학생이 모두 가입한 뒤 한 번 더 실행하면 담임 배정과 예시 데이터가 완성된다.
create or replace function setup_demo_school(p_school uuid)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_name text;
  r record;
  i int := 0;
  v_pins json;
  v_reset json;
begin
  select name into v_name from schools where id = p_school;
  if v_name is null then
    return json_build_object('ok', false, 'error', '학교를 찾을 수 없어요');
  end if;
  if (select count(*) from profiles where school_id = p_school and role = 'student') > 10 then
    return json_build_object('ok', false,
      'error', '학생이 10명 넘는 학교는 체험 학교로 바꿀 수 없어요 (운영 중인 학교일 수 있어요)');
  end if;

  update schools
     set is_demo = true,
         subscription_status = 'active',
         subscription_expires_at = current_date + 365,
         auto_renew = false,
         checkin_open_time = time '00:00'
   where id = p_school;

  insert into student_roster (school_id, grade, class_num, student_num, name, pin)
  values
    (p_school, 1, 1, 1, '김새싹', lpad((floor(random() * 10000))::int::text, 4, '0')),
    (p_school, 1, 2, 1, '이꽃잎', lpad((floor(random() * 10000))::int::text, 4, '0')),
    (p_school, 1, 3, 1, '박열매', lpad((floor(random() * 10000))::int::text, 4, '0'))
  on conflict (school_id, grade, class_num, student_num) do nothing;

  -- 선생님: 가입 순서대로 1·2·3반 담임, 모두 관리자
  for r in
    select id from profiles
     where school_id = p_school and role = 'teacher'
     order by created_at
  loop
    i := i + 1;
    update profiles
       set teacher_role = 'admin',
           grade = case when i <= 3 then 1 else grade end,
           class_num = case when i <= 3 then i else class_num end
     where id = r.id;
  end loop;

  select json_agg(json_build_object(
           'student', grade || '학년 ' || class_num || '반 ' || student_num || '번 ' || name,
           'pin', pin, 'joined', claimed)
         order by grade, class_num, student_num)
    into v_pins
    from student_roster where school_id = p_school;

  v_reset := reset_demo_school(p_school, true, 'all');

  return json_build_object(
    'ok', true,
    'school', v_name,
    'teachers', i,
    'roster', v_pins,
    'reset', v_reset);
end $$;
revoke all on function setup_demo_school(uuid) from public, anon, authenticated;

-- ═══════════ 확인 ═══════════
--   select id, name, is_demo, checkin_open_time from schools where is_demo;
