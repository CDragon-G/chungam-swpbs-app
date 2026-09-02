-- 046_quiz_flexible_answers.sql
-- 퀴즈가 너무 어렵다는 의견 반영.
--   지금은 trim(답) = 키워드 완전 일치라, 규칙 원문이 '않았어요'면
--   '않아요'는 틀린 답이 된다. 의미가 통하면 맞게 처리한다.
--
--   1) 정답 후보를 여러 개 만들어 그중 하나만 맞으면 정답
--      · 공백·문장부호 무시
--      · 한국어 종결어미(았/었/해요/합니다/세요…)를 떼고 어간끼리 비교
--   2) 힌트도 후보 길이를 모두 보여준다 → 'ㅇㅇㅇ, ㅇㅇㅇㅇ'
--   3) 규칙 초성 퀴즈 외에 학교가 직접 만드는 지식 퀴즈 추가
--      예) "충암중 수업규칙을 이르는 말은?" → "3끝"

-- ═══════════ 1) 정답 정규화 ═══════════
--   공백·문장부호를 없애고 소문자로. '3 끝' '3끝' '3-끝' 을 같게 본다.
create or replace function quiz_norm(p text)
returns text
language sql immutable as $$
  select lower(regexp_replace(coalesce(p, ''), '[^가-힣0-9a-zA-Z]', '', 'g'));
$$;
grant execute on function quiz_norm(text) to authenticated;

-- ═══════════ 2) 한국어 어간 뽑기 ═══════════
--   '않았어요' → '않'   '않아요' → '않'   '지켜요' → '지켜'
--   완벽한 형태소 분석이 아니라, 흔한 종결어미만 뒤에서 떼어낸다.
--   너무 짧아지면(1글자 미만) 원형을 그대로 둔다.
create or replace function quiz_stem(p text)
returns text
language plpgsql immutable as $$
declare
  s text := quiz_norm(p);
  endings text[] := array[
    '였습니다','았습니다','었습니다','하겠습니다','합니다','습니다','ㅂ니다',
    '였어요','았어요','었어요','해주세요','하세요','드려요','드립니다',
    '아요','어요','여요','해요','예요','이에요','에요','세요','져요','겨요',
    '한다','된다','간다','온다','는다','ㄴ다','자','요','다'
  ];
  e text;
begin
  if s = '' then return ''; end if;
  foreach e in array endings loop
    if length(s) > length(e) and right(s, length(e)) = e then
      s := left(s, length(s) - length(e));
      exit;                       -- 어미는 한 번만 뗀다
    end if;
  end loop;
  return case when length(s) = 0 then quiz_norm(p) else s end;
end $$;
grant execute on function quiz_stem(text) to authenticated;

-- ═══════════ 3) 정답 판정 ═══════════
--   완전 일치 → 정규화 일치 → 어간 일치 순으로 본다.
create or replace function quiz_is_correct(p_answer text, p_accepted text[])
returns boolean
language plpgsql immutable as $$
declare a text;
begin
  if coalesce(trim(p_answer), '') = '' then return false; end if;
  foreach a in array p_accepted loop
    if quiz_norm(p_answer) = quiz_norm(a) then return true; end if;
    -- 어간이 2글자 이상일 때만 어간 비교 (1글자면 오답이 너무 쉽게 통과)
    if length(quiz_stem(a)) >= 2 and quiz_stem(p_answer) = quiz_stem(a) then
      return true;
    end if;
  end loop;
  return false;
end $$;
grant execute on function quiz_is_correct(text, text[]) to authenticated;

-- ═══════════ 4) 학교가 직접 만드는 지식 퀴즈 ═══════════
create table if not exists quiz_questions (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  question text not null,
  answers text[] not null,           -- 정답 후보 (여러 개 = 중복정답 인정)
  hint text,                         -- 비우면 초성 힌트를 자동 생성
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (array_length(answers, 1) >= 1)
);
create index if not exists qq_school_idx on quiz_questions(school_id, is_active);
alter table quiz_questions enable row level security;

drop policy if exists qq_read on quiz_questions;
create policy qq_read on quiz_questions
  for select to authenticated
  using (school_id = current_profile_school());

drop policy if exists qq_admin_write on quiz_questions;
create policy qq_admin_write on quiz_questions
  for all to authenticated
  using (school_id = current_profile_school() and is_admin_teacher())
  with check (school_id = current_profile_school() and is_admin_teacher());

-- ═══════════ 5) 초성 변환 (힌트용) ═══════════
create or replace function quiz_chosung(p text)
returns text
language plpgsql immutable as $$
declare
  cho text[] := array['ㄱ','ㄲ','ㄴ','ㄷ','ㄸ','ㄹ','ㅁ','ㅂ','ㅃ','ㅅ','ㅆ','ㅇ','ㅈ','ㅉ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'];
  out_t text := '';
  c text; code int;
begin
  for i in 1..coalesce(length(p), 0) loop
    c := substr(p, i, 1);
    code := ascii(c);
    if code between 44032 and 55203 then
      out_t := out_t || cho[((code - 44032) / 588) + 1];
    else
      out_t := out_t || c;
    end if;
  end loop;
  return out_t;
end $$;
grant execute on function quiz_chosung(text) to authenticated;

-- ═══════════ 6) 규칙 퀴즈의 정답 후보 ═══════════
--   키워드 자체 + 어간 + 흔한 종결형을 붙인 형태를 모두 인정한다.
create or replace function quiz_rule_answers(p_keyword text)
returns text[]
language plpgsql immutable as $$
declare st text := quiz_stem(p_keyword);
begin
  if length(st) >= 2 and st <> quiz_norm(p_keyword) then
    return array[p_keyword, st, st || '아요', st || '어요', st || '해요'];
  end if;
  return array[p_keyword];
