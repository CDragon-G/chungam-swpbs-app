-- 019_cico.sql
-- Tier 2 : CICO (Check-In / Check-Out)
--   K-ODR로 선별된 학생을 멘토 교사가 매일 동행 점검하는 표적 지원.
--   설계 결정:
--     · 평가: 멘토가 하루 1회 종합 (교시별/전교사 평가 아님 → 부담 최소)
--     · 점검 항목: 학교가 이미 설정한 school_rules 재사용 (0/1/2 평가)
--     · 목표: 학생별 목표 달성률(기본 80%)
--     · 보호자: 앱 내 서명 이미지(base64) 저장
--   쓰기는 모두 SECURITY DEFINER RPC로 처리(권한·정합성 보장), 읽기는 RLS.

-- ─────────────────────────────────────────────────────────────
-- 1) 테이블
-- ─────────────────────────────────────────────────────────────
create table if not exists cico_enrollments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  mentor_id uuid references auth.users(id) on delete set null,
  goal_pct int not null default 80 check (goal_pct between 0 and 100),
  start_date date not null default ((now() at time zone 'Asia/Seoul')::date),
  end_date date,
  status text not null default 'active'
    check (status in ('active', 'graduated', 'stopped')),
  reason text,
  created_at timestamptz not null default now()
);
create index if not exists cico_enroll_school_idx on cico_enrollments(school_id, status);
create index if not exists cico_enroll_student_idx on cico_enrollments(student_id, status);

create table if not exists cico_daily (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references cico_enrollments(id) on delete cascade,
  entry_date date not null,
  checkin_note text,        -- 아침 체크인: 오늘 목표
  checkout_note text,       -- 하교 체크아웃: 멘토 피드백
  student_reflection text,  -- 학생 소감
  parent_signature text,    -- 보호자 앱 서명 (base64 PNG)
  parent_signed_at timestamptz,
  total_score int not null default 0,
  possible_score int not null default 0,
  pct numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (enrollment_id, entry_date)
);
create index if not exists cico_daily_enroll_idx on cico_daily(enrollment_id, entry_date desc);

create table if not exists cico_scores (
  id uuid primary key default gen_random_uuid(),
  daily_id uuid not null references cico_daily(id) on delete cascade,
  rule_id uuid references school_rules(id) on delete set null,
  item_label text not null,  -- 규칙 문구 스냅샷 (규칙이 나중에 바뀌어도 기록 보존)
  category text,             -- 존중/책임/안전/수업 등
  space text,                -- 장소/시간대
  score int not null check (score between 0 and 2),
  created_at timestamptz not null default now()
);
create index if not exists cico_scores_daily_idx on cico_scores(daily_id);

-- ─────────────────────────────────────────────────────────────
-- 2) RLS (읽기 전용 — 쓰기는 아래 RPC로만)
-- ─────────────────────────────────────────────────────────────
alter table cico_enrollments enable row level security;
alter table cico_daily enable row level security;
alter table cico_scores enable row level security;

-- 등록: 같은 학교 교사 조회 / 학생 본인 조회
drop policy if exists cico_enroll_teacher_read on cico_enrollments;
create policy cico_enroll_teacher_read on cico_enrollments for select
  using (exists (select 1 from profiles p
    where p.user_id = auth.uid() and p.role = 'teacher'
      and p.school_id = cico_enrollments.school_id));
drop policy if exists cico_enroll_student_read on cico_enrollments;
create policy cico_enroll_student_read on cico_enrollments for select
  using (student_id = auth.uid());

-- 일일카드: 같은 학교 교사 / 학생 본인
drop policy if exists cico_daily_teacher_read on cico_daily;
create policy cico_daily_teacher_read on cico_daily for select
  using (exists (select 1 from cico_enrollments e
    join profiles p on p.school_id = e.school_id
    where e.id = cico_daily.enrollment_id
      and p.user_id = auth.uid() and p.role = 'teacher'));
drop policy if exists cico_daily_student_read on cico_daily;
create policy cico_daily_student_read on cico_daily for select
  using (exists (select 1 from cico_enrollments e
    where e.id = cico_daily.enrollment_id and e.student_id = auth.uid()));

-- 점수: 같은 학교 교사 / 학생 본인
drop policy if exists cico_scores_teacher_read on cico_scores;
create policy cico_scores_teacher_read on cico_scores for select
  using (exists (select 1 from cico_daily d
    join cico_enrollments e on e.id = d.enrollment_id
    join profiles p on p.school_id = e.school_id
    where d.id = cico_scores.daily_id
      and p.user_id = auth.uid() and p.role = 'teacher'));
drop policy if exists cico_scores_student_read on cico_scores;
create policy cico_scores_student_read on cico_scores for select
  using (exists (select 1 from cico_daily d
    join cico_enrollments e on e.id = d.enrollment_id
    where d.id = cico_scores.daily_id and e.student_id = auth.uid()));

-- ─────────────────────────────────────────────────────────────
-- 3) RPC (쓰기)
-- ─────────────────────────────────────────────────────────────

-- CICO 시작 (교사 전용, 같은 학교 학생, 중복 진행 방지)
create or replace function cico_start(
  p_student_user_id uuid,
  p_mentor_id uuid,
  p_goal_pct int,
  p_reason text
)
returns uuid
language plpgsql security definer set search_path = public, auth
as $$
declare
  v_caller_school uuid;
  v_student_school uuid;
  v_id uuid;
