# 대구 강의 체험 입장 안내 (2026-12-07)

참여자 350~400명이 PIN 없이 체험 코드만으로 학생 화면을 체험한다. 0.35.0 과 079 가 필요하다.

## 1. 미리 할 일 (강의 3일 전까지)

### 1-1. 서버

1. `078`, `079` 실행 (0.35.0 출시노트의 배포 순서)
2. Supabase 대시보드 → **Authentication → Sign In / Providers → Allow anonymous sign-ins** 켜기
3. Supabase 대시보드 → **Authentication → Rate Limits**
   - 익명 로그인 한도는 기본값이 낮아(IP 하나당 시간당 수십 명 수준), 강당 와이파이 하나로 400명이 들어오면 막힌다.
   - 강의 날에만 크게 올리고(예: 1000), 끝나면 되돌린다. 화면의 항목 이름과 기본값은 대시보드에서 확인한다.

### 1-2. 대구 체험 학교 만들기

엑스포용 자람체험중학교와 섞이지 않게 학교를 따로 만든다.

1. 앱에서 새 선생님 계정으로 가입 → **새 학교 등록** → 학교 이름 `자람체험중학교 대구`
   - 이메일은 지메일 뒤에 `+daegu` 를 붙이면 새로 만들지 않아도 된다 (예: `내아이디+daegu@gmail.com`).
   - 이 계정이 강사용 관리자 계정이 된다.
2. Supabase SQL 에디터에서:

```sql
-- 학교 id 확인
select id, name, school_code from schools where name = '자람체험중학교 대구';

-- 체험 학교로 만들고 예시 데이터(강화물 · 공지 등) 채우기
select setup_demo_school('<학교 id>');

-- 체험 입장 열기: 이름 앞말 · 학년 · 반 인원 · 최대 인원
select set_demo_join('<학교 id>', true, '대구체험학생', 2, 30, 600);
```

`set_demo_join` 결과의 `code` 가 참여자에게 보여 줄 **체험 코드**다.

3. 강사 계정의 담임반을 `2학년 1반` 으로 바꿔 두면 담임반 현황에서 앞 30명이 보인다
   (`setup_demo_school` 이 1학년 1반으로 정해 두기 때문).

### 1-3. 휴대폰 한 대로 시험

1. 앱 첫 화면 → **강의 · 연수 체험 코드가 있어요** → 체험 코드 → 체험 시작
2. '대구체험학생1' 로 학생 홈이 열리면 성공 (이 번호는 시험용으로 쓰인다)
3. 오늘 자기점검 · 교환소 · 칭찬 우체통이 열리는지 확인

## 2. 강의 당일

- 슬라이드: 앱 설치 QR(Play 스토어 · App Store) + **체험 코드** 크게
- 안내 순서: 설치 → 앱 열기 → '강의 · 연수 체험 코드가 있어요' → 코드 입력 → 체험 시작
- 가입이 몰려 막히면 앱이 "와이파이를 끄고 데이터로" 를 안내한다. 강사도 그렇게 말해 주면 된다.
- 공지 · 강화물을 시연할 때는 **'휴대폰 알림 보내기' 를 끈다** (400대가 한꺼번에 울린다).
- 보라색 **체험 초기화** 는 누르지 않는다 (참여자 기록이 지워진다).

## 3. 끝난 뒤 (당일)

```sql
-- 1) 입장 닫기 (이미 들어온 사람은 그대로)
select set_demo_join((select id from schools where is_demo and name = '자람체험중학교 대구'), false);

-- 2) 지울 대상 확인 (아무것도 지우지 않음)
select count(*) as "체험 학생 수"
  from profiles p
  join auth.users u on u.id = p.user_id
  join schools s on s.id = p.school_id
 where s.is_demo and s.name = '자람체험중학교 대구'
   and p.role = 'student' and u.is_anonymous;

-- 3) 체험 학생 계정과 명단 자리 지우기 (되돌릴 수 없음)
do $$
declare
  v_school uuid;
  v_users uuid[];
  v_del_users int;
  v_del_roster int;
begin
  select id into v_school from schools where is_demo and name = '자람체험중학교 대구';
  if v_school is null then
    raise exception '자람체험중학교 대구(is_demo)를 찾지 못했어요';
  end if;

  -- 이 학교 학생 중 체험 코드로 들어온(익명) 계정만
  select coalesce(array_agg(p.user_id), '{}') into v_users
    from profiles p
    join auth.users u on u.id = p.user_id
   where p.school_id = v_school and p.role = 'student' and u.is_anonymous;

  update student_roster set claimed = false, claimed_by = null
   where school_id = v_school and claimed_by = any(v_users);
  delete from auth.users where id = any(v_users);
  get diagnostics v_del_users = row_count;

  delete from student_roster
   where school_id = v_school and name ~ '체험학생[0-9]+$';
  get diagnostics v_del_roster = row_count;

  update schools set demo_join_seq = 0 where id = v_school;

  raise notice '지운 계정 %개, 지운 명단 자리 %개', v_del_users, v_del_roster;
end $$;

-- 4) 체험 코드를 넣지 않고 나간 익명 계정 정리 (하루 지난 것)
delete from auth.users u
 where u.is_anonymous
   and u.created_at < now() - interval '1 day'
   and not exists (select 1 from profiles p where p.user_id = u.id);

-- 5) (선택) 학교 전체 예시 데이터 다시 채우기
-- select reset_demo_school((select id from schools where is_demo and name = '자람체험중학교 대구'), true, 'all');
```

그다음 대시보드에서 **Rate Limits 되돌리기**, 다음 강의 계획이 없으면 **Allow anonymous sign-ins 끄기**.

## 4. 알아 둘 것

- 체험 계정은 앱을 지우거나 로그아웃하면 다시 들어올 수 없다. 다시 체험 코드를 넣으면 새 번호로 들어온다.
- 체험 학생 이름은 '대구체험학생12' 처럼 가리지 않고 구름 · 명예의 전당에 그대로 보인다 (실명이 아니라서).
- 익명 계정은 프로필을 직접 만들거나 학교 · 역할 · 반 · 이름을 바꿀 수 없다 (079 트리거). 체험 코드로만 들어온다.
- 최대 인원(600)이 차면 '체험 인원이 모두 찼어요' 가 나온다. 늘리려면 `set_demo_join(id, true, null, null, null, 800)`.
