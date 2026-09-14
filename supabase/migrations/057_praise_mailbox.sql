-- 057_praise_mailbox.sql
-- 칭찬 우체통 — 학생이 같은 반 친구의 좋은 행동을 칭찬한다.
--
-- 자유 게시판은 만들지 않는다. 중학생 사이에서는 칭찬이라는 형식을 빌려
-- "○○가 △△한테만 간식 줬대요" 같은 소문이나, 겉은 칭찬이고 속은 놀림인
-- 글이 들어오기 쉽다. 금칙어 필터는 돌려 말하면 뚫린다.
--
-- 그래서 학생이 쓰는 글자가 한 자도 없다.
--   · 앱은 '문장 번호' 만 보낸다. 문장은 이 파일의 목록에서 서버가 꺼낸다.
--     앱을 조작해도 목록에 없는 말은 들어갈 수 없다.
--   · 받는 사람은 같은 반 친구만. 다른 반 소문으로 번지지 않는다.
--   · 이름을 밝힐지 익명으로 할지는 보내는 학생이 고른다.
--     다만 선생님은 익명이어도 누가 보냈는지 볼 수 있다. 장난을 막는 장치다.
--   · 한 사람이 일주일에 3번, 서로 다른 친구에게만.
--   · 포인트는 주지 않는다. 친구끼리 주고받는 품앗이가 생기지 않도록.
--   · 받은 학생은 "사실이 아니에요" 로 바로 숨길 수 있고, 담임에게 알림이 간다.
--   · 누가 몇 번 받았는지 순위는 어디에도 공개하지 않는다.

-- ═══════════ 1) 문장 목록 ═══════════
create table if not exists praise_mail_templates (
  id text primary key,
  category text not null,
  emoji text not null,
  sentence text not null,
  sort int not null default 0,
  is_active boolean not null default true
);
alter table praise_mail_templates enable row level security;
drop policy if exists pmt_read on praise_mail_templates;
create policy pmt_read on praise_mail_templates
  for select to authenticated using (is_active);

--   문장 고르는 기준
--     · 받는 학생이 '한 일' 만 쓴다. 다른 사람을 끌어들이지 않는다
--     · 외모·연애·비교로 읽힐 말이 없다 ("따뜻하게" 같은 수식어도 뺐다)
--     · 받는 학생이 먼저 잘못했다는 뜻이 섞이지 않는다 ("먼저 사과했어요" 제외)
insert into praise_mail_templates (id, category, emoji, sentence, sort) values
  ('help_1',  '도움', '🤝', '모르는 문제를 친절하게 알려줬어요', 11),
  ('help_2',  '도움', '🤝', '무거운 짐을 같이 들어줬어요', 12),
  ('help_3',  '도움', '🤝', '떨어뜨린 물건을 주워줬어요', 13),
  ('help_4',  '도움', '🤝', '준비물을 기꺼이 빌려줬어요', 14),
  ('care_1',  '배려', '💚', '이야기를 끝까지 들어줬어요', 21),
  ('care_2',  '배려', '💚', '차례를 먼저 양보해줬어요', 22),
  ('care_3',  '배려', '💚', '속상한 친구를 위로해줬어요', 23),
  ('care_4',  '배려', '💚', '함께 하자고 먼저 불러줬어요', 24),
  ('duty_1',  '책임', '🧹', '청소를 끝까지 꼼꼼하게 해줬어요', 31),
  ('duty_2',  '책임', '🧹', '맡은 역할을 성실하게 해냈어요', 32),
  ('duty_3',  '책임', '🧹', '교실 정리를 먼저 나서서 도왔어요', 33),
  ('duty_4',  '책임', '🧹', '정해진 시간과 약속을 잘 지켰어요', 34),
  ('class_1', '수업', '📚', '모둠 활동에 적극적으로 참여했어요', 41),
  ('class_2', '수업', '📚', '용기 있게 발표를 해냈어요', 42),
  ('class_3', '수업', '📚', '수업에 집중하는 모습이 멋졌어요', 43),
  ('class_4', '수업', '📚', '친구의 발표에 박수를 보내줬어요', 44),
  ('good_1',  '바른 행동', '✨', '옳은 일을 하려고 용기를 냈어요', 51),
  ('good_2',  '바른 행동', '✨', '규칙을 잘 지켜서 모범이 됐어요', 52),
  ('good_3',  '바른 행동', '✨', '먼저 밝게 인사해줬어요', 53),
  ('good_4',  '바른 행동', '✨', '고맙다는 말을 먼저 해줬어요', 54)
on conflict (id) do update
  set category = excluded.category, emoji = excluded.emoji,
      sentence = excluded.sentence, sort = excluded.sort;

