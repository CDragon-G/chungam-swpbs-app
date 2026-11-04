-- 077_sports_players.sql
-- 함께 키우기에 '스포츠 경기' 옵션 — 보탤 때 선수로 뛸지, 응원만 할지 고른다.
--
-- 왜
--   사제 경기를 함께 키우기로 열면, 뛰지 않고 보고만 싶은 학생도 포인트를 보탠다.
--   보탠 사람이 곧 선수라는 구분이 없어서, 누가 뛰는지 선생님이 따로 물어봐야 했다.
--
-- 무엇이 바뀌나
--   point_store_items.player_slots — 선수 인원. 값이 있으면 스포츠 경기다 (null = 지금처럼).
--   group_contributions.role       — 'player' 선수 · 'supporter' 응원. 지금까지의 기록은 모두 선수.
--   contribute_to_group_item(item, amount, role)
--     · 선수 자리가 다 차면 선수로는 더 들어올 수 없다. 응원은 자리를 차지하지 않는다.
--     · 응원 포인트는 목표의 30% 까지만 받는다 (2026-10-30 결정). 나머지 70% 는 선수가 모은다.
--     · 한 번 선수가 되면 계속 선수. 응원하던 학생은 자리가 남아 있으면 선수로 바꿀 수 있다
--       (이미 보탠 응원 포인트는 선수 몫으로 옮겨 센다).
--     · 구버전 앱은 역할을 보내지 않는다. 스포츠 경기에 처음 보태려 하면 업데이트를 안내한다.
--   group_item_status · group_items_progress · group_contributors 에 선수 / 응원 숫자와 역할.
--
-- 팀 만들기 · 친구 초대 · 선생님 승인은 다음 단계다 (docs/design_sports_league.md).

-- ═══════════ 1) 칸 ═══════════
alter table point_store_items add column if not exists player_slots int;
do $$ begin
  alter table point_store_items
    add constraint psi_player_slots_chk check (player_slots is null or player_slots between 1 and 60);
exception when duplicate_object then null; end $$;

alter table group_contributions add column if not exists role text not null default 'player';
do $$ begin
  alter table group_contributions
    add constraint gc_role_chk check (role in ('player','supporter'));
exception when duplicate_object then null; end $$;

-- 응원 몫 상한 (목표의 30%)
create or replace function group_supporter_cap(p_goal int)
returns int
language sql immutable as $$
  select greatest(coalesce(p_goal, 0), 0) * 30 / 100
$$;

-- ═══════════ 2) 포인트 보태기 — 역할을 함께 받는다 ═══════════
-- 인자가 바뀌므로 040 의 두 인자 함수를 지운다. 둘 다 있으면 PostgREST 가 고르지 못한다.
-- 세 번째 인자는 기본값이 있어 구버전 앱의 (item, amount) 호출도 이 함수로 온다.
drop function if exists contribute_to_group_item(uuid, int);

create or replace function contribute_to_group_item(
  p_item_id uuid, p_amount int, p_role text default null)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
  v_school uuid; v_grade int; v_class int;
  v_item record;
  v_raised int; v_mine int; v_balance int;
  v_remain int;
  v_sports boolean;
  v_my_role text;         -- 이미 보탠 역할 (없으면 null)
  v_role text := 'player';
  v_players int; v_sup_raised int; v_sup_left int;
