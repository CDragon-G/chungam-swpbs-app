-- 073_live_home.sql
-- 홈 화면을 살아 있게 한다.
--
-- 무엇이 문제였나
--   · 홈이 정적이었다. 누가 강화물을 교환해도, 명예 식집사가 바뀌어도 홈에서는 알 수 없었다.
--   · 학교 나무의 % 가 줄어드는 날이 있었다. 성장 점수의 일부가 '지금 상태' 로 매번 새로
--     계산되기 때문이다 (최근 30일 참여율, K-ODR 증감, 강화물 개수, 공지 개수, 절반 가입 여부).
--     학생이 늘거나, 참여가 잠깐 줄거나, 강화물 하나를 지우면 나무가 뒷걸음질했다.
--   · 담임반 화면의 학생 포인트 · 반 전체 포인트는 '잔액' 이라, 학생이 교환소에서 쓰면 줄었다.
--
-- 어떻게 바꿨나
--   1) 구름 소식 school_live_feed() — 오늘 교환 · 점검 · 칭찬 수, 방금 교환한 강화물,
--      명예 식집사 · 명예의 전당 1위가 바뀐 소식. 이름은 가려서 보낸다 (2-3 신*용).
--      학교마다 60초 동안 결과를 보관해, 홈을 연 학생이 많아도 서버가 한 번만 센다.
--   2) 줄지 않는 나무 — 이번 학년도에 한 번 오른 항목 점수 · 한 번 끝낸 미션은 내려가지 않는다.
--      (school_growth_year.floors 에 항목별 최고값을 남긴다.) 새 활동은 그대로 더해진다.
--      다음 레벨까지 칭찬 몇 번이 필요한지 앱이 계산할 수 있게 'boost' 를 함께 보낸다.
--   3) 이벤트 공지 — 공지에 이미지 · 기간 · 색 · 연결 강화물을 붙여 홈 배너로 홍보한다.
--      (예: 따뜻한 등굣길 캠페인, 어묵 교환)
--   4) 모은 포인트 — 담임반 화면에 이번 학년도에 '모은' 포인트를 함께 보낸다. 써도 줄지 않는다.
--
-- 안전
--   · 기존 함수 이름 · 반환 형태는 그대로다. 구버전 앱도 그대로 동작한다.
--   · 기록은 하나도 지우지 않는다.

-- ═══════════ 0) 인덱스 ═══════════
create index if not exists exchanges_school_requested_idx
  on point_exchanges (school_id, requested_at desc);
create index if not exists praise_mail_school_created_idx
  on praise_mail (school_id, created_at);

-- ═══════════ 1) 구름 소식 ═══════════
--   바뀐 순간을 남기는 표. 교환처럼 원래 표에 시각이 있는 것은 여기 넣지 않고 바로 읽는다.
create table if not exists school_feed_events (
  id bigserial primary key,
  school_id uuid not null references schools(id) on delete cascade,
  kind text not null,          -- honor_top (이 주의 명예 식집사) | hof_top (이달의 명예의 전당 전교 1위)
  label text not null,         -- '3-2 김*수' (가린 이름)
  detail text,                 -- '3학년 2반'
  created_at timestamptz not null default now()
);
create index if not exists school_feed_events_school_idx
  on school_feed_events (school_id, created_at desc);
alter table school_feed_events enable row level security;   -- 함수로만 읽는다

create table if not exists school_feed_cache (
  school_id uuid primary key references schools(id) on delete cascade,
  payload jsonb not null,
  state jsonb not null default '{}'::jsonb,   -- 지난번 1위들 (바뀐 것을 찾으려고)
  computed_at timestamptz not null default now()
);
alter table school_feed_cache enable row level security;    -- 함수로만 읽는다

create or replace function school_live_feed()
returns jsonb
language plpgsql volatile security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  v_key bigint;
  v_payload jsonb;
  v_state jsonb;
  v_at timestamptz;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_today_ts timestamptz;
  v_week date := date_trunc('week', (now() at time zone 'Asia/Seoul')::date)::date;
  v_month text := to_char(now() at time zone 'Asia/Seoul', 'YYYY-MM');
  v_students int; v_checkins int; v_exch int; v_praise int; v_mail int;
  v_exchanges jsonb; v_events jsonb; v_honor jsonb; v_honor_labels jsonb;
  v_hof jsonb; v_hof_uid text; v_gardener jsonb;
  v_prev_honor jsonb;
  r record;
  v_new_events int := 0;
