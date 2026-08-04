-- 037_notifications_center.sql
-- 1) 교환 요청 가시성: 담임은 '자기가 등록한 강화물'의 요청만, 관리자는 전체
-- 2) 알림 센터: 모든 사용자가 놓친 소식을 이력으로 확인
-- 3) 포인트 인플레이션 대책: 학기 시즌 마감 + 경제 통계
-- 4) 성장 레벨업 알림 (중복 방지)

-- ═══════════ 1) 교환 요청 가시성/처리 권한 ═══════════
-- 기존: 같은 학교 교사면 모든 교환 요청을 봤음 → 담임은 본인 강화물 것만.
drop policy if exists pe_teacher_read on point_exchanges;
create policy pe_teacher_read on point_exchanges
  for select using (
    school_id = current_profile_school()
    and current_profile_role() = 'teacher'
    and (
      is_admin_teacher()
      or exists (
        select 1 from point_store_items i
         where i.id = point_exchanges.item_id
           and i.created_by = auth.uid()
      )
    )
  );

-- 담임도 자기 강화물의 교환은 직접 지급 처리/취소할 수 있어야 한다.
drop policy if exists pe_owner_manage on point_exchanges;
create policy pe_owner_manage on point_exchanges
  for update using (
    school_id = current_profile_school()
    and current_profile_role() = 'teacher'
    and exists (
      select 1 from point_store_items i
       where i.id = point_exchanges.item_id
         and i.created_by = auth.uid()
    )
  );

-- ═══════════ 2) 알림 센터 ═══════════
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  -- 수신 대상: user(개인) | school(전체) | students | teachers | admins | class
  audience text not null default 'school'
    check (audience in ('user','school','students','teachers','admins','class')),
  target_user_id uuid references auth.users(id) on delete cascade,
  grade int,
  class_num int,
  type text not null,          -- praise|store_item|rule|growth|exchange|lounge|notice
  title text not null,
  body text,
  route text,                  -- 탭하면 이동할 앱 경로
  dedupe_key text,             -- 같은 사건 중복 삽입 방지
  created_at timestamptz not null default now()
);
create index if not exists notif_school_idx
  on notifications(school_id, created_at desc);
create index if not exists notif_target_idx
  on notifications(target_user_id, created_at desc);
create unique index if not exists notif_dedupe_idx
  on notifications(school_id, type, dedupe_key) where dedupe_key is not null;

alter table notifications enable row level security;

drop policy if exists notif_read on notifications;
create policy notif_read on notifications
  for select using (
    school_id = current_profile_school()
    and (
      (audience = 'user' and target_user_id = auth.uid())
      or audience = 'school'
      or (audience = 'students' and current_profile_role() = 'student')
      or (audience = 'teachers' and current_profile_role() = 'teacher')
      or (audience = 'admins' and is_admin_teacher())
      or (audience = 'class' and exists (
            select 1 from profiles p
             where p.user_id = auth.uid()
               and p.grade = notifications.grade
               and p.class_num = notifications.class_num))
    )
  );
-- insert는 트리거(SECURITY DEFINER)만

