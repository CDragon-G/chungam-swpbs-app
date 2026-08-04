-- 038_praise_teacher_name.sql
-- 학생이 "어느 선생님이 칭찬해 주셨는지" 확인할 수 있게 한다.
--   · praise.teacher_id는 auth.users를 참조해 PostgREST 조인이 안 되므로 RPC로 제공
--   · 학생은 다른 프로필을 직접 조회할 수 없으므로 SECURITY DEFINER로 이름만 노출
--   · 알림 제목에도 선생님 이름을 넣는다

-- ── 1) 내가 받은 칭찬 (보낸 선생님 이름 포함) ──
create or replace function my_praises(p_limit int default 50)
returns table (
  id uuid, message text, is_read boolean,
  created_at timestamptz, teacher_name text
)
language sql security definer set search_path = public as $$
  select p.id, p.message, p.is_read, p.created_at,
         coalesce(t.nickname, '선생님') as teacher_name
    from praise p
    left join profiles t on t.user_id = p.teacher_id
   where p.student_id = auth.uid()
   order by p.created_at desc
   limit greatest(1, least(p_limit, 200));
$$;
grant execute on function my_praises(int) to authenticated;

-- ── 2) 칭찬 알림에도 선생님 이름 ──
create or replace function trg_notify_praise() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_teacher text;
begin
  select nickname into v_teacher from profiles where user_id = new.teacher_id;
  perform push_notification(
    new.school_id, 'user', new.student_id, null, null,
    'praise',
    '💚 ' || coalesce(v_teacher, '선생님') || ' 선생님께 칭찬을 받았어요!',
    left(new.message, 120), '/student/mypage', new.id::text);
  return new;
end $$;
