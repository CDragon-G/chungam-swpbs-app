-- 035_teacher_growth.sql
-- 교사 성장·보상 시스템:
--   1) 교사 포인트 원장 + 활동별 자동 적립 트리거 (서버측, 조작 불가)
--   2) 교사 교환소: 강화물(기프티콘 등, 관리자 등록) + 교환 신청/승인
--   3) 재능기부 원데이클래스: 개설 → 포인트로 신청 → 최소 인원 도달 시 자동 확정
--   4) 규칙 초성 퀴즈: 하루 1회, 정답 검증은 서버(결정적 키워드), 학생 +5 / 교사 +3
--
-- 포인트 설계 (노력 비례):
--   칭찬 +2(일5회) · K-ODR +10(일3건) · CICO점검 +6(일5건) · 수업맛집투표 +3
--   공지 +5(일1건) · 퀴즈정답 +3(일1회) · 클래스 개설 확정 +15

-- ═══════════ 1) 교사 포인트 원장 ═══════════
create table if not exists teacher_point_transactions (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  teacher_id uuid not null references auth.users(id) on delete cascade,
  points int not null,
  source text not null,  -- praise|kodr|cico|vote|announcement|quiz|class_host|class_enroll|exchange|refund|admin
  ref_id uuid,
  memo text,
  kst_date date not null default ((now() at time zone 'Asia/Seoul')::date),
  created_at timestamptz not null default now()
);
create index if not exists tpt_teacher_idx on teacher_point_transactions(teacher_id, created_at desc);
create index if not exists tpt_daily_idx on teacher_point_transactions(teacher_id, source, kst_date);

alter table teacher_point_transactions enable row level security;

drop policy if exists tpt_own_read on teacher_point_transactions;
create policy tpt_own_read on teacher_point_transactions
  for select using (
    teacher_id = auth.uid()
    or (is_admin_teacher() and school_id = current_profile_school())
  );
-- insert/update는 클라이언트 불가 — SECURITY DEFINER 함수/트리거만 기록

-- 적립 헬퍼: 일일 한도 내에서만 적립 (definer)
create or replace function award_teacher_points(
  p_teacher uuid, p_school uuid, p_points int,
  p_source text, p_ref uuid, p_daily_cap int
) returns void
language plpgsql security definer set search_path = public as $$
declare v_today_cnt int;
begin
  if p_teacher is null or p_school is null then return; end if;
  select count(*) into v_today_cnt
    from teacher_point_transactions
   where teacher_id = p_teacher and source = p_source
     and kst_date = (now() at time zone 'Asia/Seoul')::date
     and points > 0;
  if p_daily_cap is not null and v_today_cnt >= p_daily_cap then return; end if;
  insert into teacher_point_transactions (school_id, teacher_id, points, source, ref_id)
  values (p_school, p_teacher, p_points, p_source, p_ref);
end $$;
revoke execute on function award_teacher_points(uuid,uuid,int,text,uuid,int) from public, anon, authenticated;

-- 잔액 조회 RPC
create or replace function teacher_point_balance()
returns int language sql security definer set search_path = public as $$
  select coalesce(sum(points), 0)::int
    from teacher_point_transactions where teacher_id = auth.uid();
$$;
grant execute on function teacher_point_balance() to authenticated;

-- ── 활동별 적립 트리거 ──
create or replace function trg_award_praise() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform award_teacher_points(new.teacher_id, new.school_id, 2, 'praise', new.id, 5);
  return new;
end $$;
drop trigger if exists praise_award on praise;
create trigger praise_award after insert on praise
  for each row execute function trg_award_praise();

create or replace function trg_award_kodr() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform award_teacher_points(new.teacher_id, new.school_id, 10, 'kodr', new.id, 3);
  return new;
end $$;
drop trigger if exists kodr_award on kodr_records;
create trigger kodr_award after insert on kodr_records
  for each row execute function trg_award_kodr();

