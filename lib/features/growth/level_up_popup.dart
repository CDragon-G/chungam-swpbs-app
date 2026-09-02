import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/supabase/supabase_client.dart';
import 'models/growth_status.dart';
import 'providers/growth_provider.dart';

/// 🎉 학교 새싹이 한 단계 자랐을 때 축하 팝업.
///
/// 레벨 계산은 앱이 한다(점수 + 관문). 계산한 레벨을 서버에 넘기면
/// 그 사용자가 이전에 본 레벨과 비교해 '처음 보는 레벨'인지 알려준다.
/// 그래서 학교가 성장한 순간, 모든 구성원이 각자 앱을 켤 때 한 번씩 축하받는다.
Future<void> maybeShowLevelUp(BuildContext context, WidgetRef ref) async {
  try {
    final growth = ref.read(schoolGrowthProvider).value;
    if (growth == null) return;

    final res = await SupabaseService.client
        .rpc('check_growth_level', params: {'p_level': growth.level});
    final m = Map<String, dynamic>.from(res as Map);
    if (m['leveled_up'] != true) return;

    final from = (m['from'] as num?)?.toInt();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _LevelUpDialog(
        growth: growth,
        fromLevel: from,
      ),
    );
  } catch (_) {
    // 축하는 부가 기능 — 조용히 넘어간다
  }
}

class _LevelUpDialog extends StatelessWidget {
  const _LevelUpDialog({required this.growth, this.fromLevel});
  final GrowthStatus growth;
  final int? fromLevel;

  /// 단계마다 다른 말로 축하한다. 매번 같은 문장이면 금방 시시해진다.
  String get _message => switch (growth.level) {
        2 => '씨앗에서 싹이 텄어요.\n작은 약속들이 모여 처음 초록이 보입니다.',
        3 => '잎이 넓어졌어요.\n우리 학교가 규칙에 익숙해지고 있다는 뜻이에요.',
        4 => '어린나무가 됐어요.\n이제 스스로 서 있을 만큼 뿌리가 내렸습니다.',
        5 => '튼튼한 나무가 됐어요.\n웬만한 바람에는 흔들리지 않습니다.',
        6 => '꽃이 피었어요.\n그동안 쌓아온 것이 눈에 보이기 시작했습니다.',
        7 => '열매를 맺었어요.\n한 해의 실천이 여기까지 왔습니다. 정말 대단해요.',
        _ => '한 뼘 더 자랐어요.',
      };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🎉', style: GoogleFonts.notoSansKr(fontSize: 44)),
            const SizedBox(height: 6),
            Text('우리 학교 새싹이 자랐어요!',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                    fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (fromLevel != null && fromLevel! >= 1) ...[
                  _LevelChip(level: fromLevel!, dim: true),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 18, color: AppColors.textTertiary),
                  ),
                ],
                _LevelChip(level: growth.level),
              ],
            ),
            const SizedBox(height: 18),
            Text(_message,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(fontSize: 13.5, height: 1.7)),
            const SizedBox(height: 10),
            Text('${growth.schoolName} · ${growth.score}점',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11.5, color: AppColors.textTertiary)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.studentGreen,
                    padding: const EdgeInsets.symmetric(vertical: 13)),
                onPressed: () => Navigator.pop(context),
                child: Text('고마워요!',
                    style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level, this.dim = false});
  final int level;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final i = (level - 1).clamp(0, GrowthStatus.levelNames.length - 1);
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: Column(
        children: [
          Text(GrowthStatus.levelEmojis[i],
              style: const TextStyle(fontSize: 30)),
          const SizedBox(height: 2),
          Text('Lv.$level',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textSecondary)),
          Text(GrowthStatus.levelNames[i],
              style: GoogleFonts.notoSansKr(
                  fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
