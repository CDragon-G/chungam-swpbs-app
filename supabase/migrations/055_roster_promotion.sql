-- 055_roster_promotion.sql
-- 새 학년도 진급 처리.
--
-- 문제
--   student_roster 의 고유키가 (학교, 학년, 반, 번호) 즉 '자리' 다. 사람이 아니다.
--   그래서 3월에 새 명렬표를 그냥 올리면
--     1) 이미 가입한 학생의 학년·반·번호가 바뀌지 않는다 (profiles 를 아무도 안 고침)
--     2) 작년 1학년 자리가 claimed 로 잠겨 있어 신입생이 가입을 못 한다
--     3) 진급한 학생 앞에 빈 자리가 새로 생겨 두 번째 계정을 만들 수 있다
--
-- 해결
--   자리를 새로 만드는 대신 '사람을 옮긴다'.
--     · 이름이 맞고 학년이 정확히 +1 인 사람 → 그 자리를 그대로 이동
--       (PIN·claimed 유지 → 다시 가입할 필요도, 할 방법도 없다)
--     · 새 이름 → 신입생. 새 자리 + 새 PIN
--     · 새 명렬표에 없는 사람 → 졸업·전출. 자리를 비우고 프로필에 left_at 표시
--
--   반드시 promote_roster_preview 로 먼저 보여주고, 확인을 받은 뒤에만
--   promote_roster_apply 를 부른다. 400명을 한 번에 옮기는 일이라
--   되돌리기가 어렵다.

-- ═══════════ 0) 떠난 학생 표시 ═══════════
--   프로필을 지우지 않는다. 그 학생의 점검 기록·포인트·칭찬이 통계의 일부다.
--   다만 '지금 우리 학교 학생 수' 에서는 빠져야 참여율이 정직해진다.
alter table profiles add column if not exists left_at timestamptz;
create index if not exists profiles_active_idx
  on profiles(school_id, role) where left_at is null;

-- ═══════════ 1) 이름 정규화 ═══════════
--   공백·중점 차이로 같은 사람을 다른 사람으로 보지 않기 위해.
create or replace function roster_name_key(p_name text)
returns text
language sql immutable set search_path = public as $$
  select lower(regexp_replace(coalesce(p_name, ''), '[[:space:]·.]', '', 'g'));
$$;