create or replace function trg_award_cico() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_mentor uuid; v_school uuid;
begin
  select mentor_id, school_id into v_mentor, v_school
    from cico_enrollments where id = new.enrollment_id;
  perform award_teacher_points(v_mentor, v_school, 6, 'cico', new.id, 5);
  return new;
end $$;
drop trigger if exists cico_award on cico_daily;
create trigger cico_award after insert on cico_daily
  for each row execute function trg_award_cico();

create or replace function trg_award_vote() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform award_teacher_points(new.teacher_id, new.school_id, 3, 'vote', new.id, null);
  return new;
end $$;
drop trigger if exists vote_award on class_votes;
create trigger vote_award after insert on class_votes
  for each row execute function trg_award_vote();

create or replace function trg_award_announcement() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform award_teacher_points(new.created_by, new.school_id, 5, 'announcement', new.id, 1);
  return new;
end $$;
drop trigger if exists announcement_award on announcements;
create trigger announcement_award after insert on announcements
  for each row execute function trg_award_announcement();

-- ═══════════ 2) 교사 교환소: 강화물 ═══════════
create table if not exists teacher_store_items (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  name text not null,
  description text,
  cost_points int not null check (cost_points > 0),
  stock int,                     -- null = 무제한
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists tsi_school_idx on teacher_store_items(school_id, is_active);

alter table teacher_store_items enable row level security;
drop policy if exists tsi_read on teacher_store_items;
create policy tsi_read on teacher_store_items
  for select using (
    school_id = current_profile_school()
    and exists (select 1 from profiles p where p.user_id = auth.uid() and p.role = 'teacher')
  );
drop policy if exists tsi_admin_write on teacher_store_items;
create policy tsi_admin_write on teacher_store_items
  for all using (is_admin_teacher() and school_id = current_profile_school())
  with check (is_admin_teacher() and school_id = current_profile_school());

create table if not exists teacher_exchanges (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  teacher_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid references teacher_store_items(id) on delete set null,
  item_name text not null,
  cost_points int not null,
  status text not null default 'pending'
    check (status in ('pending', 'fulfilled', 'cancelled')),
  requested_at timestamptz not null default now(),
  fulfilled_at timestamptz,
  fulfilled_by uuid references auth.users(id)
);
create index if not exists tex_school_idx on teacher_exchanges(school_id, status, requested_at desc);
create index if not exists tex_teacher_idx on teacher_exchanges(teacher_id, requested_at desc);

alter table teacher_exchanges enable row level security;
drop policy if exists tex_read on teacher_exchanges;
create policy tex_read on teacher_exchanges
  for select using (
    teacher_id = auth.uid()
    or (is_admin_teacher() and school_id = current_profile_school())
  );
-- 관리자: 승인/취소 처리
drop policy if exists tex_admin_update on teacher_exchanges;
create policy tex_admin_update on teacher_exchanges
  for update using (is_admin_teacher() and school_id = current_profile_school())
  with check (is_admin_teacher() and school_id = current_profile_school());

-- 교환 신청 RPC: 잔액·재고 검증 후 차감 + 신청 생성
create or replace function teacher_exchange_item(p_item_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_item teacher_store_items; v_balance int; v_school uuid; v_ex_id uuid;
begin
  select school_id into v_school from profiles
   where user_id = auth.uid() and role = 'teacher';
  if v_school is null then return json_build_object('ok', false, 'error', '교사만 이용할 수 있어요'); end if;

  select * into v_item from teacher_store_items
   where id = p_item_id and school_id = v_school and is_active for update;
  if v_item.id is null then return json_build_object('ok', false, 'error', '강화물을 찾을 수 없어요'); end if;
  if v_item.stock is not null and v_item.stock <= 0 then
    return json_build_object('ok', false, 'error', '재고가 모두 소진됐어요');
  end if;

  select coalesce(sum(points),0) into v_balance
    from teacher_point_transactions where teacher_id = auth.uid();
  if v_balance < v_item.cost_points then
    return json_build_object('ok', false, 'error', '포인트가 부족해요');
  end if;

  if v_item.stock is not null then
    update teacher_store_items set stock = stock - 1 where id = v_item.id;
  end if;
  insert into teacher_exchanges (school_id, teacher_id, item_id, item_name, cost_points)
  values (v_school, auth.uid(), v_item.id, v_item.name, v_item.cost_points)
  returning id into v_ex_id;
  insert into teacher_point_transactions (school_id, teacher_id, points, source, ref_id)
  values (v_school, auth.uid(), -v_item.cost_points, 'exchange', v_ex_id);
  return json_build_object('ok', true);
end $$;
grant execute on function teacher_exchange_item(uuid) to authenticated;

-- 교환 취소 RPC(관리자 또는 본인, pending만): 포인트·재고 환불
create or replace function teacher_exchange_cancel(p_exchange_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_ex teacher_exchanges;
begin
  select * into v_ex from teacher_exchanges where id = p_exchange_id for update;
  if v_ex.id is null or v_ex.status <> 'pending' then
    return json_build_object('ok', false, 'error', '취소할 수 없는 신청이에요');
  end if;
  if v_ex.teacher_id <> auth.uid() and not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '권한이 없어요');
  end if;
  update teacher_exchanges set status = 'cancelled' where id = v_ex.id;
  update teacher_store_items set stock = stock + 1
   where id = v_ex.item_id and stock is not null;
  insert into teacher_point_transactions (school_id, teacher_id, points, source, ref_id)
  values (v_ex.school_id, v_ex.teacher_id, v_ex.cost_points, 'refund', v_ex.id);
  return json_build_object('ok', true);
end $$;
grant execute on function teacher_exchange_cancel(uuid) to authenticated;

-- ═══════════ 3) 재능기부 원데이클래스 ═══════════
create table if not exists teacher_classes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  host_id uuid not null references auth.users(id) on delete cascade,
  title text not null,             -- 예: 배드민턴 15분 레슨
  description text,
  cost_points int not null default 10 check (cost_points >= 0),
  min_participants int not null default 3 check (min_participants >= 1),
  max_participants int,            -- null = 무제한
  duration_minutes int,
  scheduled_at timestamptz,
  location text,
  status text not null default 'recruiting'
    check (status in ('recruiting', 'confirmed', 'done', 'cancelled')),
  created_at timestamptz not null default now()
);
create index if not exists tclass_school_idx on teacher_classes(school_id, status, created_at desc);

