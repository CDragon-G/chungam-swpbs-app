-- 044_vote_grade_schedule.sql
-- 수업맛집 학년별 투표 일정
--   3학년은 진학 때문에 중간·기말고사를 1·2학년보다 훨씬 일찍 본다.
--   시험 주간에는 정상 수업이 없어 관찰할 수업도 없고, 그 주를 주차로 세면
--   3학년만 라운드가 뒤로 밀린다. 그래서 학년별로 따로 굴린다.
--     1) 투표 쉬는 기간(시험 기간 등)을 학년별로 등록 → 그 학년만 투표 잠김
--     2) 쉬는 주는 그 학년의 주차 카운트에서 빠짐
--     3) 학년별 총 주차를 따로 줄 수 있음 (3학년 4주, 1·2학년 6주 등)
--     4) 학년별 조기 마감 → 3학년만 먼저 결과 공개·시상, 1·2학년은 계속

-- ═══════════ 1) 투표 쉬는 기간 ═══════════
create table if not exists vote_blackouts (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  grade int,                                   -- null = 전 학년
  start_date date not null,
  end_date date not null,
  label text not null default '시험 기간',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (end_date >= start_date),
  check (grade is null or grade between 1 and 6)
);
create index if not exists vb_school_idx
  on vote_blackouts(school_id, start_date, end_date);

alter table vote_blackouts enable row level security;

drop policy if exists vb_select on vote_blackouts;
create policy vb_select on vote_blackouts
  for select to authenticated
  using (school_id = current_profile_school());

drop policy if exists vb_admin_write on vote_blackouts;
create policy vb_admin_write on vote_blackouts
  for all to authenticated
  using (school_id = current_profile_school() and is_admin_teacher())
  with check (school_id = current_profile_school() and is_admin_teacher());

-- ═══════════ 2) 라운드 × 학년 설정 (총 주차 override · 조기 마감) ═══════════
create table if not exists vote_grade_settings (
  round_id uuid not null references vote_rounds(id) on delete cascade,
  grade int not null check (grade between 1 and 6),
  total_weeks int check (total_weeks between 1 and 20),  -- null = 라운드 기본값
  closed_at timestamptz,
  closed_by uuid references auth.users(id) on delete set null,
  primary key (round_id, grade)
);
alter table vote_grade_settings enable row level security;

drop policy if exists vgs_select on vote_grade_settings;
create policy vgs_select on vote_grade_settings
  for select to authenticated
  using (exists (select 1 from vote_rounds r
                  where r.id = round_id
                    and r.school_id = current_profile_school()));
-- 쓰기는 아래 RPC로만 (관리자 검증)

-- ═══════════ 3) 학교에 실제로 있는 학년 ═══════════
create or replace function school_grades(p_school uuid)
returns int[]
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select array_agg(distinct p.grade order by p.grade)
       from profiles p
      where p.school_id = p_school and p.role = 'student'
        and p.grade is not null),
    array[1, 2, 3]);
$$;
grant execute on function school_grades(uuid) to authenticated;

-- ═══════════ 4) 그 날 그 학년이 투표를 쉬는가 (쉬면 사유) ═══════════
create or replace function vote_blackout_label(p_school uuid, p_grade int, p_date date)
returns text
language sql stable security definer set search_path = public as $$
  select b.label
    from vote_blackouts b
   where b.school_id = p_school
     and (b.grade is null or b.grade = p_grade)
     and p_date between b.start_date and b.end_date
   order by b.grade nulls last, b.start_date
   limit 1;
$$;
grant execute on function vote_blackout_label(uuid, int, date) to authenticated;

-- ═══════════ 5) 학년별 현재 주차 ═══════════
--   라운드 시작 주부터 이번 주까지 세되, '그 학년이 실제로 투표할 수 있었던 주'만 센다.
--   한 주에 수업일이 하루라도 있고 그 날이 쉬는 기간이 아니면 그 주는 진행된 주.
create or replace function vote_grade_week(p_round uuid, p_grade int)
returns int
language plpgsql stable security definer set search_path = public as $$
declare
  v_school uuid; v_start date; v_total int;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_cur date; v_cnt int := 0;
