-- PBS+ Initial Schema
-- SWPBS (School-Wide Positive Behavior Support) for Korean schools
-- Run this in the Supabase SQL editor for a fresh project.

-- =========================================================
-- 1. Tables
-- =========================================================

create table if not exists schools (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  region text not null,
  level text not null check (level in ('중학교', '고등학교')),
  school_code text not null unique,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  role text not null check (role in ('teacher', 'student')),
  nickname text not null,
  school_id uuid references schools(id) on delete set null,
  grade int,
  class_num int,
  student_num int,
  notify_hour int default 17,
  notify_minute int default 0,
  created_at timestamptz not null default now()
);

create index if not exists profiles_school_idx on profiles(school_id);
create index if not exists profiles_role_idx on profiles(role);

create table if not exists school_rules (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  space text not null,
  category text not null,
  rule_text text not null,
  order_index int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists school_rules_school_idx on school_rules(school_id, is_active);

create table if not exists daily_checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  school_id uuid not null references schools(id) on delete cascade,
  checkin_date date not null default current_date,
  answers jsonb not null default '{}'::jsonb,
  total_score int not null default 0,
  total_possible int not null default 0,
  score_pct float not null default 0,
  category_scores jsonb not null default '{}'::jsonb,
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, checkin_date)
);

create index if not exists checkins_school_date_idx on daily_checkins(school_id, checkin_date);
create index if not exists checkins_user_date_idx on daily_checkins(user_id, checkin_date desc);

create table if not exists badges (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null,
  icon_emoji text not null,
  condition_type text not null,
  condition_value int default 0
);

create table if not exists user_badges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id uuid not null references badges(id) on delete cascade,
  earned_at timestamptz not null default now(),
  unique (user_id, badge_id)
);