begin
  if v_user is null then
    return json_build_object('ok', false, 'error', '로그인이 필요합니다');
  end if;
  if p_amount is null or p_amount <= 0 then
    return json_build_object('ok', false, 'error', '보탤 포인트를 입력해주세요');
  end if;
  if p_role is not null and p_role not in ('player','supporter') then
    return json_build_object('ok', false, 'error', '선수 또는 응원을 골라주세요');
  end if;

  select school_id, grade, class_num into v_school, v_grade, v_class
    from profiles where user_id = v_user;

  -- 같은 강화물에 동시에 보태도 자리 · 상한이 어긋나지 않게 먼저 잠근다
  select * into v_item from point_store_items
   where id = p_item_id and is_active = true for update;

  if v_item is null then
    return json_build_object('ok', false, 'error', '강화물을 찾을 수 없어요');
  end if;
  if v_item.item_type is distinct from 'group' then
    return json_build_object('ok', false, 'error', '함께 키우는 강화물이 아니에요');
  end if;
  if v_item.school_id is distinct from v_school then
    return json_build_object('ok', false, 'error', '다른 학교의 강화물이에요');
  end if;
  if v_item.grade is not null
     and (v_grade is distinct from v_item.grade
          or v_class is distinct from v_item.class_num) then
    return json_build_object('ok', false, 'error', '우리 반 강화물이 아니에요');
  end if;
  if v_item.achieved_at is not null then
    return json_build_object('ok', false, 'error', '이미 목표를 달성했어요');
  end if;
  if v_item.closed_at is not null then
    return json_build_object('ok', false, 'error', '마감된 강화물이에요');
  end if;

  -- 현재 모인 금액
  select coalesce(sum(amount), 0) into v_raised
    from group_contributions where item_id = p_item_id and refunded = false;
  v_remain := v_item.cost_points - v_raised;
  if v_remain <= 0 then
    return json_build_object('ok', false, 'error', '이미 목표를 달성했어요');
  end if;
  -- 남은 금액을 넘겨 받지 않는다
  if p_amount > v_remain then
    p_amount := v_remain;
  end if;

  -- ── 스포츠 경기: 선수 / 응원 ──
  v_sports := v_item.player_slots is not null;
  if v_sports then
    select case when bool_or(role = 'player') then 'player'
                when count(*) > 0 then 'supporter' end
      into v_my_role
      from group_contributions
     where item_id = p_item_id and user_id = v_user and refunded = false;

    if v_my_role = 'player' then
      v_role := 'player';                         -- 한 번 선수면 계속 선수
    elsif p_role = 'player' then
      select count(distinct user_id) into v_players
        from group_contributions
       where item_id = p_item_id and refunded = false and role = 'player';
      if v_players >= v_item.player_slots then
        return json_build_object('ok', false,
          'error', format('선수 %s명이 다 찼어요. 응원으로 보탤 수 있어요', v_item.player_slots));
      end if;
      v_role := 'player';
    elsif p_role = 'supporter' or v_my_role = 'supporter' then
      v_role := 'supporter';
    else
      return json_build_object('ok', false,
        'error', '앱을 업데이트하면 선수로 뛸지, 응원만 할지 골라서 보탤 수 있어요');
    end if;

    if v_role = 'supporter' then
      select coalesce(sum(amount), 0) into v_sup_raised
        from group_contributions
       where item_id = p_item_id and refunded = false and role = 'supporter';
      v_sup_left := group_supporter_cap(v_item.cost_points) - v_sup_raised;
      if v_sup_left <= 0 then
        return json_build_object('ok', false,
          'error', '응원 포인트가 가득 찼어요 (목표의 30%). 나머지는 선수들이 채워요');
      end if;
      if p_amount > v_sup_left then
        p_amount := v_sup_left;
      end if;
    end if;
  end if;

  -- 1인 한도
  if v_item.max_per_student is not null then
    select coalesce(sum(amount), 0) into v_mine
      from group_contributions
     where item_id = p_item_id and user_id = v_user and refunded = false;
    if v_mine + p_amount > v_item.max_per_student then
      return json_build_object('ok', false,
        'error', format('한 사람이 최대 %sP까지 보탤 수 있어요 (내가 보탠 %sP)',
                        v_item.max_per_student, v_mine));
    end if;
  end if;

  -- 잔액
  select get_user_points(v_user) into v_balance;
  if v_balance < p_amount then
    return json_build_object('ok', false,
      'error', format('포인트가 부족해요 (보유 %sP)', v_balance));
  end if;

  -- 응원하던 학생이 선수가 되면, 이미 보탠 응원 포인트도 선수 몫으로 센다
  if v_sports and v_role = 'player' and v_my_role = 'supporter' then
    update group_contributions set role = 'player'
     where item_id = p_item_id and user_id = v_user and refunded = false;
  end if;

  insert into group_contributions (item_id, user_id, school_id, amount, role)
  values (p_item_id, v_user, v_school, p_amount, v_role);

  insert into point_transactions
    (user_id, school_id, amount, reason, period_key, description)
  values
    (v_user, v_school, -p_amount, 'group_contribute',
     p_item_id::text || ':' || gen_random_uuid()::text,
     case when not v_sports then '함께 키우기: '
          when v_role = 'player' then '스포츠 경기 선수: '
          else '스포츠 경기 응원: ' end || v_item.name);

  v_raised := v_raised + p_amount;

  -- 목표 달성
  if v_raised >= v_item.cost_points then
    update point_store_items set achieved_at = now(), updated_at = now()
      where id = p_item_id;

    perform push_notification(
      v_school,
      case when v_item.grade is null then 'students' else 'class' end,
      null, v_item.grade, v_item.class_num,
      'exchange',
      case when v_sports then '⚽ 경기 성사!' else '🎉 목표 달성!' end,
      v_item.name || case when v_sports then ' — 목표를 채웠어요. 경기가 열려요!'
                          else ' — 함께 키우기 목표를 채웠어요!' end,
      '/student/store', 'grpdone:' || p_item_id::text);

    if v_item.created_by is not null then
      perform push_notification(
        v_school, 'user', v_item.created_by, null, null,
        'exchange',
        case when v_sports then '⚽ 스포츠 경기 목표 달성' else '🎉 함께 키우기 목표 달성' end,
        v_item.name || case when v_sports then ' 목표가 채워졌어요. 선수 명단을 확인하고 날짜를 정해주세요.'
                            else ' 목표가 채워졌어요. 지급 처리를 해주세요.' end,
        '/teacher/store', 'grpdoneT:' || p_item_id::text);
    end if;
  end if;

  return json_build_object(
    'ok', true, 'contributed', p_amount, 'role', v_role,
    'raised', v_raised, 'goal', v_item.cost_points,
    'achieved', v_raised >= v_item.cost_points);