create table if not exists notification_reads (
  notification_id uuid not null references notifications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (notification_id, user_id)
);
alter table notification_reads enable row level security;
drop policy if exists nread_own on notification_reads;
create policy nread_own on notification_reads
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 알림 생성 헬퍼 (definer)
create or replace function push_notification(
  p_school uuid, p_audience text, p_target uuid,
  p_grade int, p_class int,
  p_type text, p_title text, p_body text, p_route text, p_dedupe text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_school is null then return; end if;
  insert into notifications
    (school_id, audience, target_user_id, grade, class_num,
     type, title, body, route, dedupe_key)
  values
    (p_school, p_audience, p_target, p_grade, p_class,
     p_type, p_title, p_body, p_route, p_dedupe)
  on conflict do nothing;
end $$;
revoke execute on function
  push_notification(uuid,text,uuid,int,int,text,text,text,text,text)
  from public, anon, authenticated;

-- ── 내 알림 목록 (읽음 여부 포함) ──
create or replace function my_notifications(p_limit int default 50)
returns table (
  id uuid, type text, title text, body text, route text,
  created_at timestamptz, is_read boolean
)
language sql security definer set search_path = public as $$
  select n.id, n.type, n.title, n.body, n.route, n.created_at,
         (r.user_id is not null) as is_read
    from notifications n
    left join notification_reads r
      on r.notification_id = n.id and r.user_id = auth.uid()
   where n.school_id = current_profile_school()
     and (
       (n.audience = 'user' and n.target_user_id = auth.uid())
       or n.audience = 'school'
       or (n.audience = 'students' and current_profile_role() = 'student')
       or (n.audience = 'teachers' and current_profile_role() = 'teacher')
       or (n.audience = 'admins' and is_admin_teacher())
       or (n.audience = 'class' and exists (
             select 1 from profiles p
              where p.user_id = auth.uid()
                and p.grade = n.grade and p.class_num = n.class_num))
     )
   order by n.created_at desc
   limit greatest(1, least(p_limit, 200));
$$;
grant execute on function my_notifications(int) to authenticated;

create or replace function unread_notification_count()
returns int language sql security definer set search_path = public as $$
  select count(*)::int from my_notifications(200) where not is_read;
$$;
grant execute on function unread_notification_count() to authenticated;

create or replace function mark_notifications_read()
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into notification_reads (notification_id, user_id)
  select n.id, auth.uid() from my_notifications(200) n where not n.is_read
  on conflict do nothing;
end $$;
grant execute on function mark_notifications_read() to authenticated;

-- ── 트리거: 칭찬 → 학생 개인 ──
create or replace function trg_notify_praise() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform push_notification(
    new.school_id, 'user', new.student_id, null, null,
    'praise', '💚 선생님께 칭찬을 받았어요!',
    left(new.message, 120), '/student/mypage', new.id::text);
  return new;
end $$;
drop trigger if exists praise_notify on praise;
create trigger praise_notify after insert on praise
  for each row execute function trg_notify_praise();

-- ── 트리거: 새 강화물 등록 → 학생(학급 또는 전교) ──
create or replace function trg_notify_store_item() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not new.is_active then return new; end if;
  if new.grade is not null and new.class_num is not null then
    perform push_notification(
      new.school_id, 'class', null, new.grade, new.class_num,
      'store_item', '🎁 우리 반 새 강화물이 등록됐어요',
      new.name || ' · ' || new.cost_points || 'P',
      '/student/store', new.id::text);
  else
    perform push_notification(
      new.school_id, 'students', null, null, null,
      'store_item', '🎁 학교 교환소에 새 강화물이 등록됐어요',
      new.name || ' · ' || new.cost_points || 'P',
      '/student/store', new.id::text);
  end if;
  return new;
end $$;
drop trigger if exists store_item_notify on point_store_items;
create trigger store_item_notify after insert on point_store_items
  for each row execute function trg_notify_store_item();

-- ── 트리거: 규칙 추가/수정 → 학교 전체 ──
create or replace function trg_notify_rule() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform push_notification(
      new.school_id, 'school', null, null, null,
      'rule', '📖 우리 학교 규칙이 추가됐어요',
      '[' || new.space || '] ' || left(new.rule_text, 100),
      '/student/rules', 'add-' || new.id::text);
  elsif new.rule_text is distinct from old.rule_text then
    perform push_notification(
      new.school_id, 'school', null, null, null,
      'rule', '📖 규칙이 수정됐어요',
      '[' || new.space || '] ' || left(new.rule_text, 100),
      '/student/rules',
      'edit-' || new.id::text || '-' ||
        to_char(now() at time zone 'Asia/Seoul', 'YYYYMMDDHH24MI'));
  end if;
  return new;
end $$;
drop trigger if exists rule_notify on school_rules;
create trigger rule_notify after insert or update on school_rules
  for each row execute function trg_notify_rule();

-- ── 트리거: 학생 교환 신청 → 강화물 등록 교사(없으면 관리자) ──
create or replace function trg_notify_exchange() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_owner uuid; v_student text;
begin
  select created_by into v_owner from point_store_items where id = new.item_id;
  select nickname into v_student from profiles where user_id = new.user_id;
  if v_owner is not null then
    perform push_notification(
      new.school_id, 'user', v_owner, null, null,
      'exchange', '🛍️ 교환 요청이 도착했어요',
      coalesce(v_student, '학생') || ' · ' || new.item_name ||
        ' (' || new.cost_points || 'P)',
      '/teacher/store', new.id::text);
  else
    perform push_notification(
      new.school_id, 'admins', null, null, null,
      'exchange', '🛍️ 교환 요청이 도착했어요',
      coalesce(v_student, '학생') || ' · ' || new.item_name ||
        ' (' || new.cost_points || 'P)',
      '/teacher/store', new.id::text);
  end if;
  return new;
end $$;
drop trigger if exists exchange_notify on point_exchanges;
create trigger exchange_notify after insert on point_exchanges
  for each row execute function trg_notify_exchange();

-- ── 트리거: 교사 라운지 교환 신청 → 리더십팀(관리자) ──
create or replace function trg_notify_teacher_exchange() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  select nickname into v_name from profiles where user_id = new.teacher_id;
  perform push_notification(
    new.school_id, 'admins', null, null, null,
    'lounge', '🎁 교사 강화물 교환 신청',
    coalesce(v_name, '선생님') || ' · ' || new.item_name ||
      ' (' || new.cost_points || 'P)',
    '/teacher/lounge', new.id::text);
  return new;
end $$;
drop trigger if exists teacher_exchange_notify on teacher_exchanges;
create trigger teacher_exchange_notify after insert on teacher_exchanges
  for each row execute function trg_notify_teacher_exchange();

-- ── 트리거: 교사 강화물 등록 → 전체 교사 ──
create or replace function trg_notify_teacher_item() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform push_notification(
    new.school_id, 'teachers', null, null, null,
    'lounge', '🎁 교사 라운지에 새 강화물이 등록됐어요',
    new.name || ' · ' || new.cost_points || 'P',
    '/teacher/lounge', new.id::text);
  return new;
end $$;
drop trigger if exists teacher_item_notify on teacher_store_items;
create trigger teacher_item_notify after insert on teacher_store_items
  for each row execute function trg_notify_teacher_item();

-- ═══════════ 3) 성장 레벨업 알림 ═══════════
-- school_growth()는 stable이라 쓰기 불가 → 클라이언트가 호출하는 별도 RPC.
-- 서버가 점수를 다시 계산해 레벨을 판정하므로 조작 불가.
alter table schools
  add column if not exists notified_growth_level int not null default 0;