end $$;
grant execute on function quiz_rule_answers(text) to authenticated;

-- ═══════════ 7) 오늘의 퀴즈 한 문제 ═══════════
--   규칙 초성 퀴즈와 지식 퀴즈를 섞어서 하나 내준다.
--   정답은 절대 내려보내지 않는다 (채점은 서버에서).
create or replace function todays_quiz()
returns json
language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_school uuid := current_profile_school();
  v_rule school_rules;
  v_q quiz_questions;
  v_kw text;
  v_use_bank boolean;
  v_bank_cnt int;
begin
  if v_school is null then return json_build_object('ok', false); end if;

  select count(*) into v_bank_cnt from quiz_questions
   where school_id = v_school and is_active;

  -- 지식 퀴즈가 있으면 절반 확률로 그쪽을 낸다
  v_use_bank := v_bank_cnt > 0 and random() < 0.5;

  if v_use_bank then
    select * into v_q from quiz_questions
     where school_id = v_school and is_active
     order by random() limit 1;
    return json_build_object(
      'ok', true, 'kind', 'bank', 'id', v_q.id,
      'question', v_q.question,
      'hint', coalesce(v_q.hint, quiz_chosung(v_q.answers[1])),
      'lengths', (select array_agg(distinct length(quiz_norm(a)) order by length(quiz_norm(a)))
                    from unnest(v_q.answers) a));
  end if;

  select * into v_rule from school_rules
   where school_id = v_school and is_active
     and quiz_keyword(rule_text) is not null
   order by random() limit 1;
  if v_rule.id is null then return json_build_object('ok', false); end if;

  v_kw := quiz_keyword(v_rule.rule_text);
  return json_build_object(
    'ok', true, 'kind', 'rule', 'id', v_rule.id,
    'question', v_rule.rule_text,
    'keyword_masked', quiz_chosung(v_kw),
    'lengths', (select array_agg(distinct length(quiz_norm(a)) order by length(quiz_norm(a)))
                  from unnest(quiz_rule_answers(v_kw)) a));
end $$;
grant execute on function todays_quiz() to authenticated;

-- ═══════════ 8) 채점 ═══════════
create or replace function submit_quiz(p_rule_id uuid, p_answer text)
returns json language plpgsql security definer set search_path = public, auth as $$
declare
  v_profile profiles; v_rule school_rules; v_q quiz_questions;
  v_accepted text[]; v_correct boolean; v_points int := 0; v_shown text;
begin
  select * into v_profile from profiles where user_id = auth.uid();
  if v_profile.id is null or v_profile.school_id is null then
    return json_build_object('ok', false, 'error', '프로필을 찾을 수 없어요');
  end if;
  if exists (select 1 from quiz_attempts where user_id = auth.uid()
             and quiz_date = (now() at time zone 'Asia/Seoul')::date) then
    return json_build_object('ok', false, 'error', '오늘 퀴즈는 이미 참여했어요');
  end if;

  -- 지식 퀴즈인지 규칙 퀴즈인지 id로 판별
  select * into v_q from quiz_questions
   where id = p_rule_id and school_id = v_profile.school_id and is_active;
  if v_q.id is not null then
    v_accepted := v_q.answers;
    v_shown := v_q.answers[1];
  else
    select * into v_rule from school_rules
     where id = p_rule_id and school_id = v_profile.school_id and is_active;
    if v_rule.id is null then
      return json_build_object('ok', false, 'error', '문제를 찾을 수 없어요');
    end if;
    v_shown := quiz_keyword(v_rule.rule_text);
    v_accepted := quiz_rule_answers(v_shown);
  end if;

  v_correct := quiz_is_correct(p_answer, v_accepted);
  if v_correct then
    v_points := case when v_profile.role = 'student' then 5 else 3 end;
  end if;

  insert into quiz_attempts (school_id, user_id, rule_id, correct, awarded)
  values (v_profile.school_id, auth.uid(),
          case when v_q.id is not null then null else p_rule_id end,
          v_correct, v_points);

  if v_correct then
    if v_profile.role = 'student' then
      insert into point_transactions (user_id, school_id, amount, reason, period_key, description)
      values (auth.uid(), v_profile.school_id, 5, 'quiz',
              to_char((now() at time zone 'Asia/Seoul')::date, 'YYYY-MM-DD'),
              '깜짝 퀴즈 정답')
      on conflict do nothing;
    else
      perform award_teacher_points(auth.uid(), v_profile.school_id, 3, 'quiz', p_rule_id, 1);
    end if;
  end if;

  return json_build_object('ok', true, 'correct', v_correct,
                           'points', v_points, 'keyword', v_shown);
end $$;
grant execute on function submit_quiz(uuid, text) to authenticated;

-- quiz_attempts.rule_id 가 지식 퀴즈일 때 null 이 되도록 제약 완화
alter table quiz_attempts alter column rule_id drop not null;

-- ═══════════ 9) 기본 지식 퀴즈 씨앗 ═══════════
--   충암중에 '3끝' 문제를 하나 넣어둔다. 다른 학교엔 영향 없음.
insert into quiz_questions (school_id, question, answers, hint)
select s.id,
       '충암중학교의 수업 규칙 세 가지를 한 마디로 부르는 말은?',
       array['3끝', '삼끝', '충암 3끝', '충암삼끝'],
       '3ㄲ'
  from schools s
 where s.name like '%충암%'
   and not exists (select 1 from quiz_questions q
                    where q.school_id = s.id and q.question like '%한 마디로 부르는 말%');
