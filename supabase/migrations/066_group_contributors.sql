-- 066_group_contributors.sql
-- 함께 키우기 — 누가 얼마나 보탰는지 전체 명단 (선생님용)
--
-- 065 는 목록에 보여줄 상위 3명만 준다. 지급하거나 취소할 때, 또는 반에서 이야기를
-- 나눌 때는 "누가 얼마나 보탰는지" 전부 필요하다.
--
-- 학생에게는 지금처럼 상위 3명만 보인다 (group_item_status). 전체 명단은 선생님만.

create or replace function group_contributors(p_item_id uuid)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text;
  v_item point_store_items;
  v_raised int; v_people int;
  v_items json;
begin
  select school_id, role into v_school, v_role
    from profiles where user_id = auth.uid();
  if v_school is null or v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 볼 수 있어요');
  end if;

  select * into v_item from point_store_items where id = p_item_id;
  if v_item.id is null or v_item.school_id is distinct from v_school then
    return json_build_object('ok', false, 'error', '강화물을 찾을 수 없어요');
  end if;

  select coalesce(sum(c.amount), 0)::int, count(distinct c.user_id)::int
    into v_raised, v_people
    from group_contributions c
   where c.item_id = p_item_id and c.refunded = false;

  --   한 학생이 여러 번 보탰으면 합쳐서 한 줄로 보여준다.
  select coalesce(json_agg(json_build_object(
           'name', t.nickname,
           'grade', t.grade,
           'class_num', t.class_num,
           'student_num', t.student_num,
           'amount', t.amount,
           'times', t.times,
           'last_at', t.last_at)
         order by t.amount desc, t.last_at), '[]'::json)
    into v_items
    from (
      select p.nickname, p.grade, p.class_num, p.student_num,
             sum(c.amount)::int as amount,
             count(*)::int as times,
             max(c.created_at) as last_at
        from group_contributions c
        join profiles p on p.user_id = c.user_id
       where c.item_id = p_item_id and c.refunded = false
       group by p.nickname, p.grade, p.class_num, p.student_num
    ) t;

  return json_build_object(
    'ok', true,
    'name', v_item.name,
    'emoji', v_item.emoji,
    'goal', v_item.cost_points,
    'raised', v_raised,
    'people', v_people,
    'closed', v_item.closed_at is not null,
    'achieved', v_item.achieved_at is not null,
    'items', v_items);
end $$;
grant execute on function group_contributors(uuid) to authenticated;

-- ═══════════ 확인 ═══════════
--   앱의 교환소 → 강화물 관리에서 함께 키우기 막대를 누르면 명단이 열린다.
--   (SQL 에디터에서는 로그인한 선생님이 없어 ok:false 가 나온다)