create or replace function notify_growth_levelup()
returns json language plpgsql security definer set search_path = public as $$
declare
  v_school uuid := current_profile_school();
  v_score int;
  v_level int;
  v_prev int;
  v_names text[] := array['씨앗','새싹','푸른 잎','어린나무','튼튼한 나무','꽃나무','열매나무'];
  v_th int[] := array[0,15,40,70,100,130,160];
  i int;
begin
  if v_school is null then return json_build_object('ok', false); end if;
  v_score := (school_growth() ->> 'score')::int;
  v_level := 1;
  for i in 1..array_length(v_th, 1) loop
    if v_score >= v_th[i] then v_level := i; end if;
  end loop;

  select notified_growth_level into v_prev from schools where id = v_school;
  if v_level > coalesce(v_prev, 0) then
    update schools set notified_growth_level = v_level where id = v_school;
    -- 첫 호출(0 → N)은 기록만 하고 알림은 보내지 않는다
    if coalesce(v_prev, 0) > 0 then
      perform push_notification(
        v_school, 'school', null, null, null,
        'growth', '🌱 우리 학교 새싹이 자랐어요!',
        'Lv.' || v_level || ' ' || v_names[v_level] || '(으)로 성장했어요. 함께 만든 결과예요!',
        null, 'lv-' || v_level::text);
      return json_build_object('ok', true, 'leveled_up', true, 'level', v_level);
    end if;
  end if;
  return json_build_object('ok', true, 'leveled_up', false, 'level', v_level);
end $$;
grant execute on function notify_growth_levelup() to authenticated;

-- ═══════════ 4) 포인트 인플레이션 대책 ═══════════
-- (a) 경제 통계 — 관리자가 강화물 가격을 판단하는 근거
create or replace function point_economy_stats()
returns json language plpgsql security definer set search_path = public as $$
declare
  v_school uuid := current_profile_school();
  v_res json;
begin
  if v_school is null or current_profile_role() <> 'teacher' then
    return json_build_object('ok', false);
  end if;
  select json_build_object(
    'ok', true,
    'students', count(*),
    'total', coalesce(sum(bal), 0),
    'avg', coalesce(round(avg(bal))::int, 0),
    'median', coalesce(
      percentile_cont(0.5) within group (order by bal)::int, 0),
    'max', coalesce(max(bal), 0),
    'rich_ratio', case when count(*) = 0 then 0
      else round(100.0 * count(*) filter (where bal >= 1000) / count(*))::int end
  ) into v_res
  from (
    select p.user_id,
           coalesce((select sum(t.amount) from point_transactions t
                      where t.user_id = p.user_id), 0) as bal
      from profiles p
     where p.school_id = v_school and p.role = 'student'
  ) s;
  return v_res;
end $$;
grant execute on function point_economy_stats() to authenticated;

-- (b) 학기 마감 — 전교생 잔여 포인트 정산(소멸) + 안내 알림
--     명예의 전당·뱃지·기록은 그대로 유지된다.
create or replace function close_point_season(p_label text default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_school uuid := current_profile_school();
  v_key text := coalesce(p_label,
    to_char((now() at time zone 'Asia/Seoul')::date, 'YYYY-MM-DD'));
  v_count int := 0;
  v_sum bigint := 0;
  r record;
begin
  if not is_admin_teacher() then
    return json_build_object('ok', false, 'error', '리더십팀(관리자)만 실행할 수 있어요');
  end if;
  for r in
    select p.user_id,
           coalesce((select sum(t.amount) from point_transactions t
                      where t.user_id = p.user_id), 0) as bal
      from profiles p
     where p.school_id = v_school and p.role = 'student'
  loop
    if r.bal > 0 then
      insert into point_transactions
        (user_id, school_id, amount, reason, period_key, description)
      values (r.user_id, v_school, -r.bal, 'season_reset', v_key, '학기 마감 정산')
      on conflict do nothing;
      v_count := v_count + 1;
      v_sum := v_sum + r.bal;
    end if;
  end loop;

  perform push_notification(
    v_school, 'students', null, null, null,
    'notice', '🌱 학기 포인트가 정산됐어요',
    '이번 학기 포인트는 마감되고 새 학기가 시작돼요. 그동안 모은 뱃지와 기록은 그대로 남아 있어요!',
    '/student/store', 'season-' || v_key);

  return json_build_object('ok', true, 'students', v_count, 'points', v_sum);
end $$;
grant execute on function close_point_season(text) to authenticated;
