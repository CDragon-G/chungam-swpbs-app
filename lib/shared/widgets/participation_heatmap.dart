import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart';

class ParticipationHeatmap extends StatelessWidget {
  const ParticipationHeatmap({
    super.key,
    required this.scoresByDate,
    this.weeks = 12,
  });

  /// date (YYYY-MM-DD) -> 0..100 score; null = no participation
  final Map<String, double> scoresByDate;
  final int weeks;

  static const double _cell = 14;
  static const double _gap = 3;

  Color _cellColor(double? score) {
    if (score == null) return AppColors.borderLight;
    if (score >= 80) return const Color(0xFF047857);
    if (score >= 60) return const Color(0xFF34D399);
    if (score > 0) return const Color(0xFFA7F3D0);
    return AppColors.borderLight;
  }

  @override
  Widget build(BuildContext context) {
    final today = KstDate.today();
    // Anchor on Monday `weeks` weeks ago for a clean column-per-week grid.
    final startMonday =
        KstDate.startOfWeek(today).subtract(Duration(days: (weeks - 1) * 7));

    final columns = <Widget>[];
    for (var w = 0; w < weeks; w++) {
      final monday = startMonday.add(Duration(days: w * 7));
      final cells = <Widget>[];
      for (var d = 0; d < 7; d++) {
        final day = monday.add(Duration(days: d));
        if (day.isAfter(today)) {
          cells.add(_blankCell());
        } else {
          final score = scoresByDate[KstDate.formatYmd(day)];
          cells.add(_dataCell(day, score));
        }
      }
      columns.add(Padding(
        padding: const EdgeInsets.only(right: _gap),
        child: Column(children: cells),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: (_cell + _gap) * 7,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(children: columns),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '참여도',
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 8),
            for (final c in const [
              Color(0xFFE2E8F0),
              Color(0xFFA7F3D0),
              Color(0xFF34D399),
              Color(0xFF047857),
            ])
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            const SizedBox(width: 4),
            Text(
              '높음',
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _blankCell() => SizedBox(
        width: _cell,
        height: _cell + _gap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: _gap),
          child: const SizedBox.shrink(),
        ),
      );

  Widget _dataCell(DateTime day, double? score) {
    return Tooltip(
      message:
          '${KstDate.formatKorean(day)}\n${score == null ? "미참여" : "${score.round()}점"}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: _gap),
        child: Container(
          width: _cell,
          height: _cell,
          decoration: BoxDecoration(
            color: _cellColor(score),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
