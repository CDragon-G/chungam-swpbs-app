-- 078_demo_reset_admin_only.sql
-- 체험 학교 초기화(reset_demo_school)를 관리자 선생님만 할 수 있게 한다.
--
-- 왜
--   체험 학교의 선생님 홈에는 보라색 '체험 초기화' 가 보인다. 지금까지는 체험 학교의 선생님이면
--   누구나 누를 수 있었다. 엑스포 부스에서는 부스 선생님 계정(모두 관리자)만 있어서 괜찮았지만,
--   연수 · 특강에서 참석자가 교사 코드로 가입해 '선생님 체험' 을 하면 이야기가 달라진다.
--   담임 반이 없는 선생님이 누르면 학교 전체가 초기화되어, 옆에서 학생 체험을 하던 사람의
--   오늘 점검 · 칭찬 · 교환이 사라진다.
--
-- 무엇이 바뀌나
--   · 관리자 선생님(teacher_role = 'admin')만 초기화할 수 있다. 일반 선생님이 누르면 안내만 나온다.
--   · 부스 선생님 계정은 setup_demo_school 이 모두 관리자로 만들어 두었으므로 엑스포는 그대로다.
--   · SQL 에디터에서 부르는 것(로그인 없음)은 지금처럼 된다.
--   본문은 070 과 같고 관리자 확인 다섯 줄만 더했다. 앱은 그대로다.
--
-- 주의: 참석자가 선생님으로 가입한 뒤에는 setup_demo_school 을 다시 실행하지 않는다.
--       다시 실행하면 그 학교의 선생님이 모두 관리자가 된다.

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
    -- 078: 관리자 선생님만. 연수 · 특강에서 교사 코드로 들어온 체험 선생님이
    --      보라색 '체험 초기화' 를 눌러 다른 사람의 체험 기록을 지우지 못하게 한다.
    if not is_admin_teacher() then
      return json_build_object('ok', false, 'error', '관리자 선생님만 초기화할 수 있어요');
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
  delete from support_referrals
   where school_id = v_school
     and (student_id = any(v_targets)
          or roster_id in (select ro.id from student_roster ro where ro.school_id = v_school and (v_scope = 'all' or (ro.grade = v_my_grade and ro.class_num = v_my_class))));
  delete from kodr_tier_alerts
   where school_id = v_school
     and (student_id = any(v_targets)
          or roster_id in (select ro.id from student_roster ro where ro.school_id = v_school and (v_scope = 'all' or (ro.grade = v_my_grade and ro.class_num = v_my_class))));
  delete from kodr_records
   where school_id = v_school
     and (student_id = any(v_targets)
          or roster_id in (select ro.id from student_roster ro where ro.school_id = v_school and (v_scope = 'all' or (ro.grade = v_my_grade and ro.class_num = v_my_class))));
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

-- ═══════════ 확인 ═══════════
--   select prosrc like '%관리자 선생님만 초기화%' from pg_proc where proname = 'reset_demo_school';   -- true
