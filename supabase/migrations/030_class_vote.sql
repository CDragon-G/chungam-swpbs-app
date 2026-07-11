-- 030_class_vote.sql
-- 수업맛집 투표: 수업 3끝 규칙을 잘 지킨 학급을 교사들이 매주 투표로 선정.
--   · 라운드: 집계 기간 단위 (예: "2026-1학기 중간고사 전"). 관리자가 열고 닫음.
--   · 과목: 학교별 커스텀 목록 (관리자 관리).
--   · 투표권: 교사 1인당 "주당" N표 (라운드 설정, 기본 2) — KST ISO주 기준.
--   · 같은 주에 같은 학급 중복 투표 불가. 집계는 라운드 단위 합산, 학년별 1위 선정.
--   · 실시간 집계는 관리자만, 마감 후에는 모든 교사가 열람.

-- ── 1) 과목 ──────────────────────────────────────────────────
create table if not exists vote_subjects (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  name text not null,
  order_index int not null default 0,
  created_at timestamptz not null default now(),
  unique (school_id, name)
);
alter table vote_subjects enable row level security;

drop policy if exists vs_select on vote_subjects;
create policy vs_select on vote_subjects
  for select to authenticated
  using (school_id = current_profile_school()
         and current_profile_role() = 'teacher');

drop policy if exists vs_admin_write on vote_subjects;
create policy vs_admin_write on vote_subjects
  for all to authenticated
  using (school_id = current_profile_school() and is_admin_teacher())
  with check (school_id = current_profile_school() and is_admin_teacher());

-- ── 2) 라운드 ────────────────────────────────────────────────
create table if not exists vote_rounds (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  title text not null,
  votes_per_week int not null default 2 check (votes_per_week between 1 and 20),
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now(),
  closed_at timestamptz
);
create index if not exists vote_rounds_school_idx
  on vote_rounds(school_id, status, created_at desc);
alter table vote_rounds enable row level security;

drop policy if exists vr_select on vote_rounds;
create policy vr_select on vote_rounds
  for select to authenticated
  using (school_id = current_profile_school()
         and current_profile_role() = 'teacher');

drop policy if exists vr_admin_write on vote_rounds;
create policy vr_admin_write on vote_rounds
  for all to authenticated
  using (school_id = current_profile_school() and is_admin_teacher())
  with check (school_id = current_profile_school() and is_admin_teacher());

-- ── 3) 투표 ──────────────────────────────────────────────────
create table if not exists class_votes (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references vote_rounds(id) on delete cascade,
  school_id uuid not null references schools(id) on delete cascade,
  teacher_id uuid not null references auth.users(id) on delete cascade,
  subject text not null,
  grade int not null check (grade between 1 and 6),
  class_num int not null check (class_num between 1 and 30),
  week_key text not null,   -- KST 기준 ISO주 'IYYY-IW'
  created_at timestamptz not null default now()
);
create index if not exists class_votes_round_idx
  on class_votes(round_id, grade, class_num);
create index if not exists class_votes_teacher_idx
  on class_votes(round_id, teacher_id, week_key);
alter table class_votes enable row level security;

-- 본인 투표 조회
drop policy if exists cv_select_own on class_votes;
create policy cv_select_own on class_votes
  for select to authenticated
  using (teacher_id = auth.uid());

-- 관리자는 전체 조회 (실시간 집계)
drop policy if exists cv_select_admin on class_votes;
create policy cv_select_admin on class_votes
  for select to authenticated
  using (school_id = current_profile_school() and is_admin_teacher());

-- 본인 투표 취소 (라운드가 열려 있을 때만)
drop policy if exists cv_delete_own on class_votes;
create policy cv_delete_own on class_votes
  for delete to authenticated
  using (
    teacher_id = auth.uid()
    and exists (select 1 from vote_rounds r
                where r.id = round_id and r.status = 'open')
  );
-- insert 정책 없음 → cast_class_vote RPC로만 (주당 투표권 검증)

-- ── 4) KST 주차 키 ───────────────────────────────────────────
create or replace function public.kst_week_key()
returns text
language sql stable
as $$
  select to_char((now() at time zone 'Asia/Seoul')::date, 'IYYY-IW');
$$;

-- ── 5) 투표하기 (주당 투표권·중복 검증) ──────────────────────
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

-- ── 6) 집계 (열림: 관리자만 / 마감: 모든 교사) ───────────────
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
  if v_round.status = 'open' and not is_admin_teacher() then
    raise exception '집계는 마감 후 공개돼요.';
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
