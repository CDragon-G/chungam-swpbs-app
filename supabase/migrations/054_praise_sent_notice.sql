-- 054_praise_sent_notice.sql
-- 선생님이 '내가 칭찬을 보냈는지' 를 나중에도 확인할 수 있게 한다.
--
-- 지금은 칭찬을 보내면 학생에게만 알림이 가고, 선생님 쪽에는 순간 스낵바만
-- 뜬다. 화면을 넘기면 사라져서 "아까 그 학생 칭찬한 게 맞나?" 를 확인할
-- 길이 없다. 같은 학생을 두 번 칭찬하거나, 보낸 줄 알았는데 안 보낸 일이
-- 생긴다.
--
-- 그래서
--   · 칭찬을 보내면 선생님 본인에게도 알림을 하나 남긴다 (type: praise_sent)
--   · 일괄 칭찬은 인원수만큼이 아니라 '25명에게 보냈어요' 한 건으로 남긴다
--   · 알림을 누르면 '내가 보낸 칭찬' 목록으로 간다
--
-- 알림 type 을 'praise' 가 아니라 'praise_sent' 로 둔 이유:
--   notif_dedupe_idx 가 (school_id, type, dedupe_key) 유니크라서, 학생에게
--   간 알림과 dedupe_key(=praise.id)가 같으면 선생님 알림이 조용히 버려진다.

-- ═══════════ 1) 단건 칭찬 ═══════════
create or replace function public.give_praise(
  p_student_user_id uuid,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  caller_role text;
  caller_school uuid;
  student_school uuid;
  v_praise_id uuid;
  v_count int;
  v_label text;
  b record;
begin
  select role, school_id into caller_role, caller_school
  from profiles where user_id = auth.uid();
  if caller_role is null then raise exception '로그인 상태가 아닙니다.'; end if;
  if caller_role <> 'teacher' then raise exception '교사만 칭찬할 수 있어요.'; end if;

  select school_id into student_school
  from profiles where user_id = p_student_user_id and role = 'student';
  if student_school is null then raise exception '학생을 찾을 수 없어요.'; end if;
  if student_school is distinct from caller_school then
    raise exception '같은 학교 학생만 칭찬할 수 있어요.';
  end if;
  if char_length(coalesce(trim(p_message), '')) = 0 then
    raise exception '칭찬 내용을 입력해주세요.';
  end if;

  -- 칭찬 기록
  insert into praise (school_id, teacher_id, student_id, message)
  values (caller_school, auth.uid(), p_student_user_id, trim(p_message))
  returning id into v_praise_id;

  -- +50P (칭찬마다 고유 period_key = praise id → 중복 없이 매번 적립)
  insert into point_transactions (user_id, school_id, amount, reason, period_key, description)
  values (p_student_user_id, caller_school, 50, 'praise', v_praise_id::text, '교사 칭찬');

  -- 누적 칭찬 횟수
  select count(*) into v_count from praise where student_id = p_student_user_id;

  -- 조건을 충족하는 칭찬 배지 모두 부여
  for b in
    select id from badges
    where condition_type = 'praise_count' and condition_value <= v_count
  loop
    insert into user_badges (user_id, badge_id)
    values (p_student_user_id, b.id)
    on conflict (user_id, badge_id) do nothing;
  end loop;

  -- 보낸 선생님 본인에게 확인용 알림
  select case
           when grade is not null and class_num is not null and student_num is not null
             then grade || '학년 ' || class_num || '반 ' || student_num || '번 ' || nickname
           else nickname
         end
    into v_label
    from profiles where user_id = p_student_user_id;

  perform push_notification(
    caller_school, 'user', auth.uid(), null, null,
    'praise_sent',
    '💚 칭찬을 보냈어요',
    coalesce(v_label, '학생') || ' · +50P' || E'\n' || left(trim(p_message), 80),
    '/teacher/praise-sent',
    v_praise_id::text);

  return jsonb_build_object('praise_id', v_praise_id, 'praise_count', v_count);
end;
$$;
revoke all on function public.give_praise(uuid, text) from public;
grant execute on function public.give_praise(uuid, text) to authenticated;

-- ═══════════ 2) 일괄 칭찬 — 알림은 한 건만 ═══════════
create or replace function give_praise_bulk(
  p_student_ids uuid[], p_message text)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_role text; v_school uuid;
  v_sid uuid; v_praise_id uuid; v_count int;
  v_sent int := 0;
  v_first uuid;
  b record;