-- ═══════════ 2) 진급 계획 세우기 (아무것도 바꾸지 않음) ═══════════
create or replace function promote_roster_plan(p_school_id uuid, p_rows jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_role text; v_school uuid;
  v_moves jsonb; v_new jsonb; v_leaving jsonb; v_ambig jsonb;
begin
  select role, school_id into v_role, v_school
    from profiles where user_id = auth.uid();
  if v_role is distinct from 'teacher' then
    return jsonb_build_object('ok', false, 'error', '교사만 진급 처리를 할 수 있어요');
  end if;
  if v_school is distinct from p_school_id then
    return jsonb_build_object('ok', false, 'error', '본인 학교만 처리할 수 있어요');
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array'
     or jsonb_array_length(p_rows) = 0 then
    return jsonb_build_object('ok', false, 'error', '새 명렬표가 비어 있어요');
  end if;

  with
  -- 새 명렬표
  incoming as (
    select (r->>'grade')::int      as grade,
           (r->>'class_num')::int  as class_num,
           (r->>'student_num')::int as student_num,
           btrim(r->>'name')       as name,
           roster_name_key(r->>'name') as key
      from jsonb_array_elements(p_rows) r
     where (r->>'grade') ~ '^[0-9]+$'
       and (r->>'class_num') ~ '^[0-9]+$'
       and (r->>'student_num') ~ '^[0-9]+$'
       and btrim(coalesce(r->>'name','')) <> ''
  ),
  -- 지금 명단
  current_roster as (
    select id, grade, class_num, student_num, name, claimed, claimed_by,
           roster_name_key(name) as key
      from student_roster where school_id = p_school_id
  ),
  -- 이름+학년이 유일해야 자동으로 이을 수 있다
  cur_dup as (
    select key, grade from current_roster group by key, grade having count(*) > 1
  ),
  inc_dup as (
    select key, grade from incoming group by key, grade having count(*) > 1
  ),
  -- 애매한 이름은 아예 손대지 않는다.
  --   동명이인을 '짝 못 찾음' 으로 흘려보내면 졸업 처리되고 새 PIN 으로
  --   다시 등록된다. 이미 가입한 학생의 계정 연결이 끊긴다. 그래서
  --   이 이름들은 moves·new·leaving 어디에도 넣지 않고 따로 보고만 한다.
  ambig_key as (
    select key from cur_dup
    union
    select key from inc_dup
  ),
  -- 짝짓기: 같은 이름, 학년이 정확히 +1
  pairs as (
    select c.id as roster_id, c.name, c.claimed, c.claimed_by,
           c.grade as from_grade, c.class_num as from_class, c.student_num as from_num,
           i.grade as to_grade,   i.class_num as to_class,   i.student_num as to_num
      from current_roster c
      join incoming i
        on i.key = c.key and i.grade = c.grade + 1
     where not exists (select 1 from ambig_key a where a.key = c.key)
  )
  select
    -- 옮길 사람
    coalesce((select jsonb_agg(jsonb_build_object(
        'roster_id', p.roster_id, 'name', p.name, 'joined', p.claimed,
        'from', p.from_grade || '-' || p.from_class || '-' || p.from_num,
        'to',   p.to_grade   || '-' || p.to_class   || '-' || p.to_num,
        'to_grade', p.to_grade, 'to_class', p.to_class, 'to_num', p.to_num)
      order by p.to_grade, p.to_class, p.to_num) from pairs p), '[]'::jsonb),
    -- 신입생 (짝을 못 찾은 새 명렬표 줄)
    coalesce((select jsonb_agg(jsonb_build_object(
        'name', i.name, 'to', i.grade || '-' || i.class_num || '-' || i.student_num,
        'grade', i.grade, 'class_num', i.class_num, 'student_num', i.student_num)
      order by i.grade, i.class_num, i.student_num)
      from incoming i
     where not exists (select 1 from pairs p
                        where p.to_grade = i.grade and p.to_class = i.class_num
                          and p.to_num = i.student_num)
       and not exists (select 1 from ambig_key a where a.key = i.key)), '[]'::jsonb),
    -- 떠나는 사람 (짝을 못 찾은 기존 명단)
    coalesce((select jsonb_agg(jsonb_build_object(
        'roster_id', c.id, 'name', c.name, 'joined', c.claimed,
        'user_id', c.claimed_by,
        'from', c.grade || '-' || c.class_num || '-' || c.student_num)
      order by c.grade, c.class_num, c.student_num)
      from current_roster c
     where not exists (select 1 from pairs p where p.roster_id = c.id)
       and not exists (select 1 from ambig_key a where a.key = c.key)), '[]'::jsonb),
    -- 사람이 판단해야 하는 것 (동명이인)
    coalesce((select jsonb_agg(distinct jsonb_build_object(
        'name', t.name, 'grade', t.grade,
        'reason', '같은 학년에 같은 이름이 둘 이상이라 자동으로 잇지 못했어요'))
      from (
        select c.name, c.grade from current_roster c
          join ambig_key a on a.key = c.key
        union
        select i.name, i.grade from incoming i
          join ambig_key a on a.key = i.key
      ) t), '[]'::jsonb)
  into v_moves, v_new, v_leaving, v_ambig;

  return jsonb_build_object(
    'ok', true,
    'moves', v_moves,
    'new', v_new,
    'leaving', v_leaving,
    'ambiguous', v_ambig,
    'counts', jsonb_build_object(
      'moves', jsonb_array_length(v_moves),
      'new', jsonb_array_length(v_new),
      'leaving', jsonb_array_length(v_leaving),
      'ambiguous', jsonb_array_length(v_ambig)));
end $$;
grant execute on function promote_roster_plan(uuid, jsonb) to authenticated;

-- 미리보기는 계획만 돌려준다 (이름만 다른 얇은 껍데기 — 호출부에서 의도가 드러나도록)
create or replace function promote_roster_preview(p_school_id uuid, p_rows jsonb)
returns jsonb
language sql stable security definer set search_path = public, auth as $$
  select promote_roster_plan(p_school_id, p_rows);
$$;
grant execute on function promote_roster_preview(uuid, jsonb) to authenticated;

-- ═══════════ 3) 실제로 옮기기 ═══════════
--   계획은 서버가 다시 세운다. 앱이 보낸 계획을 그대로 믿지 않는다.
create or replace function promote_roster_apply(
  p_school_id uuid,
  p_rows jsonb,
  p_mark_leavers boolean default true
)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_plan jsonb;
  v_moved int := 0; v_added int := 0; v_left int := 0;
  r jsonb;
  v_pin text;
