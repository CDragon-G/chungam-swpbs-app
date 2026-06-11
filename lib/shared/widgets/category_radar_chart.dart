import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';

class CategoryRadarChart extends StatelessWidget {
  const CategoryRadarChart({
    super.key,
    required this.scores,
    this.comparison,
    this.height = 260,
  });

  /// category -> 0..100
  final Map<String, double> scores;
  /// optional secondary dataset (e.g. class average)
  final Map<String, double>? comparison;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            '아직 데이터가 충분하지 않아요.',
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      );
    }
    final keys = scores.keys.toList();
    final myValues = keys.map((k) => scores[k] ?? 0).toList();
    final cmpValues =
        comparison == null ? null : keys.map((k) => comparison![k] ?? 0).toList();

    return SizedBox(
      height: height,
      child: RadarChart(
        RadarChartData(
          radarShape: RadarShape.polygon,
          tickCount: 4,
          ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 10),
          tickBorderData: BorderSide(color: AppColors.borderLight),
          gridBorderData: BorderSide(color: AppColors.borderLight),
          radarBorderData: const BorderSide(color: Colors.transparent),
          titlePositionPercentageOffset: 0.15,
          getTitle: (i, _) => RadarChartTitle(
            text: keys[i],
            angle: 0,
          ),
          titleTextStyle: GoogleFonts.notoSansKr(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
          dataSets: [
            RadarDataSet(
              fillColor: AppColors.primary.withValues(alpha: 0.25),
              borderColor: AppColors.primary,
              borderWidth: 2,
              entryRadius: 3,
              dataEntries:
                  myValues.map((v) => RadarEntry(value: v)).toList(),
            ),
            if (cmpValues != null)
              RadarDataSet(
                fillColor: Colors.transparent,
                borderColor: AppColors.textTertiary,
                borderWidth: 1.5,
                entryRadius: 0,
                dataEntries:
                    cmpValues.map((v) => RadarEntry(value: v)).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