begin
  if v_school is null then
    return jsonb_build_object('ok', false);
  end if;

  select payload, state, computed_at into v_payload, v_state, v_at
    from school_feed_cache where school_id = v_school;
  if v_payload is not null and v_at > now() - interval '60 seconds' then
    return v_payload;
  end if;
  v_state := coalesce(v_state, '{}'::jsonb);

  -- 읽기 전용으로 불리면 보관 값만 준다 (앱은 POST 로 부르므로 보통 여기 오지 않는다)
  if current_setting('transaction_read_only') = 'on' then
    return coalesce(v_payload, jsonb_build_object('ok', false));
  end if;

  -- 여러 명이 동시에 들어오면 한 명만 다시 센다. 나머지는 직전 값을 받는다.
  v_key := hashtextextended('school_live_feed:' || v_school::text, 0);
  if not pg_try_advisory_xact_lock(v_key) then
    if v_payload is not null then
      return v_payload;
    end if;
    perform pg_advisory_xact_lock(v_key);
    select payload, state, computed_at into v_payload, v_state, v_at
      from school_feed_cache where school_id = v_school;
    if v_payload is not null and v_at > now() - interval '60 seconds' then
      return v_payload;
    end if;
    v_state := coalesce(v_state, '{}'::jsonb);
  end if;

  v_today_ts := v_today::timestamp at time zone 'Asia/Seoul';

  -- ── 오늘 숫자 ──
  select count(*) into v_students from profiles
   where school_id = v_school and role = 'student' and left_at is null;
  select count(distinct user_id) into v_checkins from daily_checkins
   where school_id = v_school and checkin_date = v_today;
  select count(*) into v_exch from point_exchanges
   where school_id = v_school and requested_at >= v_today_ts and status <> 'cancelled';
  select count(*) into v_praise from praise
   where school_id = v_school and created_at >= v_today_ts;
  select count(*) into v_mail from praise_mail
   where school_id = v_school and created_at >= v_today_ts and hidden_at is null;

  -- ── 방금 교환한 강화물 (24시간, 최신 8건) ──
  select coalesce(jsonb_agg(jsonb_build_object(
           'label', t.grade || '-' || t.class_num || ' ' || mask_name(t.nickname),
           'item', t.item_name,
           'emoji', t.emoji,
           'at', t.requested_at)
         order by t.requested_at desc), '[]'::jsonb)
    into v_exchanges
    from (
      select p.grade, p.class_num, p.nickname, e.item_name, e.requested_at,
             coalesce(nullif(btrim(i.emoji), ''), '🎁') as emoji
        from point_exchanges e
        join profiles p on p.user_id = e.user_id
        left join point_store_items i on i.id = e.item_id
       where e.school_id = v_school
         and e.requested_at >= now() - interval '24 hours'
         and e.status <> 'cancelled'
         and p.role = 'student' and p.grade is not null and p.class_num is not null
       order by e.requested_at desc
       limit 8
    ) t;

  -- ── 이 주의 명예 식집사: 반마다 1위가 바뀌면 소식으로 남긴다 ──
  select coalesce(jsonb_object_agg(h.grade || '-' || h.class_num, h.user_id::text), '{}'::jsonb),
         coalesce(jsonb_agg(h.grade || '-' || h.class_num || ' ' || mask_name(h.nickname)
                            order by h.grade, h.class_num), '[]'::jsonb)
    into v_honor, v_honor_labels
    from weekly_honor_rank_cached(v_school, v_week) h
   where h.rn = 1;

  -- 주가 바뀐 첫 계산(월요일 아침)에는 모든 반이 '새 1위' 라 소식으로 남기지 않는다
  if v_state->>'week' = v_week::text then
    v_prev_honor := coalesce(v_state->'honor', '{}'::jsonb);
    for r in
      select h.grade, h.class_num, h.nickname, h.user_id
        from weekly_honor_rank_cached(v_school, v_week) h
       where h.rn = 1
         and v_prev_honor ? (h.grade || '-' || h.class_num)
         and v_prev_honor->>(h.grade || '-' || h.class_num) <> h.user_id::text
       order by h.grade, h.class_num
       limit 5
    loop
      insert into school_feed_events (school_id, kind, label, detail)
      values (v_school, 'honor_top',
              r.grade || '-' || r.class_num || ' ' || mask_name(r.nickname),
              r.grade || '학년 ' || r.class_num || '반');
      v_new_events := v_new_events + 1;
    end loop;
  end if;

  -- ── 이달의 명예의 전당 (10분마다 다시 센다) ──
  if v_state->>'hof_month' = v_month
     and (v_state->>'hof_at')::timestamptz > now() - interval '10 minutes' then
    v_hof := coalesce(v_state->'hof', 'null'::jsonb);
    v_hof_uid := v_state->>'hof_uid';
  else
    -- 한 번만 계산해서 전교 · 학년 1위를 꺼낸다
    select coalesce(jsonb_agg(jsonb_build_object(
             'scope', h.scope, 'grade', h.grade, 'uid', h.user_id,
             'label', h.grade || '-' || h.class_num || ' ' || mask_name(h.nickname))), '[]'::jsonb)
      into v_hof
      from hall_of_fame(v_school, v_month) h
     where h.scope in ('school', 'grade');

    select e->>'uid' into v_hof_uid
      from jsonb_array_elements(v_hof) e where e->>'scope' = 'school' limit 1;

    select jsonb_build_object(
             'school', (select e->>'label' from jsonb_array_elements(v_hof) e
                         where e->>'scope' = 'school' limit 1),
             'grades', coalesce((select jsonb_agg(jsonb_build_object(
                                          'grade', (e->>'grade')::int, 'label', e->>'label')
                                        order by (e->>'grade')::int)
                                   from jsonb_array_elements(v_hof) e
                                  where e->>'scope' = 'grade'), '[]'::jsonb))
      into v_hof;

    if v_state->>'hof_month' = v_month
       and v_state->>'hof_uid' is not null
       and v_hof_uid is not null
       and v_hof_uid <> v_state->>'hof_uid' then
      insert into school_feed_events (school_id, kind, label, detail)
      values (v_school, 'hof_top', v_hof->>'school', '전교');
      v_new_events := v_new_events + 1;
    end if;

    v_state := v_state || jsonb_build_object(
      'hof_month', v_month, 'hof_at', now(), 'hof', v_hof, 'hof_uid', v_hof_uid);
  end if;

  -- ── 2주 꾸준 식집사 (선정 후 3일 동안) ──
  select jsonb_build_object(
           'label', p.grade || '-' || p.class_num || ' ' || mask_name(p.nickname),
           'at', g.selected_at)
    into v_gardener
    from honor_gardener g
    join profiles p on p.user_id = g.winner_user_id
   where g.school_id = v_school
     and g.selected_at >= now() - interval '3 days'
   order by g.selected_at desc
   limit 1;

  -- ── 소식 (48시간, 최신 6건) ──
  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', t.kind, 'label', t.label, 'detail', t.detail, 'at', t.created_at)
         order by t.created_at desc), '[]'::jsonb)
    into v_events
    from (
      select kind, label, detail, created_at
        from school_feed_events
       where school_id = v_school
         and created_at >= now() - interval '48 hours'
       order by created_at desc
       limit 6
    ) t;

  -- 오래된 소식 정리 (14일)
  if v_new_events > 0 then
    delete from school_feed_events
     where school_id = v_school and created_at < now() - interval '14 days';
  end if;

  v_payload := jsonb_build_object(
    'ok', true,
    'today', jsonb_build_object(
      'students', v_students, 'checkins', v_checkins,
      'exchanges', v_exch, 'praise', v_praise, 'mail', v_mail),
    'exchanges', v_exchanges,
    'events', v_events,
    'honor_tops', v_honor_labels,
    'hof', v_hof,
    'gardener', v_gardener,
    'computed_at', now());

  v_state := v_state || jsonb_build_object('week', v_week, 'honor', v_honor);

  insert into school_feed_cache (school_id, payload, state, computed_at)
  values (v_school, v_payload, v_state, now())
  on conflict (school_id) do update
    set payload = excluded.payload, state = excluded.state,
        computed_at = excluded.computed_at;

  return v_payload;