-- ═══════════ 2) 편지 ═══════════
create table if not exists praise_mail (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  template_id text not null references praise_mail_templates(id),
  is_anonymous boolean not null default true,
  week_start date not null,
  read_at timestamptz,
  hidden_at timestamptz,
  hidden_by uuid references auth.users(id) on delete set null,
  hidden_reason text check (hidden_reason in ('not_true', 'teacher')),
  created_at timestamptz not null default now(),
  -- 같은 주에 같은 친구에게 두 번 보낼 수 없다
  unique (sender_id, recipient_id, week_start),
  check (sender_id <> recipient_id)
);
create index if not exists praise_mail_recipient_idx
  on praise_mail (recipient_id, created_at desc);
create index if not exists praise_mail_sender_week_idx
  on praise_mail (sender_id, week_start);

--   RLS 는 켜되 읽기 정책을 두지 않는다. 모든 접근은 아래 함수로만.
--   받은 학생이 테이블을 직접 읽을 수 있으면 익명 편지의 sender_id 가 그대로 보인다.
alter table praise_mail enable row level security;

-- ═══════════ 3) 공통 ═══════════
create or replace function praise_mail_week()
returns date
language sql stable as $$
  select date_trunc('week', (now() at time zone 'Asia/Seoul')::date)::date;
$$;

-- ═══════════ 4) 학생 — 보내기 화면 ═══════════
--   한 번에 문장 목록 · 우리 반 친구 · 이번 주 남은 횟수를 준다.
create or replace function praise_mail_home()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_me profiles;
  v_week date := praise_mail_week();
  v_used int;
  v_templates json;
  v_friends json;
begin
  select * into v_me from profiles where user_id = auth.uid();
  if v_me.user_id is null or v_me.role <> 'student' then
    return json_build_object('ok', false, 'error', '학생만 칭찬 우체통을 쓸 수 있어요');
  end if;
  if v_me.left_at is not null then
    return json_build_object('ok', false, 'error', '졸업·전출 처리된 계정이에요');
  end if;
  if v_me.grade is null or v_me.class_num is null then
    return json_build_object('ok', false, 'error', '학년·반 정보가 없어요. 선생님께 문의해 주세요');
  end if;

  select count(*)::int into v_used
    from praise_mail where sender_id = auth.uid() and week_start = v_week;

  select coalesce(json_agg(json_build_object(
           'id', t.id, 'category', t.category,
           'emoji', t.emoji, 'sentence', t.sentence)
         order by t.sort), '[]'::json)
    into v_templates
    from praise_mail_templates t where t.is_active;

  select coalesce(json_agg(json_build_object(
           'user_id', p.user_id,
           'name', p.nickname,
           'student_num', p.student_num,
           'sent', exists (select 1 from praise_mail m
                            where m.sender_id = auth.uid()
                              and m.recipient_id = p.user_id
                              and m.week_start = v_week))
         order by p.student_num nulls last, p.nickname), '[]'::json)
    into v_friends
    from profiles p
   where p.school_id = v_me.school_id
     and p.role = 'student'
     and p.left_at is null
     and p.grade = v_me.grade
     and p.class_num = v_me.class_num
     and p.user_id <> auth.uid();

  return json_build_object(
    'ok', true,
    'limit', 3,
    'used', v_used,
    'remaining', greatest(0, 3 - v_used),
    'templates', v_templates,
    'friends', v_friends);
end $$;
grant execute on function praise_mail_home() to authenticated;

-- ═══════════ 5) 학생 — 보내기 ═══════════
create or replace function send_praise_mail(
  p_recipient uuid,
  p_template text,
  p_anonymous boolean default true
)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_me profiles;
  v_to profiles;
  v_week date := praise_mail_week();
  v_used int;
  v_sentence text;
  v_id uuid;
