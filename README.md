# PBS+

PBS+ (Positive Behavior Support Plus) — SWPBS 일일 자기점검 모바일 앱.

## 기술 스택

- Flutter 3.5+ (Dart 3.5+)
- 상태관리: `flutter_riverpod` + `hooks_riverpod`
- 라우팅: `go_router` (ShellRoute 기반 하단 탭)
- 백엔드: Supabase (`supabase_flutter`) — Postgres + Auth + RLS
- 차트: `fl_chart`
- 캘린더: `table_calendar`
- 알림: `flutter_local_notifications`
- 폰트: Noto Sans KR (Google Fonts)

## 1. Supabase 프로젝트 만들기

1. https://supabase.com 에서 새 프로젝트 생성
2. 좌측 **SQL Editor** → 새 쿼리 → `supabase/migrations/001_init.sql`의 전체 내용 붙여넣고 실행
3. **Project Settings → API**에서 `Project URL`과 `anon public` 키 복사

## 2. `.env` 설정

루트의 `.env` 파일을 수정:

```
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_ANON_KEY=YOUR_ANON_KEY_HERE
```

`pubspec.yaml`에 `.env`가 asset으로 등록되어 있어 그대로 빌드하면 됩니다.

## 3. 실행

```bash
flutter pub get
flutter run
```

iOS / Android 둘 다 지원 (iOS 13+, Android API 21+).

## 4. 첫 사용 흐름

1. 앱 시작 → **교사로 시작하기** → 이메일·비밀번호·학교명·지역·학교급 입력 후 가입
2. 가입 시 자동으로 6자리 학교 코드(예: `CH2026`)가 발급되며, 교사 홈에서 확인 및 QR 공유 가능
3. 학생은 **학생으로 시작하기** → 학교 코드 입력 → 확인 → 학년·반·번호 입력 후 가입
4. 학생 홈에서 **점검하기** → 카테고리별 O/X 응답 → 결과 화면

## 5. 데이터 모델 요약

| 테이블 | 설명 |
| --- | --- |
| `schools` | 학교 + 6자리 학교 코드 |
| `school_rules` | 공간×카테고리별 규칙 (교사가 편집) |
| `profiles` | 사용자 프로필 (교사/학생) |
| `daily_checkins` | 일일 자기점검 (같은 날 재제출 시 덮어쓰기) |
| `badges` / `user_badges` | 뱃지 정의 / 획득 |
| `announcements` | 학교 공지 |

모든 테이블에 RLS 정책이 적용되어 있어 학생은 자기 학교 데이터만, 자기 자신의 점검 기록만 접근할 수 있습니다. 교사는 같은 학교 학생의 데이터(통계, 미참여 알림)에 한해 조회 가능합니다.

## 6. 디렉터리 구조

```
lib/
  main.dart, app.dart
  core/
    constants/        # 색상·문자열·사이즈
    router/           # go_router + ShellRoute
    supabase/         # initialize 헬퍼
    notifications/
    utils/            # KST 날짜, 학교 코드 생성기
  features/
    auth/             # welcome / login / signup-* + repository / provider
    school/           # school + school_rule 모델 / repository / provider
    checkin/          # 일일 점검 모델 / repository / 화면
    student/          # 홈 / 마이페이지 / 뱃지 / 비교 + stats provider
    teacher/          # 홈 / 대시보드(3탭) / 학생관리 / 규칙 / 공지
  shared/
    models/           # profile, badge
    providers/        # profile_provider
    widgets/          # ScoreRing, StreakBadge, Radar, Heatmap, AppBar, BottomNav, Cards/Buttons
```

## 7. 푸시 알림 (선택)

기본 `NotificationsService`는 즉시 알림(`showReminderNow()`)만 제공합니다. 종례 시간 등 정시 반복 알림이 필요하면:

1. `pubspec.yaml`에 `timezone: ^0.9.4` 추가
2. `main.dart`에서 `tz.initializeTimeZones()` 호출 + `tz.local = tz.getLocation('Asia/Seoul')`
3. `notifications_service.dart`의 메서드를 `zonedSchedule`로 교체
4. iOS: `Info.plist`에 `NSUserNotificationsUsageDescription` 추가, Android 13+: `POST_NOTIFICATIONS` 권한 요청

## 8. 디자인 시스템

- Primary 보라 `#7C3AED`
- Student 그린 `#10B981`
- Teacher 네이비 `#1F3864`
- 점수 색상: 80↑ 초록, 60↑ 노랑, 그 외 빨강

전체 토큰은 `lib/core/constants/app_colors.dart` 참고.

## 9. 문제 해결

- **로그인 후 무한 로딩**: `profiles` 행이 만들어지지 않은 경우. Supabase SQL Editor에서 `select * from profiles where user_id = '...'` 확인 후 비어 있으면 회원가입 플로우를 다시 진행하세요.
- **학교 코드 확인 실패**: 입력란이 자동 대문자 변환되어야 합니다. 6자리 영문 대문자+숫자만 가능합니다.
- **RLS 오류**: `001_init.sql` 전체를 다시 실행하면 정책이 멱등성 있게 재적용됩니다.

## 10. 라이선스

내부 사용 · 비공개. 충암중학교 SWPBS 운영용.