alter table teacher_classes enable row level security;
drop policy if exists tclass_read on teacher_classes;
create policy tclass_read on teacher_classes
  for select using (
    school_id = current_profile_school()
    and exists (select 1 from profiles p where p.user_id = auth.uid() and p.role = 'teacher')
  );
drop policy if exists tclass_host_insert on teacher_classes;
create policy tclass_host_insert on teacher_classes
  for insert with check (
    host_id = auth.uid() and school_id = current_profile_school()
    and exists (select 1 from profiles p where p.user_id = auth.uid() and p.role = 'teacher')
  );
drop policy if exists tclass_host_update on teacher_classes;
create policy tclass_host_update on teacher_classes
  for update using (
    (host_id = auth.uid() or is_admin_teacher())
    and school_id = current_profile_school()
  );

create table if not exists class_enrollments (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references teacher_classes(id) on delete cascade,
  school_id uuid not null references schools(id) on delete cascade,
  teacher_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (class_id, teacher_id)
);
create index if not exists cenroll_class_idx on class_enrollments(class_id);

alter table class_enrollments enable row level security;
drop policy if exists cenroll_read on class_enrollments;
create policy cenroll_read on class_enrollments
  for select using (
    school_id = current_profile_school()
    and exists (select 1 from profiles p where p.user_id = auth.uid() and p.role = 'teacher')
  );
-- insert/delete는 RPC로만