begin
  select r.school_id,
         (r.created_at at time zone 'Asia/Seoul')::date,
         coalesce((select s.total_weeks from vote_grade_settings s
                    where s.round_id = r.id and s.grade = p_grade),
                  r.total_weeks)
    into v_school, v_start, v_total
    from vote_rounds r where r.id = p_round;
  if v_school is null then return 0; end if;

  -- 시작일이 속한 주의 월요일부터 이번 주까지
  v_cur := v_start - (extract(isodow from v_start)::int - 1);
  while v_cur <= v_today loop
    if exists (
      select 1
        from generate_series(v_cur, v_cur + 4, interval '1 day') d
       where d::date >= v_start
         and is_school_day(v_school, d::date)
         and vote_blackout_label(v_school, p_grade, d::date) is null
    ) then
      v_cnt := v_cnt + 1;
    end if;
    v_cur := v_cur + 7;
  end loop;

  return least(greatest(v_cnt, 1), v_total);
end $$;
grant execute on function vote_grade_week(uuid, int) to authenticated;

-- ═══════════ 6) 학년별 진행 현황 ═══════════
create or replace function vote_round_progress(p_round_id uuid)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_round vote_rounds;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_out json;
begin
  select * into v_round from vote_rounds
    where id = p_round_id and school_id = current_profile_school();
  if v_round is null then raise exception '투표를 찾을 수 없어요.'; end if;
  if current_profile_role() <> 'teacher' then
    raise exception '교사만 볼 수 있어요.';
  end if;

  select coalesce(json_agg(t.j order by t.g), '[]'::json) into v_out
  from (
    select g,
      json_build_object(
        'grade', g,
        'week_now', vote_grade_week(p_round_id, g),
        'total_weeks', coalesce(s.total_weeks, v_round.total_weeks),
        'custom_weeks', s.total_weeks is not null,
        'closed', s.closed_at is not null,
        'closed_at', s.closed_at,
        'paused_label', vote_blackout_label(v_round.school_id, g, v_today),
        'votes', (select count(*) from class_votes cv
                   where cv.round_id = p_round_id and cv.grade = g)
      ) as j
    from unnest(school_grades(v_round.school_id)) as g
    left join vote_grade_settings s
      on s.round_id = p_round_id and s.grade = g
  ) t;

  return json_build_object('round_id', p_round_id, 'grades', v_out);
end $$;
revoke all on function vote_round_progress(uuid) from public;
grant execute on function vote_round_progress(uuid) to authenticated;

-- ═══════════ 7) 학년별 총 주차 · 조기 마감 (관리자) ═══════════
create or replace function set_vote_grade_weeks(
  p_round_id uuid, p_grade int, p_weeks int
)
returns json
language plpgsql security definer set search_path = public, auth as $$
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 바꿀 수 있어요');
  end if;
  if not exists (select 1 from vote_rounds
                  where id = p_round_id and school_id = current_profile_school()) then
    return json_build_object('ok', false, 'error', '투표를 찾을 수 없어요');
  end if;
  if p_weeks is not null and (p_weeks < 1 or p_weeks > 20) then
    return json_build_object('ok', false, 'error', '주차는 1~20 사이로 넣어주세요');
  end if;

  insert into vote_grade_settings(round_id, grade, total_weeks)
  values (p_round_id, p_grade, p_weeks)
  on conflict (round_id, grade) do update set total_weeks = excluded.total_weeks;

  return json_build_object('ok', true);
end $$;
revoke all on function set_vote_grade_weeks(uuid, int, int) from public;
grant execute on function set_vote_grade_weeks(uuid, int, int) to authenticated;

