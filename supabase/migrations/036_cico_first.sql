-- 036_cico_first.sql
-- 교사 포인트 재조정 + CICO 중심 개선:
--   1) CICO(+10) > K-ODR(+8) — 1주 내내 진행하는 CICO의 노력 반영
--      (CICO는 일일 점검 저장마다 적립, 하루 5건 한도)
--   2) 공지 적립 제거 + 공지 작성은 리더십팀(관리자)만 (RLS 강화)
--   3) 학교별 CICO 권장 기준 설정: schools.kodr_cico_threshold (기본 3건/월)
--      근거: 미국 PBIS 표준 실무에서 ODR 월 2~5건 학생을 Tier 2 검토 대상으로
--      권장 (Horner & Sugai). 2건=민감, 3건=균형(기본), 5건=보수적.
--   4) cico_candidates() RPC — 이달 K-ODR이 기준 이상 & CICO 미진행 학생 목록
--      (담임·리더십팀 화면에서 바로 CICO 시작)

-- ── 1) 포인트 재조정: K-ODR 10→8, CICO 6→10 ──
create or replace function trg_award_kodr() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform award_teacher_points(new.teacher_id, new.school_id, 8, 'kodr', new.id, 3);
  return new;
end $$;

create or replace function trg_award_cico() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_mentor uuid; v_school uuid;
begin
  select mentor_id, school_id into v_mentor, v_school
    from cico_enrollments where id = new.enrollment_id;
  perform award_teacher_points(v_mentor, v_school, 10, 'cico', new.id, 5);
  return new;
end $$;

-- ── 2) 공지: 적립 제거 + 관리자 전용 작성 ──
drop trigger if exists announcement_award on announcements;
drop function if exists trg_award_announcement();

drop policy if exists announcements_teacher_write on announcements;
drop policy if exists announcements_admin_write on announcements;
create policy announcements_admin_write on announcements
  for all using (is_admin_teacher() and school_id = current_profile_school())
  with check (is_admin_teacher() and school_id = current_profile_school());

-- ── 3) 학교별 CICO 권장 기준 ──
alter table schools add column if not exists kodr_cico_threshold int not null default 3
  check (kodr_cico_threshold between 1 and 10);

create or replace function set_kodr_cico_threshold(p_value int)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '리더십팀(관리자)만 변경할 수 있어요');
  end if;
  if p_value < 1 or p_value > 10 then
    return json_build_object('ok', false, 'error', '1~10건 사이로 설정해주세요');
  end if;
  update schools set kodr_cico_threshold = p_value
   where id = current_profile_school();
  return json_build_object('ok', true);
end $$;
grant execute on function set_kodr_cico_threshold(int) to authenticated;

-- ── 4) CICO 후보 자동 분류 RPC ──
-- 이달(KST) K-ODR 기록이 학교 기준 이상이면서 아직 CICO 진행 중이 아닌 학생.
create or replace function cico_candidates()
returns table (
  student_id uuid, nickname text, grade int, class_num int, student_num int,
  kodr_count bigint, threshold int
)
language sql security definer set search_path = public as $$
  with me as (
    select p.school_id from profiles p
     where p.user_id = auth.uid() and p.role = 'teacher'
  ),
  th as (
    select s.id as sid, s.kodr_cico_threshold as t
      from schools s join me on s.id = me.school_id
  )
  select p.user_id, p.nickname, p.grade, p.class_num, p.student_num,
         k.cnt, th.t
    from th
    join (
      select kr.student_id, kr.school_id, count(*) as cnt
        from kodr_records kr
       where kr.occurred_date >=
             date_trunc('month', (now() at time zone 'Asia/Seoul'))::date
       group by kr.student_id, kr.school_id
    ) k on k.school_id = th.sid and k.cnt >= th.t
    join profiles p on p.user_id = k.student_id and p.role = 'student'
   where not exists (
     select 1 from cico_enrollments e
      where e.student_id = k.student_id and e.status = 'active'
   )
   order by k.cnt desc, p.grade, p.class_num, p.student_num;
$$;
grant execute on function cico_candidates() to authenticated;