end $$;
grant execute on function contribute_to_group_item(uuid, int, text) to authenticated;

-- ═══════════ 3) 현황 (학생) — 선수 / 응원 숫자와 내 역할 ═══════════
create or replace function group_item_status(p_item_id uuid)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
  v_item record;
  v_raised int; v_mine int; v_people int;
  v_players int; v_supporters int; v_sup_raised int;
  v_my_role text;
  v_top json;
begin
  select * into v_item from point_store_items where id = p_item_id;
  if v_item is null then return json_build_object('ok', false); end if;

  select coalesce(sum(amount), 0), count(distinct user_id),
         count(distinct user_id) filter (where role = 'player'),
         count(distinct user_id) filter (where role = 'supporter'),
         coalesce(sum(amount) filter (where role = 'supporter'), 0)
    into v_raised, v_people, v_players, v_supporters, v_sup_raised
    from group_contributions where item_id = p_item_id and refunded = false;

  select coalesce(sum(amount), 0),
         case when bool_or(role = 'player') then 'player'
              when count(*) > 0 then 'supporter' end
    into v_mine, v_my_role
    from group_contributions
   where item_id = p_item_id and user_id = v_user and refunded = false;

  -- 기여도 TOP 3 (닉네임 공개 — 학급 내 참여 독려 목적)
  select coalesce(json_agg(t), '[]'::json) into v_top from (
    select p.nickname, sum(g.amount)::int as amount
      from group_contributions g
      join profiles p on p.user_id = g.user_id
     where g.item_id = p_item_id and g.refunded = false
     group by p.nickname
     order by sum(g.amount) desc, min(g.created_at)
     limit 3
  ) t;

  return json_build_object(
    'ok', true,
    'goal', v_item.cost_points,
    'raised', v_raised,
    'people', v_people,
    'my_amount', v_mine,
    'max_per_student', v_item.max_per_student,
    'achieved', v_item.achieved_at is not null,
    'closed', v_item.closed_at is not null,
    'top', v_top,
    'player_slots', v_item.player_slots,
    'players', v_players,
    'supporters', v_supporters,
    'supporter_raised', v_sup_raised,
    'supporter_cap', group_supporter_cap(v_item.cost_points),
    'my_role', v_my_role);
end $$;
grant execute on function group_item_status(uuid) to authenticated;

-- ═══════════ 4) 진행 상황 (선생님 목록) ═══════════
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
           'top', coalesce(t.top, '[]'::json),
           'player_slots', i.player_slots,
           'players', coalesce(g.players, 0),
           'supporters', coalesce(g.supporters, 0),
           'supporter_raised', coalesce(g.sup_raised, 0))
         order by i.order_index), '[]'::json)
    into v_items
    from point_store_items i
    left join lateral (
      select coalesce(sum(c.amount), 0)::int as raised,
             count(distinct c.user_id)::int as people,
             (count(distinct c.user_id) filter (where c.role = 'player'))::int as players,
             (count(distinct c.user_id) filter (where c.role = 'supporter'))::int as supporters,
             coalesce(sum(c.amount) filter (where c.role = 'supporter'), 0)::int as sup_raised
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

-- ═══════════ 5) 보탠 학생 전체 명단 (선생님) — 역할 포함 ═══════════
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
           'last_at', t.last_at,
           'role', t.role)
         order by t.amount desc, t.last_at), '[]'::json)
    into v_items
    from (
      select p.nickname, p.grade, p.class_num, p.student_num,
             sum(c.amount)::int as amount,
             count(*)::int as times,
             max(c.created_at) as last_at,
             case when bool_or(c.role = 'player') then 'player' else 'supporter' end as role
        from group_contributions c
        join profiles p on p.user_id = c.user_id
       where c.item_id = p_item_id and c.refunded = false
       group by p.user_id, p.nickname, p.grade, p.class_num, p.student_num
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
    'player_slots', v_item.player_slots,
    'items', v_items);
end $$;
grant execute on function group_contributors(uuid) to authenticated;

-- ═══════════ 확인 ═══════════
--   select column_name from information_schema.columns
--    where table_name = 'point_store_items' and column_name = 'player_slots';   -- 1행
--   select pg_get_function_identity_arguments(oid) from pg_proc
--    where proname = 'contribute_to_group_item';   -- p_item_id uuid, p_amount integer, p_role text 한 줄