begin
  v_plan := promote_roster_plan(p_school_id, p_rows);
  if (v_plan->>'ok')::boolean is not true then
    return v_plan::json;
  end if;

  -- 동명이인이 남아 있으면 아예 시작하지 않는다.
  --   그 학생들만 빼고 돌리면 자리가 어긋나 다른 학생의 이동까지 막힌다.
  --   400명을 반쯤 옮겨 놓고 멈추는 것보다, 손대지 않고 멈추는 편이 낫다.
  if jsonb_array_length(v_plan->'ambiguous') > 0 then
    return json_build_object('ok', false, 'error',
      '같은 학년에 이름이 같은 학생이 있어 자동으로 잇지 못했어요. ' ||
      '학생 관리에서 그 학생들의 학년·반·번호를 먼저 정리한 뒤 다시 실행해 주세요.');
  end if;

  -- (1) 떠나는 사람의 자리를 먼저 비운다.
  --     안 그러면 3학년 자리가 차 있어서 2학년이 올라갈 수 없다.
  for r in select * from jsonb_array_elements(v_plan->'leaving') loop
    if p_mark_leavers and (r->>'user_id') is not null then
      update profiles
         set left_at = now()
       where user_id = (r->>'user_id')::uuid
         and school_id = p_school_id
         and left_at is null;
    end if;
    delete from student_roster where id = (r->>'roster_id')::uuid;
    v_left := v_left + 1;
  end loop;

  -- (2) 옮길 사람을 잠시 밖으로 뺀다.
  --     1학년→2학년과 2학년→3학년이 동시에 일어나므로, 한 줄씩 바로 옮기면
  --     중간에 (학년,반,번호) 중복으로 걸린다. 음수 학년에 잠깐 세워둔다.
  update student_roster
     set grade = grade - 1000
   where school_id = p_school_id
     and id in (select (e->>'roster_id')::uuid
                  from jsonb_array_elements(v_plan->'moves') e);

  -- (3) 새 자리에 앉힌다. PIN 과 claimed 는 건드리지 않는다.
  for r in select * from jsonb_array_elements(v_plan->'moves') loop
    update student_roster
       set grade = (r->>'to_grade')::int,
           class_num = (r->>'to_class')::int,
           student_num = (r->>'to_num')::int
     where id = (r->>'roster_id')::uuid;

    -- 가입한 학생이면 프로필의 학년·반·번호도 같이 옮긴다.
    -- 이걸 안 하면 앱에서는 영원히 작년 학번으로 보인다.
    if (r->>'joined')::boolean then
      update profiles p
         set grade = (r->>'to_grade')::int,
             class_num = (r->>'to_class')::int,
             student_num = (r->>'to_num')::int
        from student_roster s
       where s.id = (r->>'roster_id')::uuid
         and p.user_id = s.claimed_by;
    end if;
    v_moved := v_moved + 1;
  end loop;

  -- (4) 신입생 자리를 만든다. 새 PIN 이 붙는다.
  for r in select * from jsonb_array_elements(v_plan->'new') loop
    v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');
    insert into student_roster
      (school_id, grade, class_num, student_num, name, pin)
    values
      (p_school_id, (r->>'grade')::int, (r->>'class_num')::int,
       (r->>'student_num')::int, r->>'name', v_pin)
    on conflict (school_id, grade, class_num, student_num) do nothing;
    v_added := v_added + 1;
  end loop;

  return json_build_object('ok', true,
    'moved', v_moved, 'added', v_added, 'left', v_left);
end $$;
grant execute on function promote_roster_apply(uuid, jsonb, boolean) to authenticated;

