-- 008_teacher_code.sql
-- 교사 전용 가입 코드 분리 (보안 강화)
-- 기존: school_code 하나로 학생·교사 모두 가입 → 학생이 교사 코드를 알면 교사 가입 가능
-- 변경: teacher_code를 별도로 두어, 기존 학교에 참여하는 교사만 이 코드로 가입.
--       학생은 기존 school_code 그대로 사용.

-- 1) teacher_code 컬럼 추가
alter table schools add column if not exists teacher_code text;

-- 2) 기존 학교들에 teacher_code 백필 (없는 경우)
--    학교 id + random 기반 → 학교마다 확실히 유니크한 8자리
update schools
set teacher_code = upper(substr(md5(random()::text || id::text), 1, 8))
where teacher_code is null;

-- 3) 유니크 제약 + NOT NULL
alter table schools alter column teacher_code set not null;

create unique index if not exists schools_teacher_code_key
  on schools (teacher_code);