-- 클래스 신청 RPC: 잔액·정원 검증, 차감, 최소 인원 도달 시 자동 확정(+개설자 보너스 15)
create or replace function enroll_teacher_class(p_class_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_class teacher_classes; v_balance int; v_cnt int; v_enroll_id uuid;
begin
  select * into v_class from teacher_classes
   where id = p_class_id and status = 'recruiting' for update;
  if v_class.id is null then return json_build_object('ok', false, 'error', '모집 중인 클래스가 아니에요'); end if;
  if v_class.host_id = auth.uid() then
    return json_build_object('ok', false, 'error', '내가 연 클래스에는 신청할 수 없어요');
  end if;
  if v_class.school_id <> (select school_id from profiles where user_id = auth.uid() and role = 'teacher') then
    return json_build_object('ok', false, 'error', '같은 학교 교사만 신청할 수 있어요');
  end if;
  if exists (select 1 from class_enrollments where class_id = v_class.id and teacher_id = auth.uid()) then
    return json_build_object('ok', false, 'error', '이미 신청했어요');
  end if;
  select count(*) into v_cnt from class_enrollments where class_id = v_class.id;
  if v_class.max_participants is not null and v_cnt >= v_class.max_participants then
    return json_build_object('ok', false, 'error', '정원이 가득 찼어요');
  end if;
  select coalesce(sum(points),0) into v_balance
    from teacher_point_transactions where teacher_id = auth.uid();
  if v_balance < v_class.cost_points then
    return json_build_object('ok', false, 'error', '포인트가 부족해요');
  end if;

  insert into class_enrollments (class_id, school_id, teacher_id)
  values (v_class.id, v_class.school_id, auth.uid())
  returning id into v_enroll_id;
  if v_class.cost_points > 0 then
    insert into teacher_point_transactions (school_id, teacher_id, points, source, ref_id)
    values (v_class.school_id, auth.uid(), -v_class.cost_points, 'class_enroll', v_enroll_id);
  end if;

  -- 최소 인원 도달 → 자동 확정 + 개설자 보너스
  if v_cnt + 1 >= v_class.min_participants then
    update teacher_classes set status = 'confirmed' where id = v_class.id and status = 'recruiting';
    if found then
      perform award_teacher_points(v_class.host_id, v_class.school_id, 15, 'class_host', v_class.id, null);
    end if;
  end if;
  return json_build_object('ok', true, 'confirmed', v_cnt + 1 >= v_class.min_participants);
end $$;
grant execute on function enroll_teacher_class(uuid) to authenticated;

-- 신청 취소 RPC (모집 중일 때만, 전액 환불)
create or replace function cancel_class_enrollment(p_class_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_class teacher_classes; v_enroll class_enrollments;
begin
  select * into v_class from teacher_classes where id = p_class_id for update;
  if v_class.id is null or v_class.status <> 'recruiting' then
    return json_build_object('ok', false, 'error', '모집 중일 때만 취소할 수 있어요');
  end if;
  select * into v_enroll from class_enrollments
   where class_id = p_class_id and teacher_id = auth.uid();
  if v_enroll.id is null then return json_build_object('ok', false, 'error', '신청 내역이 없어요'); end if;
  delete from class_enrollments where id = v_enroll.id;
  if v_class.cost_points > 0 then
    insert into teacher_point_transactions (school_id, teacher_id, points, source, ref_id)
    values (v_class.school_id, auth.uid(), v_class.cost_points, 'refund', v_enroll.id);
  end if;
  return json_build_object('ok', true);
end $$;
grant execute on function cancel_class_enrollment(uuid) to authenticated;

-- 클래스 취소 RPC (개설자/관리자): 신청자 전원 환불
create or replace function cancel_teacher_class(p_class_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_class teacher_classes; r record;
begin
  select * into v_class from teacher_classes where id = p_class_id for update;
  if v_class.id is null then return json_build_object('ok', false, 'error', '클래스를 찾을 수 없어요'); end if;
  if v_class.host_id <> auth.uid() and not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '권한이 없어요');
  end if;
  if v_class.status in ('cancelled', 'done') then
    return json_build_object('ok', false, 'error', '이미 종료된 클래스예요');
  end if;
  for r in select * from class_enrollments where class_id = v_class.id loop
    if v_class.cost_points > 0 then
      insert into teacher_point_transactions (school_id, teacher_id, points, source, ref_id)
      values (v_class.school_id, r.teacher_id, v_class.cost_points, 'refund', r.id);
    end if;
  end loop;
  delete from class_enrollments where class_id = v_class.id;
  update teacher_classes set status = 'cancelled' where id = v_class.id;
  return json_build_object('ok', true);
end $$;
grant execute on function cancel_teacher_class(uuid) to authenticated;

-- ═══════════ 4) 규칙 초성 퀴즈 ═══════════
create table if not exists quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  quiz_date date not null default ((now() at time zone 'Asia/Seoul')::date),
  rule_id uuid,
  correct boolean not null,
  awarded int not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, quiz_date)
);
alter table quiz_attempts enable row level security;
drop policy if exists qa_own_read on quiz_attempts;
create policy qa_own_read on quiz_attempts
  for select using (user_id = auth.uid());