-- ═══════════ 3-1) 학생 학년·반·번호 직접 수정 ═══════════
--   동명이인처럼 자동으로 못 잇는 경우, 전입, 반 배정 정정에 쓴다.
--   프로필과 명단 자리를 함께 옮겨야 둘이 어긋나지 않는다.
create or replace function set_student_class(
  p_user_id uuid, p_grade int, p_class_num int, p_student_num int)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare v_school uuid; v_roster uuid; v_taken uuid;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 수정할 수 있어요');
  end if;
  select school_id into v_school from profiles where user_id = auth.uid();

  if not exists (select 1 from profiles
                  where user_id = p_user_id and school_id = v_school
                    and role = 'student') then
    return json_build_object('ok', false, 'error', '우리 학교 학생이 아니에요');
  end if;
  if p_grade is null or p_class_num is null or p_student_num is null
     or p_grade < 1 or p_class_num < 1 or p_student_num < 1 then
    return json_build_object('ok', false, 'error', '학년·반·번호를 확인해 주세요');
  end if;

  -- 이 학생이 쓰고 있는 명단 자리
  select id into v_roster from student_roster
   where school_id = v_school and claimed_by = p_user_id;

  -- 옮겨 갈 자리에 다른 사람이 있으면 멈춘다
  select id into v_taken from student_roster
   where school_id = v_school and grade = p_grade
     and class_num = p_class_num and student_num = p_student_num
     and (v_roster is null or id <> v_roster);
  if v_taken is not null then
    return json_build_object('ok', false, 'error',
      p_grade || '학년 ' || p_class_num || '반 ' || p_student_num ||
      '번 자리에 이미 다른 학생이 있어요');
  end if;

  update profiles
     set grade = p_grade, class_num = p_class_num, student_num = p_student_num
   where user_id = p_user_id;

  if v_roster is not null then
    update student_roster
       set grade = p_grade, class_num = p_class_num, student_num = p_student_num
     where id = v_roster;
  end if;

  return json_build_object('ok', true, 'roster_moved', v_roster is not null);
end $$;
grant execute on function set_student_class(uuid, int, int, int) to authenticated;

-- ═══════════ 4) 떠난 학생 되돌리기 ═══════════
--   전출인 줄 알았는데 아니었던 경우. 명단 자리는 따로 만들어야 한다.
create or replace function undo_student_leave(p_user_id uuid)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare v_school uuid;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 되돌릴 수 있어요');
  end if;
  select school_id into v_school from profiles where user_id = auth.uid();
  update profiles set left_at = null
   where user_id = p_user_id and school_id = v_school;
  return json_build_object('ok', found);
end $$;
grant execute on function undo_student_leave(uuid) to authenticated;

-- ═══════════ 5) 떠난 학생은 '지금 학생 수' 에서 뺀다 ═══════════
--   참여율 = 최근 30일 점검자 / 학생 수. 졸업생이 분모에 남아 있으면
--   3월마다 참여율이 근거 없이 무너진다.
create or replace function public.school_growth()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_school uuid := current_profile_school();
  v_name text;
  v_started date;
  v_year date := growth_year_start();
  v_year_ts timestamptz;
  v_from date;
  v_days int;

  v_rules int; v_roster int; v_students int;
  v_checkins bigint; v_active30 int;
  v_praise bigint; v_kodr bigint; v_kodr30 bigint; v_kodr_prev30 bigint;
  v_cico int; v_cico_grad int; v_rounds int; v_items int;
  v_exch bigint; v_votes bigint; v_ann int; v_weekly bigint;

  m1 boolean; m2 boolean; m3 boolean; m4 boolean;
  m5 boolean; m6 boolean; m7 boolean; m8 boolean;

  v_part numeric; v_kodr_mode text;
  a_part int; a_praise int; a_kodr int; a_cico int;
  a_items int; a_exch int; a_votes int; a_ann int; a_weekly int;
  v_score int; v_hist jsonb;
