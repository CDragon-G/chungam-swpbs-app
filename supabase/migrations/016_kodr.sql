-- 016_kodr.sql
-- K-ODR (한국형 행동 기록). 처벌이 아닌 '학생 지원'을 위한 관찰 기록.
-- 월 3건 이상 누적된 학생은 CICO(멘토 동행) 대상으로 자동 식별된다.

create table if not exists kodr_records (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  teacher_id uuid not null references auth.users(id) on delete set null,
  occurred_date date not null,
  place text,
  situation text,
  behavior text not null,
  immediate_response text,
  secondary_response text,
  student_reaction text,
  author_role text,
  school_responses text[] default '{}',
  needs_intervention boolean default false,   -- PBS 리더팀 판단
  note text,
  created_at timestamptz not null default now()
);

create index if not exists kodr_school_date_idx on kodr_records (school_id, occurred_date desc);
create index if not exists kodr_student_idx on kodr_records (student_id, occurred_date desc);

alter table kodr_records enable row level security;

-- 같은 학교 교사만 기록 조회/작성/수정
drop policy if exists kodr_teacher_all on kodr_records;
create policy kodr_teacher_all on kodr_records
  for all using (
    exists (
      select 1 from profiles p
      where p.user_id = auth.uid() and p.role = 'teacher'
        and p.school_id = kodr_records.school_id
    )
  ) with check (
    exists (
      select 1 from profiles p
      where p.user_id = auth.uid() and p.role = 'teacher'
        and p.school_id = kodr_records.school_id
    )
  );

-- 월별 학생별 K-ODR 집계 + 3건 이상 CICO 대상 식별
create or replace function public.kodr_monthly_summary(
  p_school_id uuid,
  p_year_month text default null
)
returns table (
  student_id uuid,
  nickname text,
  grade int,
  class_num int,
  student_num int,
  record_count int,
  needs_cico boolean
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  caller_role text;
  caller_school uuid;
  ym text := coalesce(p_year_month, to_char((now() at time zone 'Asia/Seoul'), 'YYYY-MM'));
  d_start date := to_date(ym || '-01', 'YYYY-MM-DD');
  d_end date := (to_date(ym || '-01', 'YYYY-MM-DD') + interval '1 month')::date;
begin
  select role, school_id into caller_role, caller_school
  from profiles where user_id = auth.uid();
  if caller_role <> 'teacher' or caller_school is distinct from p_school_id then
    raise exception '본인 학교 교사만 조회할 수 있어요.';
  end if;

  return query
  select p.user_id, p.nickname, p.grade, p.class_num, p.student_num,
         count(k.id)::int as record_count,
         (count(k.id) >= 3) as needs_cico
  from kodr_records k
  join profiles p on p.user_id = k.student_id
  where k.school_id = p_school_id
    and k.occurred_date >= d_start and k.occurred_date < d_end
  group by p.user_id, p.nickname, p.grade, p.class_num, p.student_num
  order by count(k.id) desc, p.grade, p.class_num, p.student_num;
end;
$$;

revoke all on function public.kodr_monthly_summary(uuid, text) from public;
grant execute on function public.kodr_monthly_summary(uuid, text) to authenticated;