-- 결정적 키워드: 규칙 문장에서 가장 긴 토큰 (동률이면 사전순 첫 번째)
-- 클라이언트도 같은 규칙으로 마스킹하므로 서버·클라이언트가 항상 일치
create or replace function quiz_keyword(p_text text)
returns text language sql immutable as $$
  select t from unnest(
    string_to_array(regexp_replace(p_text, '[^가-힣0-9A-Za-z ]', ' ', 'g'), ' ')
  ) t
  where char_length(t) >= 2
  order by char_length(t) desc, t asc
  limit 1;
$$;

-- 퀴즈 제출 RPC: 하루 1회, 정답 시 학생 +5 / 교사 +3
create or replace function submit_quiz(p_rule_id uuid, p_answer text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_profile profiles; v_rule school_rules; v_keyword text;
  v_correct boolean; v_points int := 0;
begin
  select * into v_profile from profiles where user_id = auth.uid();
  if v_profile.id is null or v_profile.school_id is null then
    return json_build_object('ok', false, 'error', '프로필을 찾을 수 없어요');
  end if;
  if exists (select 1 from quiz_attempts where user_id = auth.uid()
             and quiz_date = (now() at time zone 'Asia/Seoul')::date) then
    return json_build_object('ok', false, 'error', '오늘 퀴즈는 이미 참여했어요');
  end if;
  select * into v_rule from school_rules
   where id = p_rule_id and school_id = v_profile.school_id and is_active;
  if v_rule.id is null then return json_build_object('ok', false, 'error', '규칙을 찾을 수 없어요'); end if;

  v_keyword := quiz_keyword(v_rule.rule_text);
  v_correct := (trim(coalesce(p_answer, '')) = v_keyword);
  if v_correct then
    v_points := case when v_profile.role = 'student' then 5 else 3 end;
  end if;

  insert into quiz_attempts (school_id, user_id, rule_id, correct, awarded)
  values (v_profile.school_id, auth.uid(), p_rule_id, v_correct, v_points);

  if v_correct then
    if v_profile.role = 'student' then
      insert into point_transactions (user_id, school_id, amount, reason, period_key, description)
      values (auth.uid(), v_profile.school_id, 5, 'quiz',
              to_char((now() at time zone 'Asia/Seoul')::date, 'YYYY-MM-DD'),
              '초성 퀴즈 정답')
      on conflict do nothing;
    else
      perform award_teacher_points(auth.uid(), v_profile.school_id, 3, 'quiz', p_rule_id, 1);
    end if;
  end if;
  return json_build_object('ok', true, 'correct', v_correct,
                           'points', v_points, 'keyword', v_keyword);
end $$;
grant execute on function submit_quiz(uuid, text) to authenticated;

-- 오늘 퀴즈 참여 여부 확인 RPC
create or replace function quiz_attempted_today()
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from quiz_attempts where user_id = auth.uid()
                 and quiz_date = (now() at time zone 'Asia/Seoul')::date);
$$;
grant execute on function quiz_attempted_today() to authenticated;