begin
  select * into v_me from profiles where user_id = auth.uid();
  if v_me.user_id is null or v_me.role <> 'student' or v_me.left_at is not null then
    return json_build_object('ok', false, 'error', '학생만 칭찬을 보낼 수 있어요');
  end if;

  select * into v_to from profiles where user_id = p_recipient;
  if v_to.user_id is null or v_to.role <> 'student' or v_to.left_at is not null
     or v_to.school_id is distinct from v_me.school_id then
    return json_build_object('ok', false, 'error', '칭찬할 친구를 찾을 수 없어요');
  end if;
  if v_to.user_id = v_me.user_id then
    return json_build_object('ok', false, 'error', '나에게는 보낼 수 없어요');
  end if;
  -- 같은 반만
  if v_to.grade is distinct from v_me.grade
     or v_to.class_num is distinct from v_me.class_num then
    return json_build_object('ok', false, 'error', '같은 반 친구에게만 보낼 수 있어요');
  end if;

  -- 문장은 서버 목록에서만 꺼낸다
  select sentence into v_sentence from praise_mail_templates
   where id = p_template and is_active;
  if v_sentence is null then
    return json_build_object('ok', false, 'error', '문장을 다시 골라주세요');
  end if;

  -- 같은 학생이 두 번 눌러 4번째가 끼어드는 일을 막는다
  perform pg_advisory_xact_lock(hashtextextended('praise_mail:' || auth.uid()::text, 0));

  select count(*)::int into v_used
    from praise_mail where sender_id = auth.uid() and week_start = v_week;
  if v_used >= 3 then
    return json_build_object('ok', false, 'error',
      '이번 주 칭찬 3번을 모두 보냈어요. 월요일에 다시 보낼 수 있어요');
  end if;

  if exists (select 1 from praise_mail
              where sender_id = auth.uid() and recipient_id = p_recipient
                and week_start = v_week) then
    return json_build_object('ok', false, 'error',
      '이번 주에 이미 이 친구에게 보냈어요. 다른 친구를 칭찬해 주세요');
  end if;

  insert into praise_mail
    (school_id, sender_id, recipient_id, template_id, is_anonymous, week_start)
  values
    (v_me.school_id, auth.uid(), p_recipient, p_template,
     coalesce(p_anonymous, true), v_week)
  returning id into v_id;

  perform push_notification(
    v_me.school_id, 'user', p_recipient, null, null,
    'praise_mail',
    '💌 칭찬 우체통에 편지가 도착했어요',
    v_sentence,
    '/student/praise-mail',
    v_id::text);

  return json_build_object('ok', true, 'remaining', greatest(0, 2 - v_used));
end $$;
grant execute on function send_praise_mail(uuid, text, boolean) to authenticated;

-- ═══════════ 6) 학생 — 받은 편지함 ═══════════
--   익명 편지는 보낸 사람 이름을 아예 싣지 않는다.
create or replace function my_praise_mailbox(p_limit int default 50)
returns json
language sql stable security definer set search_path = public, auth as $$
  select coalesce(json_agg(row_to_json(t) order by t.created_at desc), '[]'::json)
  from (
    select m.id,
           tp.emoji,
           tp.category,
           tp.sentence,
           case when m.is_anonymous then null else s.nickname end as sender_name,
           m.created_at,
           m.read_at is not null as is_read
      from praise_mail m
      join praise_mail_templates tp on tp.id = m.template_id
      join profiles s on s.user_id = m.sender_id
     where m.recipient_id = auth.uid()
       and m.hidden_at is null
     order by m.created_at desc
     limit greatest(1, least(coalesce(p_limit, 50), 200))
  ) t;
$$;
grant execute on function my_praise_mailbox(int) to authenticated;

-- 이번 주에 내가 보낸 칭찬 (받는 친구 이름 · 문장 · 익명 여부)
create or replace function my_sent_praise_mail()
returns json
language sql stable security definer set search_path = public, auth as $$
  select coalesce(json_agg(json_build_object(
           'name', r.nickname,
           'emoji', tp.emoji,
           'sentence', tp.sentence,
           'is_anonymous', m.is_anonymous,
           'created_at', m.created_at)
         order by m.created_at desc), '[]'::json)
    from praise_mail m
    join praise_mail_templates tp on tp.id = m.template_id
    join profiles r on r.user_id = m.recipient_id
   where m.sender_id = auth.uid()
     and m.week_start = praise_mail_week();
$$;
grant execute on function my_sent_praise_mail() to authenticated;

create or replace function unread_praise_mail_count()
returns int
language sql stable security definer set search_path = public, auth as $$
  select count(*)::int from praise_mail
   where recipient_id = auth.uid() and read_at is null and hidden_at is null;
$$;
grant execute on function unread_praise_mail_count() to authenticated;

create or replace function mark_praise_mail_read()
returns void
language sql security definer set search_path = public, auth as $$
  update praise_mail set read_at = now()
   where recipient_id = auth.uid() and read_at is null;
$$;
grant execute on function mark_praise_mail_read() to authenticated;

-- ═══════════ 7) 학생 — "사실이 아니에요" ═══════════
--   받은 학생이 누르면 바로 숨기고, 담임 선생님(없으면 관리자)에게 알린다.
create or replace function hide_praise_mail(p_id uuid)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare
  v_mail praise_mail;
  v_to profiles;
  v_notified int := 0;
  t record;
