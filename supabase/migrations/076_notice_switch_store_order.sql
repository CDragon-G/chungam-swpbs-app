-- 076_notice_switch_store_order.sql
-- 1) 공지를 지우지 않고 '게시' 를 끄고 켤 수 있게 한다.
-- 2) 강화물 순서를 한 번에 저장한다 (끌어서 옮기기 · 가격순 정렬).
--
-- 왜
--   1) 끝난 공지를 내리려면 지워야 했고, 휴지통을 누르면 묻지도 않고 바로 지워졌다.
--      지난 공지를 다시 쓰거나 기록으로 남기고 싶어도 방법이 없었다.
--   2) 강화물 순서(order_index)는 있었지만 바꾸는 화면이 없었다. 등록한 순서대로만 보였다.
--
-- 무엇이 바뀌나
--   announcements.is_active — 끄면 학생에게 보이지 않는다 (홈 배너 · 공지 목록 · 이벤트 팝업).
--     학생 쪽은 서버 정책으로 막으므로 구버전 앱에서도 바로 사라진다.
--     선생님은 꺼진 공지도 목록에서 보고 다시 켤 수 있다.
--   reorder_store_items(ids) — 받은 순서대로 order_index 를 매긴다.
--     관리자 선생님은 모든 강화물, 일반 선생님은 자기가 등록한 강화물만 (지금의 편집 권한과 같다).

-- ═══════════ 1) 공지 게시 켜고 끄기 ═══════════
alter table announcements add column if not exists is_active boolean not null default true;

drop policy if exists announcements_school_read on announcements;
create policy announcements_school_read on announcements
  for select using (
    school_id = current_profile_school()
    and (is_active or current_profile_role() = 'teacher')
  );

-- ═══════════ 2) 강화물 순서 저장 ═══════════
create or replace function reorder_store_items(p_ids uuid[])
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text; v_admin boolean;
  v_changed int := 0;
  i int;
begin
  select school_id, role into v_school, v_role from profiles where user_id = auth.uid();
  if v_school is null or v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 순서를 바꿀 수 있어요');
  end if;
  v_admin := is_admin_teacher();

  for i in 1 .. coalesce(array_length(p_ids, 1), 0) loop
    update point_store_items
       set order_index = i - 1, updated_at = now()
     where id = p_ids[i]
       and school_id = v_school
       and (v_admin or created_by = auth.uid())
       and order_index is distinct from i - 1;
    if found then v_changed := v_changed + 1; end if;
  end loop;

  return json_build_object('ok', true, 'changed', v_changed);
end $$;
revoke all on function reorder_store_items(uuid[]) from public, anon;
grant execute on function reorder_store_items(uuid[]) to authenticated;

-- ═══════════ 3) 새 공지 · 새 강화물 → 휴대폰 알림 ═══════════
--   화면이 꺼져 있어도 알림이 오게 FCM 으로 보낸다 (Edge Function send-school-push).
--   앱이 공지 · 강화물을 등록한 직후 그 함수를 부르고, 함수가 아래 두 가지를 쓴다.

--   같은 공지 · 강화물을 두 번 보내지 않게 기록한다 (함수만 쓴다)
create table if not exists push_sent (
  ref text primary key,               -- 'notice:<id>' · 'store_item:<id>'
  school_id uuid references schools(id) on delete cascade,
  sent_by uuid references auth.users(id) on delete set null,
  recipients int not null default 0,
  sent_at timestamptz not null default now()
);
alter table push_sent enable row level security;   -- 정책 없음: 서비스 키로만

--   받을 사람의 기기 토큰. audience: 'school'(학생+선생님) · 'students' · 'class'
create or replace function push_tokens_for(
  p_school uuid, p_audience text, p_grade int default null, p_class int default null,
  p_except uuid default null
)
returns table (token text, role text)
language sql stable security definer set search_path = public as $$
  select distinct d.token, p.role
    from device_tokens d
    join profiles p on p.user_id = d.user_id
   where p.school_id = p_school
     and p.left_at is null
     and (p_except is null or p.user_id <> p_except)
     and case p_audience
           when 'school'   then p.role in ('student', 'teacher')
           when 'students' then p.role = 'student'
           when 'class'    then p.role = 'student' and p.grade = p_grade and p.class_num = p_class
           else false
         end;
$$;
revoke all on function push_tokens_for(uuid, text, int, int, uuid) from public, anon, authenticated;

--   새 공지도 앱 안 알림(종)에 남긴다. 새 강화물은 037 의 트리거가 이미 남긴다.
create or replace function trg_notify_announcement() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not new.is_active then return new; end if;
  perform push_notification(
    new.school_id, 'school', null, null, null,
    'notice',
    case when new.kind = 'event' then '📣 학교 이벤트' else '📢 새 공지' end,
    left(new.title, 120), null, 'ann:' || new.id::text);
  return new;
end $$;
drop trigger if exists announcement_notify on announcements;
create trigger announcement_notify after insert on announcements
  for each row execute function trg_notify_announcement();

-- ═══════════ 확인 ═══════════
--   select title, is_active from announcements order by created_at desc limit 10;
--   select name, order_index from point_store_items order by order_index;
--   select * from push_sent order by sent_at desc limit 10;   -- 휴대폰 알림을 보낸 기록
