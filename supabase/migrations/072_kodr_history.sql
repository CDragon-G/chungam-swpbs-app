-- 072_kodr_history.sql
-- K-ODR 을 달이 바뀌어도, 학년이 바뀌어도 볼 수 있게 한다.
--
-- 무엇이 문제였나
--   K-ODR 화면의 현황은 '이번 달' 만 보여줬다. 10월 1일이 되자 9월 기록이 화면에서
--   모두 사라진 것처럼 보였다. 기록은 지워지지 않았다. 볼 방법이 없었을 뿐이다.
--
--   K-ODR 은 한 학생을 여러 해에 걸쳐 이해하기 위한 기록이다. 새 학기에 담임이나
--   교과 선생님이 바뀌어도 그 학생의 지난 기록을 볼 수 있어야 의미가 있다.
--
-- 어떻게 바꿨나
--   · 기간별 현황: 월별(지난달로 넘겨 보기) · 이번 학년도 · 전체
--   · 학생별 누적 이력: 그 학생의 모든 기록을 학년도 · 달 순서로
--   · 선생님이 앱에서 K-ODR 을 지울 수 없게 막는다 (지금도 지우는 화면은 없다.
--     서버에서도 막아 둔다)
--
-- 보존
--   기록은 학생이 진급해도 같은 학생에게 이어진다 (070: 명렬표 줄 기준).
--   졸업 · 전출로 명렬표에서 빠져도 기록은 지워지지 않고, 기록 당시의 이름 · 학번이 남는다.
--   누적 목록(학년도 · 전체)에는 지금 다니는 학생만 나온다.
--   월별 목록에는 그 달에 기록된 학생이 모두 나온다.

-- ═══════════ 1) 선생님은 K-ODR 을 지울 수 없다 ═══════════
--   016 의 정책은 'for all' 이라 지우기까지 열려 있었다. 읽기 · 쓰기 · 고치기만 남긴다.
--   체험 학교 초기화(reset_demo_school)는 서버 함수라 이 정책과 상관없이 동작한다.
drop policy if exists kodr_teacher_all on kodr_records;

drop policy if exists kodr_teacher_select on kodr_records;
create policy kodr_teacher_select on kodr_records
  for select using (
    exists (select 1 from profiles p
             where p.user_id = auth.uid() and p.role = 'teacher'
               and p.school_id = kodr_records.school_id));

drop policy if exists kodr_teacher_insert on kodr_records;
create policy kodr_teacher_insert on kodr_records
  for insert with check (
    exists (select 1 from profiles p
             where p.user_id = auth.uid() and p.role = 'teacher'
               and p.school_id = kodr_records.school_id));

drop policy if exists kodr_teacher_update on kodr_records;
create policy kodr_teacher_update on kodr_records
  for update using (
    exists (select 1 from profiles p
             where p.user_id = auth.uid() and p.role = 'teacher'
               and p.school_id = kodr_records.school_id))
  with check (
    exists (select 1 from profiles p
             where p.user_id = auth.uid() and p.role = 'teacher'
               and p.school_id = kodr_records.school_id));

-- ═══════════ 2) 기간별 현황 ═══════════
--   p_mode: 'month' (p_year_month, 기본 이번 달) · 'year' (이번 학년도) · 'all' (전체)
--   학생마다 그 기간의 건수와 함께 학년도 누적 · 전체 누적을 준다.
--   months: 이번 학년도의 달별 건수 (3월 ~ 이번 달). 어느 달에 기록이 있는지 한눈에 본다.
create or replace function kodr_period_subjects(
  p_mode text default 'month', p_year_month text default null)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text;
  v_mode text := coalesce(p_mode, 'month');
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_year_start date := growth_year_start();
  ym text := coalesce(p_year_month, to_char(v_today, 'YYYY-MM'));
  d_start date; d_end date;
  v_threshold int;
  v_items json; v_months json;
  v_total int;