begin
  select * into v_mail from praise_mail where id = p_id;
  if v_mail.id is null or v_mail.recipient_id <> auth.uid() then
    return json_build_object('ok', false, 'error', '편지를 찾을 수 없어요');
  end if;
  if v_mail.hidden_at is not null then
    return json_build_object('ok', true);
  end if;

  update praise_mail
     set hidden_at = now(), hidden_by = auth.uid(), hidden_reason = 'not_true'
   where id = p_id;

  select * into v_to from profiles where user_id = auth.uid();

  for t in
    select user_id from profiles
     where school_id = v_mail.school_id and role = 'teacher'
       and grade = v_to.grade and class_num = v_to.class_num
  loop
    perform push_notification(
      v_mail.school_id, 'user', t.user_id, null, null,
      'praise_mail_report',
      '💌 칭찬 우체통 확인이 필요해요',
      v_to.grade || '학년 ' || v_to.class_num || '반 학생이 받은 칭찬을 "사실이 아니에요" 로 숨겼어요',
      '/teacher/praise-mail',
      p_id::text || ':' || t.user_id::text);
    v_notified := v_notified + 1;
  end loop;

  if v_notified = 0 then
    perform push_notification(
      v_mail.school_id, 'admins', null, null, null,
      'praise_mail_report',
      '💌 칭찬 우체통 확인이 필요해요',
      v_to.grade || '학년 ' || v_to.class_num || '반 학생이 받은 칭찬을 "사실이 아니에요" 로 숨겼어요 (담임 미지정)',
      '/teacher/praise-mail',
      p_id::text);
  end if;

  return json_build_object('ok', true);
end $$;
grant execute on function hide_praise_mail(uuid) to authenticated;

-- ═══════════ 8) 선생님 — 학급 편지 보기 ═══════════
--   익명 편지도 보낸 학생 실명을 보여준다. 담임 또는 관리자만.
create or replace function can_see_class_mail(p_grade int, p_class int)
returns boolean
language sql stable security definer set search_path = public, auth as $$
  select is_admin_teacher()
      or exists (select 1 from profiles
                  where user_id = auth.uid() and role = 'teacher'
                    and grade = p_grade and class_num = p_class);
$$;

create or replace function class_praise_mail(p_grade int, p_class int, p_days int default 30)
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  v_items json;
begin
  if not can_see_class_mail(p_grade, p_class) then
    return json_build_object('ok', false, 'error', '담임 선생님이나 관리자만 볼 수 있어요');
  end if;

  select coalesce(json_agg(json_build_object(
           'id', m.id,
           'sender_name', s.nickname,
           'sender_num', s.student_num,
           'recipient_name', r.nickname,
           'recipient_num', r.student_num,
           'emoji', tp.emoji,
           'sentence', tp.sentence,
           'is_anonymous', m.is_anonymous,
           'hidden', m.hidden_at is not null,
           'hidden_reason', m.hidden_reason,
           'created_at', m.created_at)
         order by m.created_at desc), '[]'::json)
    into v_items
    from praise_mail m
    join praise_mail_templates tp on tp.id = m.template_id
    join profiles s on s.user_id = m.sender_id
    join profiles r on r.user_id = m.recipient_id
   where m.school_id = v_school
     and r.grade = p_grade and r.class_num = p_class
     and m.created_at >= now() - make_interval(days => greatest(1, coalesce(p_days, 30)));

  return json_build_object('ok', true, 'items', v_items);
end $$;
grant execute on function class_praise_mail(int, int, int) to authenticated;

create or replace function teacher_hide_praise_mail(p_id uuid)
returns json
language plpgsql security definer set search_path = public, auth as $$
declare v_mail praise_mail; v_to profiles;
begin
  select * into v_mail from praise_mail where id = p_id;
  if v_mail.id is null or v_mail.school_id is distinct from current_profile_school() then
    return json_build_object('ok', false, 'error', '편지를 찾을 수 없어요');
  end if;
  select * into v_to from profiles where user_id = v_mail.recipient_id;
  if not can_see_class_mail(v_to.grade, v_to.class_num) then
    return json_build_object('ok', false, 'error', '담임 선생님이나 관리자만 숨길 수 있어요');
  end if;

  update praise_mail
     set hidden_at = coalesce(hidden_at, now()),
         hidden_by = coalesce(hidden_by, auth.uid()),
         hidden_reason = coalesce(hidden_reason, 'teacher')
   where id = p_id;
  return json_build_object('ok', true);
end $$;
grant execute on function teacher_hide_praise_mail(uuid) to authenticated;

-- ═══════════ 9) 확인 ═══════════
--   select count(*) from praise_mail_templates;           -- 20
--   select * from praise_mail order by created_at desc limit 20;
