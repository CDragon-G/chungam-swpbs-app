import '../../features/school/models/school.dart';
import '../../shared/models/profile.dart';

/// Age-gate policy for advertising.
///
/// 자람은 학교 가입 구조상 사용자가 어느 학교급에 속하는지 확실히 알 수 있어요.
/// 이를 기반으로 광고 정책을 적용합니다.
///
/// 정책:
/// - 교사: 항상 광고 노출 가능 (개인화 OK)
/// - 고등학생: 광고 노출 가능 (개인화 OK)
/// - 중학생: 광고 노출 가능 (단, 비개인화 NPA만 — PIPA 14세 경계 안전)
/// - 초등학생: 광고 노출 금지 (Google Families + 한국 PIPA 준수)
/// - 학교 정보 미확정 / 프로필 미완성: 안전하게 광고 OFF
class AdsEligibility {
  AdsEligibility._();

  /// Whether ads should be shown at all for this user.
  static bool canShowAds({
    required Profile? profile,
    required School? school,
  }) {
    if (profile == null) return false;
    if (profile.isTeacher) return true;
    // student
    if (school == null) return false; // unknown school = skip
    if (school.level == '초등학교') return false;
    return true; // 중학교 + 고등학교
  }

  /// Whether to use personalized ads (vs non-personalized / NPA).
  /// Returns true only when safely above PIPA 14세 threshold.
  static bool allowPersonalizedAds({
    required Profile? profile,
    required School? school,
  }) {
    if (profile == null) return false;
    if (profile.isTeacher) return true;
    if (school == null) return false;
    if (school.level == '고등학교') return true;
    // 중학생: NPA only (some 중1 might be under 14 in Korean age)
    return false;
  }

  /// Human-readable label for the current policy (debug/admin use).
  static String policyLabel({
    required Profile? profile,
    required School? school,
  }) {
    if (!canShowAds(profile: profile, school: school)) {
      return '광고 비노출';
    }
    return allowPersonalizedAds(profile: profile, school: school)
        ? '개인화 광고'
        : '비개인화 광고 (NPA)';
  }
}
