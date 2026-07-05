-- 026_weekly_report.sql
-- 교사 주간 리포트 자동화의 DB 절반. (나머지는 Edge Function send-weekly-reports)
--   weekly_report_batch(): 활성 학교의 각 교사 이메일 + 학교 지난 7일 성과지표를 반환.
--   · 학교 단위 지표를 한 번 계산해 그 학교 모든 교사에게 붙여 반환.
--   · 이번 주 체크인이 0인 학교는 제외(휴일 등 노이즈 방지).
--   · 서비스성(자기 학교 데이터) 메일 → 마케팅 수신동의와 무관.
--   호출 권한: service_role(크론) 또는 운영자.

create or replace function public.weekly_report_batch()
returns table (
  teacher_email text,
  teacher_name text,
  school_id uuid,
  school_name text,
  metrics jsonb
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  d_from date := (current_date - 7);
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and coalesce(auth.jwt() ->> 'email', '') <> 'toyswar987@naver.com' then
    raise exception '권한이 없어요.';
  end if;

  return query
  with m as (
    select
      s.id as sid,
      s.name as sname,
      (select count(*) from profiles p
         where p.school_id = s.id and p.role = 'student') as students,
      (select count(distinct dc.user_id) from daily_checkins dc
         where dc.school_id = s.id and dc.checkin_date >= d_from) as active,
      (select count(*) from daily_checkins dc
         where dc.school_id = s.id and dc.checkin_date >= d_from) as checkins,
      (select coalesce(round(avg(dc.score_pct)::numeric, 1), 0) from daily_checkins dc
         where dc.school_id = s.id and dc.checkin_date >= d_from) as avg_score,
      (select count(*) from praise pz
         where pz.school_id = s.id and pz.created_at >= d_from) as praise,
      (select count(*) from kodr_records kr
         where kr.school_id = s.id and kr.occurred_date >= d_from) as kodr,
      (select count(*) from cico_enrollments ce
         where ce.school_id = s.id and ce.status = 'active') as cico_active
    from schools s
    where s.subscription_status = 'active'
  )
  select
    u.email::text,
    p.nickname,
    m.sid,
    m.sname,
    jsonb_build_object(
      'students', m.students,
      'active', m.active,
      'checkins', m.checkins,
      'avg_score', m.avg_score,
      'praise', m.praise,
      'kodr', m.kodr,
      'cico_active', m.cico_active,
      'no_checkin', greatest(m.students - m.active, 0),
      'participation',
        case when m.students > 0
             then round((m.active::numeric / m.students) * 100, 0) else 0 end
    )
  from m
  join profiles p on p.school_id = m.sid and p.role = 'teacher'
  join auth.users u on u.id = p.user_id
  where m.checkins > 0
    and coalesce(u.email, '') <> '';
end $$;
revoke all on function public.weekly_report_batch() from public;
grant execute on function public.weekly_report_batch() to authenticated, service_role;