begin
  if v_school is null then
    raise exception '로그인이 필요해요.';
  end if;

  select name, created_at::date into v_name, v_started
    from schools where id = v_school;

  v_year_ts := v_year::timestamp at time zone 'Asia/Seoul';
  v_from := greatest(v_year, v_started);
  v_days := greatest((now() at time zone 'Asia/Seoul')::date - v_from, 0);

  select count(*) into v_rules from school_rules
    where school_id = v_school and is_active = true;
  select count(*) into v_roster from student_roster
    where school_id = v_school;
  -- 떠난 학생 제외
  select count(*) into v_students from profiles
    where school_id = v_school and role = 'student' and left_at is null;
  select count(*) into v_items from point_store_items
    where school_id = v_school;

  select count(*) into v_checkins from daily_checkins
    where school_id = v_school and checkin_date >= v_year;
  select count(distinct d.user_id) into v_active30
    from daily_checkins d
    join profiles p on p.user_id = d.user_id and p.left_at is null
   where d.school_id = v_school
     and d.checkin_date >= current_date - interval '30 days';
  select count(*) into v_praise from praise
    where school_id = v_school and created_at >= v_year_ts;
  select count(*) into v_kodr from kodr_records
    where school_id = v_school and occurred_date >= v_year;
  select count(*) into v_kodr30 from kodr_records
    where school_id = v_school and occurred_date >= current_date - 30;
  select count(*) into v_kodr_prev30 from kodr_records
    where school_id = v_school
      and occurred_date >= current_date - 60
      and occurred_date <  current_date - 30;
  select count(*) into v_cico from cico_enrollments
    where school_id = v_school and created_at >= v_year_ts;
  select count(*) into v_cico_grad from cico_enrollments
    where school_id = v_school and status = 'graduated'
      and coalesce(end_date, start_date) >= v_year;
  select count(*) into v_rounds from vote_rounds
    where school_id = v_school and created_at >= v_year_ts;
  select count(*) into v_exch from point_exchanges
    where school_id = v_school and status = 'fulfilled'
      and coalesce(fulfilled_at, requested_at) >= v_year_ts;
  select count(*) into v_votes from class_votes
    where school_id = v_school and created_at >= v_year_ts;
  select count(*) into v_ann from announcements
    where school_id = v_school and created_at >= v_year_ts;
  select count(*) into v_weekly from point_transactions
    where school_id = v_school and reason = 'checkin_weekly'
      and created_at >= v_year_ts;

  m1 := v_rules >= 5;
  m2 := v_roster > 0;
  m3 := v_roster > 0 and v_students >= v_roster * 0.5;
  m4 := v_checkins > 0;
  m5 := v_praise > 0;
  m6 := v_kodr > 0;
  m7 := v_cico > 0;
  m8 := v_rounds > 0;

  v_part := case when v_students > 0
                 then round(v_active30::numeric / v_students * 100, 1)
                 else 0 end;
  a_part := least((v_part / 2.5)::int, 40);
  a_praise := least((v_praise / 10)::int, 25);

  if v_days < 90 then
    v_kodr_mode := 'early';
    a_kodr := least((v_kodr * 2)::int, 20);
  elsif v_kodr30 <= v_kodr_prev30 then
    v_kodr_mode := 'down';
    a_kodr := 20;
  else
    v_kodr_mode := 'up';
    a_kodr := 5;
  end if;

  a_cico   := least(v_cico_grad * 5, 15);
  a_items  := least(v_items * 2, 10);
  a_exch   := least((v_exch / 5)::int, 15);
  a_votes  := least((v_votes / 10)::int, 15);
  a_ann    := least(v_ann * 2, 10);
  a_weekly := least((v_weekly / 10)::int, 10);

  v_score :=
    (case when m1 then 10 else 0 end) + (case when m2 then 10 else 0 end) +
    (case when m3 then 10 else 0 end) + (case when m4 then 10 else 0 end) +
    (case when m5 then 10 else 0 end) + (case when m6 then 10 else 0 end) +
    (case when m7 then 10 else 0 end) + (case when m8 then 10 else 0 end) +
    a_part + a_praise + a_kodr + a_cico +
    a_items + a_exch + a_votes + a_ann + a_weekly;

  select coalesce(jsonb_agg(
           jsonb_build_object('year',  growth_year_label(y.year_start),
                              'level', y.peak_level,
                              'score', y.peak_score)
           order by y.year_start desc), '[]'::jsonb)
    into v_hist
  from school_growth_year y
  where y.school_id = v_school and y.year_start < v_year;

  return jsonb_build_object(
    'school_name', v_name,
    'score', v_score,
    'days', v_days,
    'year_start', v_year,
    'year_label', growth_year_label(v_year),
    'history', v_hist,
    'missions', jsonb_build_array(
      jsonb_build_object('key','rules',   'label','우리 학교 규칙 만들기 (5개 이상)', 'done', m1),
      jsonb_build_object('key','roster',  'label','전교생 명단 등록하기',            'done', m2),
      jsonb_build_object('key','join',    'label','학생 절반 이상 가입하기',          'done', m3),
      jsonb_build_object('key','checkin', 'label','첫 일일 자기점검 받기',            'done', m4),
      jsonb_build_object('key','praise',  'label','첫 칭찬 보내기',                  'done', m5),
      jsonb_build_object('key','kodr',    'label','첫 K-ODR 기록하기',              'done', m6),
      jsonb_build_object('key','cico',    'label','첫 CICO 동행점검 시작하기',        'done', m7),
      jsonb_build_object('key','vote',    'label','수업맛집 투표 열기',              'done', m8)
    ),
    'activity', jsonb_build_object(
      'participation', v_part,       'participation_pts', a_part,
      'praise_total', v_praise,      'praise_pts', a_praise,
      'kodr_mode', v_kodr_mode,      'kodr_total', v_kodr,   'kodr_pts', a_kodr,
      'cico_graduated', v_cico_grad, 'cico_pts', a_cico,
      'store_items', v_items,        'store_pts', a_items,
      'exchanges', v_exch,           'exchange_pts', a_exch,
      'votes_cast', v_votes,         'vote_pts', a_votes,
      'announcements', v_ann,        'announce_pts', a_ann,
      'weekly_bonus', v_weekly,      'weekly_pts', a_weekly
    )
  );
