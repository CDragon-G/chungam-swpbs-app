import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ⭐ 스토어 별점 요청.
///
/// 별점 창은 스토어가 알아서 띄워 주지 않는다. 앱이 직접 불러야 한다.
/// 부르는 것은 OS 기본 평가창이다 (Android: Play 인앱 리뷰 · iOS: App Store 평가).
///
/// 언제 부르나 — '기분 좋은 순간' 에만.
///   · 학생: 교환 신청을 마쳤을 때, 자기점검을 마쳤을 때
///   · 선생님: 칭찬을 보냈을 때
/// 그 순간이 쌓이고(학생 10번 · 선생님 5번), 앱을 쓴 지 2주가 지났을 때 한 번.
/// 그 뒤로는 120일에 한 번, 모두 3번까지만.
///
/// 지키는 것
///   · "앱이 마음에 드세요?" 처럼 먼저 묻고 좋다고 한 사람에게만 띄우지 않는다.
///     Play 정책이 금지하고(리뷰 게이팅), App Store 도 권하지 않는다.
///   · 체험 학교(엑스포 부스 · 특강 체험)에서는 띄우지 않는다.
///   · 창이 실제로 뜰지는 OS 가 정한다 (iOS 는 1년에 3번까지). 뜨지 않아도 오류가 아니다.
class ReviewPrompt {
  ReviewPrompt._();

  static const _kFirst = 'review_first_seen';
  static const _kHappy = 'review_happy_count';
  static const _kLast = 'review_last_asked';
  static const _kAsks = 'review_ask_count';

  static const appStoreId = '6780309774';

  /// 처음 쓴 날을 기억한다 (홈에서 한 번).
  static Future<void> noteFirstSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getString(_kFirst) == null) {
        await p.setString(_kFirst, DateTime.now().toIso8601String());
      }
    } catch (_) {}
  }

  /// 기분 좋은 순간 하나. 조건이 맞으면 잠시 뒤 평가창을 부른다.
  static Future<void> happyMoment({
    required bool teacher,
    required bool isDemo,
  }) async {
    if (isDemo || kIsWeb) return;
    try {
      final p = await SharedPreferences.getInstance();
      final happy = (p.getInt(_kHappy) ?? 0) + 1;
      await p.setInt(_kHappy, happy);
      if (!shouldAsk(
        teacher: teacher,
        happy: happy,
        firstSeen: DateTime.tryParse(p.getString(_kFirst) ?? ''),
        lastAsked: DateTime.tryParse(p.getString(_kLast) ?? ''),
        asks: p.getInt(_kAsks) ?? 0,
        now: DateTime.now(),
      )) {
        return;
      }
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      await p.setString(_kLast, DateTime.now().toIso8601String());
      await p.setInt(_kAsks, (p.getInt(_kAsks) ?? 0) + 1);
      // 축하 안내가 먼저 보이도록 조금 기다린다
      await Future.delayed(const Duration(milliseconds: 1500));
      await review.requestReview();
    } catch (_) {
      // 평가창은 덤이다. 실패해도 사용자에게 알리지 않는다.
    }
  }

  /// 띄울 때인가 (테스트하기 쉽게 따로 뺐다).
  @visibleForTesting
  static bool shouldAsk({
    required bool teacher,
    required int happy,
    required DateTime? firstSeen,
    required DateTime? lastAsked,
    required int asks,
    required DateTime now,
  }) {
    if (asks >= 3) return false;
    if (firstSeen == null || now.difference(firstSeen).inDays < 14) {
      return false;
    }
    if (lastAsked != null && now.difference(lastAsked).inDays < 120) {
      return false;
    }
    return happy >= (teacher ? 5 : 10);
  }

  /// 메뉴의 '앱 평가하기' — 사용자가 직접 누른 것이라 조건 없이 스토어로 보낸다.
  static Future<void> openStore() =>
      InAppReview.instance.openStoreListing(appStoreId: appStoreId);
}