end $$;
revoke all on function school_live_feed() from public;
grant execute on function school_live_feed() to authenticated;

-- ═══════════ 2) 줄지 않는 나무 ═══════════
--   이번 학년도에 오른 항목 점수와 끝낸 미션을 남겨, 그 아래로는 내려가지 않게 한다.
--   school_growth_year 는 학년도마다 한 줄이라 3월이 되면 자연스럽게 새로 시작한다.
--   (check_growth_level 이 쓰는 peak_* 와 따로 둔다. floors 는 서버만 쓴다.)
alter table school_growth_year
  add column if not exists floors jsonb not null default '{}'::jsonb;

create or replace function growth_apply_floor(p_school uuid, p_payload jsonb, p_save boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public, auth as $$
declare
  v_year date := (p_payload->>'year_start')::date;
  v_floors jsonb;
  v_act jsonb := coalesce(p_payload->'activity', '{}'::jsonb);
  v_new_act jsonb;
  v_missions jsonb;
  v_done jsonb;
  v_new_floors jsonb;
  v_kept jsonb := '[]'::jsonb;
  v_boost jsonb := '[]'::jsonb;
  v_score int;
  k text;
  v_cur int; v_f int; v_eff int;
  -- 항목 · 만점 · 몇 번에 1점 · 지금 횟수 키 (boost 계산용, 횟수로 셀 수 없는 항목은 null)
  b record;
begin
  if v_year is null then
    return p_payload;
  end if;

  select floors into v_floors
    from school_growth_year where school_id = p_school and year_start = v_year;
  v_floors := coalesce(v_floors, '{}'::jsonb);

  -- 미션: 한 번 끝낸 것은 끝난 것으로
  select coalesce(jsonb_agg(
           case when (m->>'done')::boolean
                  or coalesce(v_floors->'missions', '[]'::jsonb) ? (m->>'key')
                then m || '{"done": true}'::jsonb else m end
           order by ord), '[]'::jsonb)
    into v_missions
    from jsonb_array_elements(coalesce(p_payload->'missions', '[]'::jsonb)) with ordinality t(m, ord);

  select coalesce(jsonb_agg(m->>'key'), '[]'::jsonb) into v_done
    from jsonb_array_elements(v_missions) m
   where (m->>'done')::boolean;

  v_score := 10 * jsonb_array_length(v_done);
  v_new_act := v_act;
  v_new_floors := jsonb_build_object('missions', v_done);

  -- 항목 점수: 이번 학년도 최고값 아래로 내려가지 않는다
  foreach k in array array['participation_pts', 'praise_pts', 'kodr_pts', 'cico_pts',
                           'store_pts', 'exchange_pts', 'vote_pts', 'announce_pts', 'weekly_pts']
  loop
    v_cur := coalesce((v_act->>k)::int, 0);
    v_f := coalesce((v_floors->>k)::int, 0);
    v_eff := greatest(v_cur, v_f);
    if v_eff > v_cur then
      v_kept := v_kept || to_jsonb(k);
    end if;
    v_new_act := jsonb_set(v_new_act, array[k], to_jsonb(v_eff));
    v_new_floors := v_new_floors || jsonb_build_object(k, v_eff);
    v_score := v_score + v_eff;
  end loop;

  -- 다음 레벨까지 '무엇을 몇 번' 하면 되는지 — 횟수로 셀 수 있는 항목만
  --   칭찬 10번 = 1점 (25점까지) · 교환 수령 5건 = 1점 (15점까지)
  --   수업맛집 10표 = 1점 (15점까지) · 주간 개근 10회 = 1점 (10점까지)
  for b in
    select * from (values
      ('praise',   'praise_pts',   'praise_total', 10, 25),
      ('exchange', 'exchange_pts', 'exchanges',     5, 15),
      ('vote',     'vote_pts',     'votes_cast',   10, 15),
      ('weekly',   'weekly_pts',   'weekly_bonus', 10, 10)
    ) as x(name, pts_key, count_key, per, cap)
  loop
    -- 최고값으로 올려 둔 항목은 지금 횟수로 다음 1점을 셀 수 없어서 뺀다
    continue when v_kept ? b.pts_key;
    v_eff := coalesce((v_new_act->>b.pts_key)::int, 0);
    continue when v_eff >= b.cap;
    v_boost := v_boost || jsonb_build_object(
      'key', b.name,
      'per', b.per,
      'room', b.cap - v_eff,
      'carry', coalesce((v_act->>b.count_key)::int, 0) % b.per);
  end loop;

  if p_save then
    insert into school_growth_year (school_id, year_start, peak_level, peak_score, floors)
    values (p_school, v_year, 1, v_score, v_new_floors)
    on conflict (school_id, year_start) do update
      set floors = excluded.floors,
          peak_score = greatest(school_growth_year.peak_score, excluded.peak_score),
          updated_at = now();
  end if;

  return p_payload || jsonb_build_object(
    'score', v_score,
    'missions', v_missions,
    'activity', v_new_act || jsonb_build_object('kept', v_kept),
    'boost', v_boost);
end $$;
revoke all on function growth_apply_floor(uuid, jsonb, boolean) from public, anon, authenticated;

--   061 과 같고, 계산한 값에 floors 를 적용하는 것만 더했다.
create or replace function public.school_growth()
returns jsonb
language plpgsql volatile security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  v_key bigint;
  v_payload jsonb;
  v_at timestamptz;
begin
  if v_school is null then
    raise exception '로그인이 필요해요.';
  end if;

  select payload, computed_at into v_payload, v_at
    from school_growth_cache where school_id = v_school;
  if v_payload is not null and v_at > now() - interval '10 minutes'
     and v_payload ? 'boost' then          -- 073 전에 보관한 값은 다시 계산
    return v_payload;
  end if;

  -- 읽기 전용으로 불린 경우(다른 조회 함수 안) 저장하지 않고 계산만 한다
  if current_setting('transaction_read_only') = 'on' then
    return growth_apply_floor(v_school, school_growth_compute(v_school), false);
  end if;

  v_key := hashtextextended('school_growth:' || v_school::text, 0);
  if not pg_try_advisory_xact_lock(v_key) then
    -- 누군가 이미 다시 계산하는 중. 직전 값이 있으면 그걸 준다.
    if v_payload is not null then
      return v_payload;
    end if;
    perform pg_advisory_xact_lock(v_key);
    select payload, computed_at into v_payload, v_at
      from school_growth_cache where school_id = v_school;
    if v_payload is not null and v_at > now() - interval '10 minutes'
       and v_payload ? 'boost' then
      return v_payload;
    end if;
  end if;

  v_payload := growth_apply_floor(v_school, school_growth_compute(v_school), true);
  insert into school_growth_cache (school_id, payload, computed_at)
  values (v_school, v_payload, now())
  on conflict (school_id) do update
    set payload = excluded.payload, computed_at = excluded.computed_at;
  return v_payload;
end $$;
revoke all on function public.school_growth() from public;
grant execute on function public.school_growth() to authenticated;

-- ═══════════ 3) 이벤트 공지 ═══════════
--   kind = 'event' 이면 홈에 이벤트 배너로 뜬다 (event_end 가 지나면 내려간다).
alter table announcements add column if not exists kind text not null default 'notice';
do $$ begin
  alter table announcements
    add constraint announcements_kind_chk check (kind in ('notice', 'event'));
