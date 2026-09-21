-- 065_group_progress_for_teachers.sql
-- 함께 키우기(단체 강화물) 진행 상황을 선생님도 본다.
--
-- 지금까지 진행률은 학생 화면에만 있었다. 학생은 group_item_status() 로 한 개씩
-- 받아 보는데, 선생님 교환소 목록에는 목표 금액만 있고 얼마나 모였는지가 없었다.
-- "언제 지급하면 되지?" 를 알 수 없어 달성한 뒤에도 한참 지나서야 처리하게 된다.
--
-- 학생용 함수를 그대로 쓰지 않고 목록용을 따로 만든다. 한 번에 받아야 강화물이
-- 여러 개여도 호출이 한 번으로 끝난다.

create or replace function group_items_progress()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_role text;
  v_items json;
begin
  select school_id, role into v_school, v_role
    from profiles where user_id = auth.uid();
  if v_school is null or v_role is distinct from 'teacher' then
    return json_build_object('ok', false, 'error', '선생님만 볼 수 있어요');
  end if;

  select coalesce(json_agg(json_build_object(
           'item_id', i.id,
           'goal', i.cost_points,
           'raised', coalesce(g.raised, 0),
           'people', coalesce(g.people, 0),
           'achieved', i.achieved_at is not null,
           'closed', i.closed_at is not null,
           'top', coalesce(t.top, '[]'::json))
         order by i.order_index), '[]'::json)
    into v_items
    from point_store_items i
    left join lateral (
      select coalesce(sum(c.amount), 0)::int as raised,
             count(distinct c.user_id)::int as people
        from group_contributions c
       where c.item_id = i.id and c.refunded = false
    ) g on true
    left join lateral (
      select json_agg(json_build_object('name', x.nickname, 'amount', x.amount)) as top
        from (
          select p.nickname, sum(c.amount)::int as amount
            from group_contributions c
            join profiles p on p.user_id = c.user_id
           where c.item_id = i.id and c.refunded = false
           group by p.nickname
           order by sum(c.amount) desc, min(c.created_at)
           limit 3
        ) x
    ) t on true
   where i.school_id = v_school and i.item_type = 'group';

  return json_build_object('ok', true, 'items', v_items);
end $$;
grant execute on function group_items_progress() to authenticated;

-- ═══════════ 확인 ═══════════
--   앱의 교환소 → 강화물 관리에서 '함께 키우기' 강화물에 막대가 보이면 적용된 것이다.
--   (SQL 에디터에서는 로그인한 선생님이 없어 ok:false 가 나온다)