begin
  select school_id, role into v_school, v_role
    from profiles where user_id = auth.uid();
  if v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 볼 수 있어요');
  end if;
  if v_mode not in ('month', 'year', 'all') then
    return json_build_object('ok', false, 'error', '기간을 확인해 주세요');
  end if;

  if v_mode = 'month' then
    if ym !~ '^\d{4}-(0[1-9]|1[0-2])$' then
      return json_build_object('ok', false, 'error', '달을 확인해 주세요');
    end if;
    d_start := to_date(ym || '-01', 'YYYY-MM-DD');
    d_end := (d_start + interval '1 month')::date;
  elsif v_mode = 'year' then
    d_start := v_year_start;
    d_end := date '9999-12-31';
  else
    d_start := date '1900-01-01';
    d_end := date '9999-12-31';
  end if;

  select kodr_cico_threshold into v_threshold from schools where id = v_school;

  with base as (
    select k.subject_id,
           max(k.roster_id::text)::uuid as roster_id,
           max(k.student_id::text)::uuid as student_id,
           count(*) filter (where k.occurred_date >= d_start and k.occurred_date < d_end)::int
             as record_count,
           count(*) filter (where k.occurred_date >= v_year_start)::int as year_count,
           count(*)::int as total_count,
           max(k.occurred_date) filter (where k.occurred_date >= d_start and k.occurred_date < d_end)
             as last_date,
           (array_agg(k.student_name order by k.created_at desc)
              filter (where k.student_name is not null))[1] as snap_name,
           (array_agg(k.student_grade order by k.created_at desc)
              filter (where k.student_grade is not null))[1] as snap_grade,
           (array_agg(k.student_class order by k.created_at desc)
              filter (where k.student_class is not null))[1] as snap_class,
           (array_agg(k.student_no order by k.created_at desc)
              filter (where k.student_no is not null))[1] as snap_no
      from kodr_records k
     where k.school_id = v_school and k.subject_id is not null
     group by k.subject_id
  ),
  named as (
    select b.subject_id, b.roster_id, b.student_id,
           coalesce(r.name, p.nickname, b.snap_name, '(이름 없음)') as name,
           coalesce(r.grade, p.grade, b.snap_grade, 0) as grade,
           coalesce(r.class_num, p.class_num, b.snap_class, 0) as class_num,
           coalesce(r.student_num, p.student_num, b.snap_no, 0) as student_num,
           b.record_count, b.year_count, b.total_count, b.last_date,
           (v_mode = 'month' and b.record_count >= coalesce(v_threshold, 3)) as needs_cico,
           b.student_id is not null as joined,
           -- 지금 다니는 학생인가 (명렬표에 있거나, 떠나지 않은 계정)
           (r.id is not null
            or (p.user_id is not null and p.role = 'student' and p.left_at is null)) as is_current
      from base b
      left join student_roster r on r.id = b.roster_id and r.school_id = v_school
      left join profiles p on p.user_id = b.student_id and p.school_id = v_school
     where b.record_count > 0
  )
  select coalesce(json_agg(row_to_json(n) order by n.record_count desc,
                           n.grade, n.class_num, n.student_num), '[]'::json),
         coalesce(sum(n.record_count), 0)::int
    into v_items, v_total
    from named n
   where v_mode = 'month' or n.is_current;   -- 누적 목록은 지금 다니는 학생만

  -- 이번 학년도의 달별 건수
  select coalesce(json_agg(json_build_object(
           'year_month', to_char(m.d, 'YYYY-MM'),
           'record_count', (select count(*)::int from kodr_records k
                             where k.school_id = v_school and k.subject_id is not null
                               and k.occurred_date >= m.d::date
                               and k.occurred_date < (m.d + interval '1 month')::date),
           'student_count', (select count(distinct k.subject_id)::int from kodr_records k
                              where k.school_id = v_school and k.subject_id is not null
                                and k.occurred_date >= m.d::date
                                and k.occurred_date < (m.d + interval '1 month')::date))
         order by m.d), '[]'::json)
    into v_months
    from generate_series(v_year_start::timestamp,
                         date_trunc('month', v_today)::timestamp,
                         interval '1 month') as m(d);

  return json_build_object(
    'ok', true,
    'mode', v_mode,
    'year_month', case when v_mode = 'month' then ym end,
    'this_month', to_char(v_today, 'YYYY-MM'),
    'year_start', v_year_start,
    'threshold', coalesce(v_threshold, 3),
    'total', v_total,
    'items', v_items,
    'months', v_months);
end $$;
revoke all on function kodr_period_subjects(text, text) from public, anon;
grant execute on function kodr_period_subjects(text, text) to authenticated;

-- ═══════════ 3) 학생별 누적 이력 ═══════════
--   같은 학교 선생님이면 누구나 본다 (K-ODR 기록과 같은 범위).
--   새 학기에 처음 만나는 학생의 지난 기록을 한눈에 볼 수 있어야 한다.
--   학맞통 안건 여부는 여기에 넣지 않는다. 그 정보는 관리자 선생님만 본다 (059).
create or replace function kodr_subject_history(p_subject uuid, p_limit int default 300)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_year_start date := growth_year_start();
  v_window int;
  v_student json; v_counts json; v_records json; v_behaviors json; v_places json;
  v_total int;