begin
  select school_id into v_caller_school
  from profiles where user_id = auth.uid() and role = 'teacher';
  if v_caller_school is null then
    raise exception '교사만 CICO를 시작할 수 있어요.';
  end if;

  select school_id into v_student_school
  from profiles where user_id = p_student_user_id and role = 'student';
  if v_student_school is null then
    raise exception '학생을 찾을 수 없어요.';
  end if;
  if v_student_school is distinct from v_caller_school then
    raise exception '같은 학교 학생만 가능해요.';
  end if;

  if exists (select 1 from cico_enrollments
             where student_id = p_student_user_id and status = 'active') then
    raise exception '이미 진행 중인 CICO가 있어요.';
  end if;

  insert into cico_enrollments(school_id, student_id, mentor_id, goal_pct, reason)
  values (v_caller_school, p_student_user_id, coalesce(p_mentor_id, auth.uid()),
          coalesce(p_goal_pct, 80), p_reason)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function cico_start(uuid, uuid, int, text) from public;
grant execute on function cico_start(uuid, uuid, int, text) to authenticated;

-- 일일 카드 저장 (교사 전용): 체크인/체크아웃 + 점수 배열, 달성률 자동 계산
create or replace function cico_save_day(
  p_enrollment_id uuid,
  p_entry_date date,
  p_checkin text,
  p_checkout text,
  p_scores jsonb
)
returns jsonb
language plpgsql security definer set search_path = public, auth
as $$
declare
  v_school uuid;
  v_daily uuid;
  v_total int := 0;
  v_possible int := 0;
  v_score int;
  rec jsonb;
begin
  select school_id into v_school from cico_enrollments where id = p_enrollment_id;
  if v_school is null then raise exception 'CICO 등록을 찾을 수 없어요.'; end if;
  if not exists (select 1 from profiles p
    where p.user_id = auth.uid() and p.role = 'teacher' and p.school_id = v_school) then
    raise exception '같은 학교 교사만 기록할 수 있어요.';
  end if;

  insert into cico_daily(enrollment_id, entry_date, checkin_note, checkout_note)
  values (p_enrollment_id, p_entry_date, p_checkin, p_checkout)
  on conflict (enrollment_id, entry_date) do update
    set checkin_note = excluded.checkin_note,
        checkout_note = excluded.checkout_note,
        updated_at = now()
  returning id into v_daily;

  delete from cico_scores where daily_id = v_daily;
  for rec in select * from jsonb_array_elements(coalesce(p_scores, '[]'::jsonb))
  loop
    v_score := greatest(0, least(2, coalesce((rec->>'score')::int, 0)));
    insert into cico_scores(daily_id, rule_id, item_label, category, space, score)
    values (
      v_daily,
      nullif(rec->>'rule_id', '')::uuid,
      coalesce(rec->>'item_label', ''),
      rec->>'category',
      rec->>'space',
      v_score
    );
    v_total := v_total + v_score;
    v_possible := v_possible + 2;
  end loop;

  update cico_daily set
    total_score = v_total,
    possible_score = v_possible,
    pct = case when v_possible > 0
               then round((v_total::numeric / v_possible) * 100, 1) else 0 end,
    updated_at = now()
  where id = v_daily;

  return jsonb_build_object(
    'daily_id', v_daily, 'total', v_total, 'possible', v_possible,
    'pct', case when v_possible > 0
                then round((v_total::numeric / v_possible) * 100, 1) else 0 end);
end $$;
revoke all on function cico_save_day(uuid, date, text, text, jsonb) from public;
grant execute on function cico_save_day(uuid, date, text, text, jsonb) to authenticated;

-- 학생 소감 + 보호자 서명 (학생 본인 전용)
create or replace function cico_student_note(
  p_daily_id uuid,
  p_reflection text,
  p_signature text
)
returns void
language plpgsql security definer set search_path = public, auth
as $$
begin
  if not exists (
    select 1 from cico_daily d
    join cico_enrollments e on e.id = d.enrollment_id
    where d.id = p_daily_id and e.student_id = auth.uid()) then
    raise exception '본인 CICO 기록만 작성할 수 있어요.';
  end if;
  update cico_daily set
    student_reflection = coalesce(p_reflection, student_reflection),
    parent_signature = coalesce(p_signature, parent_signature),
    parent_signed_at = case when p_signature is not null and p_signature <> ''
                            then now() else parent_signed_at end,
    updated_at = now()
  where id = p_daily_id;
end $$;
revoke all on function cico_student_note(uuid, text, text) from public;
grant execute on function cico_student_note(uuid, text, text) to authenticated;

-- 상태 변경: 졸업/중단 (교사 전용)
create or replace function cico_set_status(p_enrollment_id uuid, p_status text)
returns void
language plpgsql security definer set search_path = public, auth
as $$
begin
  if p_status not in ('active', 'graduated', 'stopped') then
    raise exception '허용되지 않은 상태예요.';
  end if;
  if not exists (select 1 from cico_enrollments e
    join profiles p on p.school_id = e.school_id
    where e.id = p_enrollment_id and p.user_id = auth.uid() and p.role = 'teacher') then
    raise exception '권한이 없어요.';
  end if;
  update cico_enrollments set
    status = p_status,
    end_date = case when p_status <> 'active'
                    then (now() at time zone 'Asia/Seoul')::date else end_date end
  where id = p_enrollment_id;
end $$;
revoke all on function cico_set_status(uuid, text) from public;
grant execute on function cico_set_status(uuid, text) to authenticated;
