-- Allow 초등학교 in addition to 중학교 / 고등학교

alter table schools drop constraint if exists schools_level_check;
alter table schools add constraint schools_level_check
  check (level in ('초등학교', '중학교', '고등학교'));