create table if not exists announcements (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  title text not null,
  body text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists announcements_school_idx on announcements(school_id, created_at desc);

-- =========================================================
-- 2. Helper functions
-- =========================================================

create or replace function current_profile_school()
returns uuid language sql stable as $$
  select school_id from profiles where user_id = auth.uid() limit 1;
$$;

create or replace function current_profile_role()
returns text language sql stable as $$
  select role from profiles where user_id = auth.uid() limit 1;
$$;

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists checkins_set_updated_at on daily_checkins;
create trigger checkins_set_updated_at
  before update on daily_checkins
  for each row execute function set_updated_at();

-- =========================================================
-- 3. Row Level Security
-- =========================================================

alter table schools enable row level security;
alter table profiles enable row level security;
alter table school_rules enable row level security;
alter table daily_checkins enable row level security;
alter table badges enable row level security;
alter table user_badges enable row level security;
alter table announcements enable row level security;

-- schools: readable by anyone (so signup can verify school_code); writable only by member teacher
drop policy if exists schools_select on schools;
create policy schools_select on schools for select using (true);

drop policy if exists schools_insert on schools;
create policy schools_insert on schools
  for insert to authenticated with check (true);

drop policy if exists schools_update on schools;
create policy schools_update on schools
  for update using (
    current_profile_role() = 'teacher' and id = current_profile_school()
  );

-- profiles: self read/write; teachers can read same-school profiles
drop policy if exists profiles_own on profiles;
create policy profiles_own on profiles
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists profiles_teacher_view on profiles;
create policy profiles_teacher_view on profiles
  for select using (
    school_id = current_profile_school()
    and current_profile_role() = 'teacher'
  );

-- school_rules: read by same-school members; write by same-school teacher
drop policy if exists school_rules_select on school_rules;
create policy school_rules_select on school_rules
  for select using (school_id = current_profile_school());

drop policy if exists school_rules_teacher_write on school_rules;
create policy school_rules_teacher_write on school_rules
  for all using (
    current_profile_role() = 'teacher' and school_id = current_profile_school()
  ) with check (
    current_profile_role() = 'teacher' and school_id = current_profile_school()
  );

-- daily_checkins: own read/write; teacher read same-school
drop policy if exists checkins_own on daily_checkins;
create policy checkins_own on daily_checkins
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists checkins_teacher_view on daily_checkins;
create policy checkins_teacher_view on daily_checkins
  for select using (
    school_id = current_profile_school()
    and current_profile_role() = 'teacher'
  );

-- badges: public read
drop policy if exists badges_public on badges;
create policy badges_public on badges for select using (true);

-- user_badges: self read/write; teacher can read same-school
drop policy if exists user_badges_own on user_badges;
create policy user_badges_own on user_badges
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists user_badges_teacher_view on user_badges;
create policy user_badges_teacher_view on user_badges
  for select using (
    current_profile_role() = 'teacher' and exists (
      select 1 from profiles p where p.user_id = user_badges.user_id and p.school_id = current_profile_school()
    )
  );

-- announcements: same-school read; teacher write
drop policy if exists announcements_school_read on announcements;
create policy announcements_school_read on announcements
  for select using (school_id = current_profile_school());

drop policy if exists announcements_teacher_write on announcements;
create policy announcements_teacher_write on announcements
  for all using (
    current_profile_role() = 'teacher' and school_id = current_profile_school()
  ) with check (
    current_profile_role() = 'teacher' and school_id = current_profile_school()
  );

-- =========================================================
-- 4. Seed badges
-- =========================================================

insert into badges (name, description, icon_emoji, condition_type, condition_value) values
  ('첫 걸음', '첫 번째 자기점검 완료!', '🌱', 'first_checkin', 1),
  ('3일 연속', '3일 연속 참여 달성!', '🔥', 'streak_3', 3),
  ('7일 연속', '7일 연속 참여 달성!', '⚡', 'streak_7', 7),
  ('30일 연속', '한 달 개근 달성!', '💎', 'streak_30', 30),
  ('완벽한 하루', '100점 달성!', '🌟', 'perfect_score', 100),
  ('주간 개근왕', '한 주 5일 모두 참여!', '🏆', 'full_week', 5),
  ('충암인', '누적 50회 참여!', '🎖️', 'total_checkins', 50)
on conflict do nothing;

-- =========================================================
-- 5. Default school rule template (called by signup-teacher flow)
-- =========================================================

create or replace function seed_default_rules(p_school_id uuid)
returns void language plpgsql security definer as $$
begin
  insert into school_rules (school_id, space, category, rule_text, order_index) values
    (p_school_id, '수업', '수업3끝', '입실끝 - 수업 종 치기 전에 자리에 앉아 준비하기', 1),
    (p_school_id, '수업', '수업3끝', '준비끝 - 교과서·필기구 미리 꺼내두기', 2),
    (p_school_id, '수업', '수업3끝', '수행끝 - 수업 활동에 끝까지 집중하기', 3),
    (p_school_id, '교실', 'M예의', '친구를 이름으로 불러요', 4),
    (p_school_id, '교실', 'R책임', '간식은 쉬는 시간에만 먹어요', 5),
    (p_school_id, '교실', 'S안전', '창문 밖으로 몸을 내밀지 않아요', 6),
    (p_school_id, '복도·계단', 'M예의', '마주치는 사람과 인사해요', 7),
    (p_school_id, '복도·계단', 'R책임', '오른쪽으로 걸어요', 8),
    (p_school_id, '복도·계단', 'S안전', '뛰지 않고 걸어 다녀요', 9),
    (p_school_id, '급식실', 'M예의', '음식을 삼킨 후에 말해요', 10),
    (p_school_id, '급식실', 'R책임', '줄 맨 뒤에서 차례를 기다려요', 11),
    (p_school_id, '급식실', 'S안전', '두 손으로 식판을 잡아요', 12),
    (p_school_id, '화장실', 'M예의', '문을 두드린 후 들어가요', 13),
    (p_school_id, '화장실', 'R책임', '휴지는 휴지통에 버려요', 14),
    (p_school_id, '화장실', 'S안전', '변기 물을 꼭 내려요', 15);
end;
$$;