exception when duplicate_object then null; end $$;
alter table announcements add column if not exists image_url text;
alter table announcements add column if not exists event_start date;
alter table announcements add column if not exists event_end date;
alter table announcements add column if not exists theme text;
alter table announcements
  add column if not exists item_id uuid references point_store_items(id) on delete set null;

--   이벤트 이미지는 공개 버킷에 학교별 폴더로 둔다 (홍보 포스터라 누구나 봐도 되는 그림).
--   올리기 · 지우기는 그 학교 관리자 선생님만.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('notice-images', 'notice-images', true, 3145728,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists notice_images_insert on storage.objects;
create policy notice_images_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'notice-images'
    and public.is_admin_teacher()
    and (storage.foldername(name))[1] = public.current_profile_school()::text
  );

drop policy if exists notice_images_delete on storage.objects;
create policy notice_images_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'notice-images'
    and public.is_admin_teacher()
    and (storage.foldername(name))[1] = public.current_profile_school()::text
  );

-- ═══════════ 4) 모은 포인트 ═══════════
--   063 과 같고, 학생마다 이번 학년도에 '모은' 포인트(earned)와 반 합계(total_earned)를 더했다.
--   모은 포인트 = 받은 포인트 합 (교환 · 함께 키우기에 쓴 것은 빼지 않는다, 환불은 넣지 않는다).
create or replace function homeroom_overview(p_days int default 30)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid; v_grade int; v_class int;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_from date;
  v_students json;
  v_total int; v_today_cnt int;
  v_avg_part numeric; v_avg_score numeric; v_total_points bigint; v_total_earned bigint;
  v_school_days int;
  v_prev date;
  v_year_ts timestamptz := growth_year_start()::timestamp at time zone 'Asia/Seoul';