create or replace function set_vote_grade_close(
  p_round_id uuid, p_grade int, p_closed boolean
)
returns json
language plpgsql security definer set search_path = public, auth as $$
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '관리자 선생님만 마감할 수 있어요');
  end if;
  if not exists (select 1 from vote_rounds
                  where id = p_round_id and school_id = current_profile_school()) then
    return json_build_object('ok', false, 'error', '투표를 찾을 수 없어요');
  end if;

  insert into vote_grade_settings(round_id, grade, closed_at, closed_by)
  values (p_round_id, p_grade,
          case when p_closed then now() else null end,
          case when p_closed then auth.uid() else null end)
  on conflict (round_id, grade) do update
    set closed_at = excluded.closed_at,
        closed_by = excluded.closed_by;

  return json_build_object('ok', true, 'closed', p_closed);
end $$;
revoke all on function set_vote_grade_close(uuid, int, boolean) from public;
grant execute on function set_vote_grade_close(uuid, int, boolean) to authenticated;

-- ═══════════ 8) 투표하기 — 쉬는 기간·학년 마감 검증 추가 ═══════════
create or replace function public.cast_class_vote(
  p_round_id uuid, p_subject text, p_grade int, p_class_num int
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_round vote_rounds;
  v_week text := kst_week_key();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_pause text;
  v_used int;
  v_id uuid;
begin
  if current_profile_role() <> 'teacher' then
    raise exception '교사만 투표할 수 있어요.';
  end if;

  select * into v_round from vote_rounds
    where id = p_round_id and school_id = current_profile_school();
  if v_round is null then raise exception '투표를 찾을 수 없어요.'; end if;
  if v_round.status <> 'open' then raise exception '이미 마감된 투표예요.'; end if;

  if coalesce(trim(p_subject), '') = '' then
    raise exception '과목을 선택해주세요.';
  end if;

  -- 학년별 조기 마감
  if exists (select 1 from vote_grade_settings s
              where s.round_id = p_round_id and s.grade = p_grade
                and s.closed_at is not null) then
    raise exception '%학년은 이미 마감돼서 투표할 수 없어요.', p_grade;
  end if;

  -- 시험 기간 등 투표를 쉬는 기간
  v_pause := vote_blackout_label(v_round.school_id, p_grade, v_today);
  if v_pause is not null then
    raise exception '%학년은 지금 투표를 쉬는 기간이에요. (%)', p_grade, v_pause;
  end if;

  -- 같은 주 같은 학급 중복 방지
  if exists (select 1 from class_votes
             where round_id = p_round_id and teacher_id = auth.uid()
               and week_key = v_week
               and grade = p_grade and class_num = p_class_num) then
    raise exception '이번 주에 이미 이 학급에 투표했어요.';
  end if;

  -- 주당 투표권 검증
  select count(*) into v_used from class_votes
    where round_id = p_round_id and teacher_id = auth.uid()
      and week_key = v_week;
  if v_used >= v_round.votes_per_week then
    raise exception '이번 주 투표권(%표)을 모두 사용했어요.', v_round.votes_per_week;
  end if;

  insert into class_votes(round_id, school_id, teacher_id, subject, grade, class_num, week_key)
  values (p_round_id, v_round.school_id, auth.uid(), trim(p_subject), p_grade, p_class_num, v_week)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.cast_class_vote(uuid, text, int, int) from public;
grant execute on function public.cast_class_vote(uuid, text, int, int) to authenticated;

-- ═══════════ 9) 집계 — 먼저 마감된 학년은 모든 교사에게 공개 ═══════════
create or replace function public.vote_tally(p_round_id uuid)
returns table (grade int, class_num int, votes bigint)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_round vote_rounds;
begin
  select * into v_round from vote_rounds
    where id = p_round_id and school_id = current_profile_school();
  if v_round is null then raise exception '투표를 찾을 수 없어요.'; end if;
  if current_profile_role() <> 'teacher' then
    raise exception '교사만 볼 수 있어요.';
  end if;

  -- 라운드가 열려 있고 관리자가 아니면, 먼저 마감된 학년만 보여준다.
  if v_round.status = 'open' and not is_admin_teacher() then
    return query
    select cv.grade, cv.class_num, count(*)::bigint
      from class_votes cv
      join vote_grade_settings s
        on s.round_id = cv.round_id and s.grade = cv.grade
     where cv.round_id = p_round_id and s.closed_at is not null
     group by cv.grade, cv.class_num
     order by cv.grade, count(*) desc, cv.class_num;
    return;
  end if;

  return query
  select cv.grade, cv.class_num, count(*)::bigint
  from class_votes cv
  where cv.round_id = p_round_id
  group by cv.grade, cv.class_num
  order by cv.grade, count(*) desc, cv.class_num;
