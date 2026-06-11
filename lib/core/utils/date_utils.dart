import 'package:intl/intl.dart';

/// All dates in PBS+ are KST (UTC+9) based.
class KstDate {
  KstDate._();

  static const Duration _kstOffset = Duration(hours: 9);

  static DateTime now() => DateTime.now().toUtc().add(_kstOffset);

  static DateTime today() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime startOfWeek([DateTime? d]) {
    final base = d ?? today();
    final monday = base.subtract(Duration(days: (base.weekday - 1) % 7));
    return DateTime(monday.year, monday.month, monday.day);
  }

  static String formatYmd(DateTime d) =>
      DateFormat('yyyy-MM-dd').format(d);

  static String formatKorean(DateTime d) =>
      DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(d);

  static String formatMd(DateTime d) =>
      DateFormat('M월 d일').format(d);

  static String formatShort(DateTime d) =>
      DateFormat('M/d').format(d);

  static DateTime parseYmd(String s) => DateTime.parse(s);

  static int daysBetween(DateTime a, DateTime b) {
    final ad = DateTime(a.year, a.month, a.day);
    final bd = DateTime(b.year, b.month, b.day);
    return bd.difference(ad).inDays;
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