begin
  select school_id, grade, class_num into v_school, v_grade, v_class
    from profiles where user_id = auth.uid() and role = 'teacher';

  if v_school is null then
    return json_build_object('ok', false, 'reason', 'not_teacher');
  end if;
  if v_grade is null or v_class is null then
    return json_build_object('ok', false, 'reason', 'no_homeroom');
  end if;

  v_from := v_today - (greatest(1, least(p_days, 180)) - 1);
  v_prev := prev_school_day(v_school, v_today);

  -- 기간 내 수업일 수 (참여율 분모)
  select count(*) into v_school_days
    from generate_series(v_from, v_today, interval '1 day') d
   where is_school_day(v_school, d::date);
  if v_school_days = 0 then v_school_days := 1; end if;

  with stu as (
    select p.user_id, p.id as profile_id, p.nickname,
           coalesce(p.student_num, 0) as student_num
      from profiles p
     where p.school_id = v_school and p.role = 'student'
       and p.grade = v_grade and p.class_num = v_class
       and p.left_at is null
  ),
  chk as (
    select d.user_id, d.checkin_date, d.score_pct
      from daily_checkins d
      join stu on stu.user_id = d.user_id
     where d.checkin_date >= v_from
  ),
  agg as (
    select c.user_id,
           count(distinct c.checkin_date)::int as days,
           max(c.checkin_date) as last_date,
           avg(c.score_pct) as avg_score,
           bool_or(c.checkin_date = v_today) as today_done
      from chk c group by c.user_id
  ),
  cur as (
    -- 수업일 기준 연속 참여 (063). 주말·공휴일·휴업일은 건너뛴다
    select cs.user_id,
           streak_now(cs.current_days, cs.last_date, v_today, v_prev) as streak
      from checkin_streaks cs
      join stu on stu.user_id = cs.user_id
  ),
  pts as (
    select t.user_id,
           sum(t.amount)::int as bal,
           coalesce(sum(t.amount) filter (
             where t.amount > 0
               and t.reason not in ('refund', 'group_refund')
               and t.created_at >= v_year_ts), 0)::int as earned
      from point_transactions t
      join stu on stu.user_id = t.user_id
     group by t.user_id
  ),
  bdg as (
    select ub.user_id, count(*)::int as cnt
      from user_badges ub join stu on stu.user_id = ub.user_id
     group by ub.user_id
  ),
  rows_ as (
    select
      stu.user_id, stu.profile_id, stu.nickname, stu.student_num,
      coalesce(agg.days, 0) as days,
      round(100.0 * coalesce(agg.days, 0) / v_school_days)::int as part_pct,
      coalesce(round(agg.avg_score)::int, 0) as avg_score,
      coalesce(agg.today_done, false) as today_done,
      agg.last_date,
      coalesce(cur.streak, 0)::int as streak,
      coalesce(pts.bal, 0) as points,
      coalesce(pts.earned, 0) as earned,
      coalesce(bdg.cnt, 0) as badges,
      case when agg.last_date is null then 999
           else (v_today - agg.last_date)::int end as missed
    from stu
    left join agg on agg.user_id = stu.user_id
    left join cur on cur.user_id = stu.user_id
    left join pts on pts.user_id = stu.user_id
    left join bdg on bdg.user_id = stu.user_id
  )
  select
    coalesce(json_agg(to_json(r) order by r.student_num, r.nickname), '[]'::json),
    count(*), count(*) filter (where r.today_done),
    coalesce(round(avg(r.part_pct)), 0), coalesce(round(avg(r.avg_score)), 0),
    coalesce(sum(r.points), 0), coalesce(sum(r.earned), 0)
  into v_students, v_total, v_today_cnt, v_avg_part, v_avg_score,
       v_total_points, v_total_earned
  from rows_ r;

  return json_build_object(
    'ok', true,
    'grade', v_grade, 'class_num', v_class,
    'days', p_days, 'school_days', v_school_days,
    'total', v_total,
    'today_done', v_today_cnt,
    'today_pct', case when v_total = 0 then 0
                      else round(100.0 * v_today_cnt / v_total)::int end,
    'avg_participation', v_avg_part::int,
    'avg_score', v_avg_score::int,
    'total_points', v_total_points,
    'total_earned', v_total_earned,
    'students', v_students);
end $$;
grant execute on function homeroom_overview(int) to authenticated;

-- ═══════════ 확인 ═══════════
--   select school_live_feed();                        -- 앱에서 (로그인한 사용자로)
--   select school_id, year_start, floors from school_growth_year order by updated_at desc;
--   select id, public from storage.buckets where id = 'notice-images';
--   select kind, count(*) from announcements group by kind;