begin
  select role, school_id into v_role, v_school
    from profiles where user_id = auth.uid();
  if v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '교사만 칭찬할 수 있어요');
  end if;
  if char_length(coalesce(trim(p_message), '')) = 0 then
    return json_build_object('ok', false, 'error', '칭찬 내용을 입력해주세요');
  end if;
  if array_length(p_student_ids, 1) is null then
    return json_build_object('ok', false, 'error', '학생을 선택해주세요');
  end if;
  if array_length(p_student_ids, 1) > 60 then
    return json_build_object('ok', false, 'error', '한 번에 최대 60명까지 보낼 수 있어요');
  end if;

  foreach v_sid in array p_student_ids loop
    if not exists (select 1 from profiles p
                    where p.user_id = v_sid and p.role = 'student'
                      and p.school_id = v_school) then
      continue;
    end if;

    insert into praise (school_id, teacher_id, student_id, message)
    values (v_school, auth.uid(), v_sid, trim(p_message))
    returning id into v_praise_id;
    if v_first is null then v_first := v_praise_id; end if;

    insert into point_transactions
      (user_id, school_id, amount, reason, period_key, description)
    values (v_sid, v_school, 50, 'praise', v_praise_id::text, '교사 칭찬')
    on conflict do nothing;

    select count(*) into v_count from praise where student_id = v_sid;
    for b in select id from badges
              where condition_type = 'praise_count' and condition_value <= v_count
    loop
      insert into user_badges (user_id, badge_id) values (v_sid, b.id)
      on conflict (user_id, badge_id) do nothing;
    end loop;

    v_sent := v_sent + 1;
  end loop;

  -- 60명에게 보내도 선생님 알림은 한 건이다. 알림함이 칭찬으로 도배되면
  -- 정작 확인하려던 내용이 묻힌다.
  if v_sent > 0 then
    perform push_notification(
      v_school, 'user', auth.uid(), null, null,
      'praise_sent',
      '💚 ' || v_sent || '명에게 칭찬을 보냈어요',
      '학생마다 +50P' || E'\n' || left(trim(p_message), 80),
      '/teacher/praise-sent',
      v_first::text);
  end if;

  return json_build_object('ok', true, 'sent', v_sent);
end $$;
grant execute on function give_praise_bulk(uuid[], text) to authenticated;

-- ═══════════ 3) 내가 보낸 칭찬 목록 ═══════════
create or replace function my_sent_praises(p_limit int default 100)
returns table (
  id uuid,
  student_name text,
  grade int,
  class_num int,
  student_num int,
  message text,
  created_at timestamptz
)
language sql stable security definer set search_path = public, auth as $$
  select p.id, pr.nickname, pr.grade, pr.class_num, pr.student_num,
         p.message, p.created_at
    from praise p
    join profiles pr on pr.user_id = p.student_id
   where p.teacher_id = auth.uid()
   order by p.created_at desc
   limit greatest(1, least(coalesce(p_limit, 100), 300));
$$;
grant execute on function my_sent_praises(int) to authenticated;

-- ═══════════ 4) 오늘 내가 보낸 칭찬 수 ═══════════
--   대시보드에 "오늘 3명 칭찬했어요" 를 띄우기 위한 가벼운 조회.
create or replace function my_praise_today()
returns int
language sql stable security definer set search_path = public, auth as $$
  select count(*)::int from praise
   where teacher_id = auth.uid()
     and (created_at at time zone 'Asia/Seoul')::date
         = (now() at time zone 'Asia/Seoul')::date;
$$;
grant execute on function my_praise_today() to authenticated;
