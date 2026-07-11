import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'providers/growth_provider.dart';

/// 성장 기여 축하 스낵바 — 교사·학생의 긍정 행동이 학교 새싹의 양분이
/// 되었음을 즉시 알려주는 추가 강화. 새싹 상태도 함께 갱신한다.
///
/// [headline]  방금 한 행동 (예: '오늘의 자기점검 완료!')
/// 본문은 "교사와 학생이 함께 키운다" 메시지로 통일.
void celebrateGrowth(
  BuildContext context,
  WidgetRef ref, {
  required String headline,
}) {
  // 새싹 카드 실시간 갱신
  ref.invalidate(schoolGrowthProvider);

  final school =
      ref.read(schoolGrowthProvider).value?.schoolName ?? '우리 학교';

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF065F46),
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🌱', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '당신의 긍정적 행동이 모여 $school 새싹을 키우고 있어요!',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    color: const Color(0xFFA7F3D0),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
