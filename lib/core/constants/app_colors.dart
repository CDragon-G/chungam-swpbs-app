import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary
  static const Color primary = Color(0xFF7C3AED);
  static const Color primaryLight = Color(0xFFEDE9FE);
  static const Color primaryDark = Color(0xFF5B21B6);

  // Student theme
  static const Color studentGreen = Color(0xFF10B981);
  static const Color studentGreenLight = Color(0xFFD1FAE5);

  // Teacher theme
  static const Color teacherNavy = Color(0xFF1F3864);
  static const Color teacherNavyLight = Color(0xFFEFF3F8);

  // Category colors
  static const Color colorLesson = Color(0xFF5B21B6);
  static const Color colorM = Color(0xFF15803D);
  static const Color colorR = Color(0xFF1E40AF);
  static const Color colorS = Color(0xFFB91C1C);
  static const Color colorClassroom = Color(0xFF0F766E);
  static const Color colorHallway = Color(0xFF1D4ED8);
  static const Color colorCafeteria = Color(0xFFB45309);
  static const Color colorRestroom = Color(0xFF0369A1);

  // Status
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  // Neutral
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFF1F5F9);
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);

  static Color spaceColor(String space) {
    switch (space) {
      case '수업':
        return colorLesson;
      case '교실':
        return colorClassroom;
      case '복도·계단':
      case '복도':
        return colorHallway;
      case '급식실':
        return colorCafeteria;
      case '화장실':
        return colorRestroom;
      default:
        return primary;
    }
  }

  static Color categoryColor(String category) {
    if (category.contains('수업')) return colorLesson;
    if (category.startsWith('M')) return colorM;
    if (category.startsWith('R')) return colorR;
    if (category.startsWith('S')) return colorS;
    return primary;
  }

  static Color scoreColor(double pct) {
    if (pct >= 80) return success;
    if (pct >= 60) return warning;
    return danger;
  }
}