begin
  select school_id, role into v_school, v_role
    from profiles where user_id = auth.uid();
  if v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 볼 수 있어요');
  end if;
  if p_subject is null then
    return json_build_object('ok', false, 'error', '학생을 골라주세요');
  end if;

  select count(*)::int into v_total
    from kodr_records where school_id = v_school and subject_id = p_subject;
  if v_total = 0 then
    return json_build_object('ok', false, 'error', '기록을 찾을 수 없어요');
  end if;

  select coalesce(kodr_window_days, 30) into v_window from schools where id = v_school;

  -- 지금의 이름 · 학번 (명렬표 → 계정 → 마지막 기록 당시)
  select json_build_object(
           'subject_id', p_subject,
           'name', coalesce(r.name, p.nickname, k.student_name, '(이름 없음)'),
           'grade', coalesce(r.grade, p.grade, k.student_grade),
           'class_num', coalesce(r.class_num, p.class_num, k.student_class),
           'student_num', coalesce(r.student_num, p.student_num, k.student_no),
           'joined', k.student_id is not null,
           'is_current', (r.id is not null
                          or (p.user_id is not null and p.role = 'student'
                              and p.left_at is null)))
    into v_student
    from (select * from kodr_records
           where school_id = v_school and subject_id = p_subject
           order by created_at desc limit 1) k
    left join student_roster r on r.id = k.roster_id and r.school_id = v_school
    left join profiles p on p.user_id = k.student_id and p.school_id = v_school;

  select json_build_object(
           'total', count(*)::int,
           'year', count(*) filter (where occurred_date >= v_year_start)::int,
           'window', count(*) filter (where occurred_date > v_today - v_window)::int,
           'window_days', v_window,
           'first_date', min(occurred_date),
           'last_date', max(occurred_date))
    into v_counts
    from kodr_records where school_id = v_school and subject_id = p_subject;

  select coalesce(json_agg(json_build_object(
           'id', k.id,
           'occurred_date', k.occurred_date,
           'school_year', extract(year from growth_year_start(k.occurred_date))::int,
           'behavior', k.behavior,
           'place', k.place,
           'situation', k.situation,
           'immediate_response', k.immediate_response,
           'secondary_response', k.secondary_response,
           'student_reaction', k.student_reaction,
           'author_role', k.author_role,
           'note', k.note,
           'student_grade', k.student_grade,
           'student_class', k.student_class,
           'teacher_name', t.nickname,
           'created_at', k.created_at)
         order by k.occurred_date desc, k.created_at desc), '[]'::json)
    into v_records
    from (select * from kodr_records
           where school_id = v_school and subject_id = p_subject
           order by occurred_date desc, created_at desc
           limit greatest(1, least(coalesce(p_limit, 300), 500))) k
    left join profiles t on t.user_id = k.teacher_id;

  select coalesce(json_agg(json_build_object('label', x.behavior, 'count', x.n)
                           order by x.n desc, x.behavior), '[]'::json)
    into v_behaviors
    from (select behavior, count(*)::int n from kodr_records
           where school_id = v_school and subject_id = p_subject
           group by behavior order by n desc, behavior limit 5) x;

  select coalesce(json_agg(json_build_object('label', x.place, 'count', x.n)
                           order by x.n desc, x.place), '[]'::json)
    into v_places
    from (select place, count(*)::int n from kodr_records
           where school_id = v_school and subject_id = p_subject
             and coalesce(place, '') <> ''
           group by place order by n desc, place limit 5) x;

  return json_build_object(
    'ok', true,
    'student', v_student,
    'counts', v_counts,
    'top_behaviors', v_behaviors,
    'top_places', v_places,
    'records', v_records);
end $$;
revoke all on function kodr_subject_history(uuid, int) from public, anon;
grant execute on function kodr_subject_history(uuid, int) to authenticated;

-- ═══════════ 확인 ═══════════
--   -- 달별 건수 (화면에 나와야 하는 숫자)
--   select to_char(occurred_date, 'YYYY-MM') as ym, count(*), count(distinct subject_id)
--     from kodr_records group by 1 order by 1;
--   -- 정책: select · insert · update 만 있어야 한다
--   select policyname, cmd from pg_policies where tablename = 'kodr_records';