end $$;
revoke all on function public.vote_tally(uuid) from public;
grant execute on function public.vote_tally(uuid) to authenticated;

-- ═══════════ 10) 힌트 — 학년별 주차·쉬는 기간 반영 ═══════════
create or replace function public.vote_hint()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_school uuid := current_profile_school();
  v_round vote_rounds;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
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

  -- 학교에 있는 모든 학년을 학년별 주차·상태와 함께 (학급명은 비공개)
  select coalesce(jsonb_agg(x.j order by x.g), '[]'::jsonb) into v_grades
  from (
    select g,
      jsonb_build_object(
        'grade', g,
        'week_now', vote_grade_week(v_round.id, g),
        'total_weeks', coalesce(s.total_weeks, v_round.total_weeks),
        'closed', s.closed_at is not null,
        'paused_label', vote_blackout_label(v_school, g, v_today),
        'top', coalesce(t.top, 0),
        'second', coalesce(t.second, 0)
      ) as j
    from unnest(school_grades(v_school)) as g
    left join vote_grade_settings s
      on s.round_id = v_round.id and s.grade = g
    left join lateral (
      select max(v.votes) as top,
             coalesce((array_agg(v.votes order by v.votes desc))[2], 0) as second
        from (select cv.class_num, count(*)::int as votes
                from class_votes cv
               where cv.round_id = v_round.id and cv.grade = g
               group by cv.class_num) v
    ) t on true
  ) x;

  return jsonb_build_object(
    'has_round', true,
    'title', v_round.title,
    'votes_per_week', v_round.votes_per_week,
    -- 전체 표시용은 가장 앞선 학년 기준 (구버전 앱 호환)
    'week_now', (select max((e->>'week_now')::int)
                   from jsonb_array_elements(v_grades) e),
    'total_weeks', v_round.total_weeks,
    'grades', v_grades
  );
end $$;
revoke all on function public.vote_hint() from public;
grant execute on function public.vote_hint() to authenticated;

-- ═══════════ 11) 알림용 — 오늘 투표 가능한 학년 ═══════════
create or replace function vote_reminder_grades(p_school uuid)
returns json
language sql stable security definer set search_path = public as $$
  with g as (select unnest(school_grades(p_school)) as grade),
  st as (
    select g.grade,
           vote_blackout_label(p_school, g.grade,
             (now() at time zone 'Asia/Seoul')::date) as pause_label,
           exists (select 1 from vote_rounds r
                     join vote_grade_settings s
                       on s.round_id = r.id and s.grade = g.grade
                    where r.school_id = p_school and r.status = 'open'
                      and s.closed_at is not null) as closed
      from g
  )
  select json_build_object(
    'open', coalesce((select array_agg(grade order by grade) from st
                       where pause_label is null and not closed), '{}'::int[]),
    'paused', coalesce((select json_agg(json_build_object('grade', grade, 'label', pause_label)
                                        order by grade)
                          from st where pause_label is not null), '[]'::json));
$$;
grant execute on function vote_reminder_grades(uuid) to authenticated, service_role;