end $$;
revoke all on function public.school_growth() from public;
grant execute on function public.school_growth() to authenticated;

-- ═══════════ 6) 떠난 학생은 자기점검을 하지 않는다 ═══════════
create or replace function submit_checkin(
  p_answers jsonb,
  p_comment text default null
)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text; v_left timestamptz;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_total int := 0; v_possible int := 0;
  v_pct float := 0;
  v_cats jsonb := '{}'::jsonb;
  v_clean jsonb := '{}'::jsonb;
  v_existing boolean;
  r record;
begin
  select school_id, role, left_at into v_school, v_role, v_left
    from profiles where user_id = auth.uid();
  if v_school is null then
    return json_build_object('ok', false, 'error', '로그인이 필요해요');
  end if;
  if v_left is not null then
    return json_build_object('ok', false, 'error',
      '졸업·전출 처리된 계정이에요. 선생님께 문의해 주세요.');
  end if;

  if not is_school_day(v_school, v_today) then
    return json_build_object('ok', false, 'error',
      '오늘은 자기점검을 하는 날이 아니에요. 다음 수업일에 만나요!');
  end if;

  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    return json_build_object('ok', false, 'error', '점검 내용이 비어 있어요');
  end if;

  for r in
    select sr.id, sr.category, (p_answers ->> sr.id::text) as raw
      from school_rules sr
     where sr.school_id = v_school and sr.is_active
       and p_answers ? sr.id::text
  loop
    if r.raw not in ('true', 'false') then continue; end if;
    v_possible := v_possible + 1;
    if r.raw = 'true' then v_total := v_total + 1; end if;
    v_clean := v_clean || jsonb_build_object(r.id::text, (r.raw = 'true'));
  end loop;

  if v_possible = 0 then
    return json_build_object('ok', false, 'error', '점검한 규칙이 없어요');
  end if;
  v_pct := (v_total::float / v_possible) * 100.0;

  select coalesce(jsonb_object_agg(t.category, t.avg_pct), '{}'::jsonb)
    into v_cats
  from (
    select sr.category,
           avg(case when v_clean ->> sr.id::text = 'true' then 100.0 else 0.0 end) as avg_pct
      from school_rules sr
     where sr.school_id = v_school and sr.is_active
       and v_clean ? sr.id::text
     group by sr.category
  ) t;

  select exists (select 1 from daily_checkins
                  where user_id = auth.uid() and checkin_date = v_today)
    into v_existing;

  insert into daily_checkins
    (user_id, school_id, checkin_date, answers,
     total_score, total_possible, score_pct, category_scores, comment)
  values
    (auth.uid(), v_school, v_today, v_clean,
     v_total, v_possible, v_pct, v_cats, nullif(btrim(coalesce(p_comment, '')), ''))
  on conflict (user_id, checkin_date) do update
    set answers = excluded.answers,
        total_score = excluded.total_score,
        total_possible = excluded.total_possible,
        score_pct = excluded.score_pct,
        category_scores = excluded.category_scores,
        comment = excluded.comment,
        updated_at = now();

  if v_role = 'student' then
    perform award_checkin_points_internal(auth.uid(), v_school, v_today);
  end if;

  return json_build_object(
    'ok', true,
    'checkin_date', v_today,
    'total_score', v_total,
    'total_possible', v_possible,
    'score_pct', v_pct,
    'is_overwrite', v_existing);
end $$;
grant execute on function submit_checkin(jsonb, text) to authenticated;

-- ═══════════ 7) 확인 ═══════════
--   미리보기 (아무것도 바뀌지 않음)
--     select promote_roster_preview('<school_id>', '[{"grade":2,"class_num":1,"student_num":1,"name":"홍길동"}]'::jsonb);
--   실제 적용
--     select promote_roster_apply('<school_id>', '<같은 jsonb>');
--   떠난 학생 확인
--     select nickname, grade, class_num, student_num, left_at
--       from profiles where left_at is not null order by left_at desc;
