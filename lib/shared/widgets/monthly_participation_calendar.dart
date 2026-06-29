import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart';

/// 월간 달력으로 참여/미참여를 직관적으로 보여준다.
///   초록 = 참여한 날(점수 높을수록 진함), 회색 = 안 한 날, 오늘 = 테두리 강조.
/// 데이터가 있는 범위 안에서 이전/다음 달로 이동할 수 있다.
class MonthlyParticipationCalendar extends StatefulWidget {
  const MonthlyParticipationCalendar({super.key, required this.scoresByDate});

  /// 'YYYY-MM-DD' -> 0..100 점수. 키가 없으면 미참여.
  final Map<String, double> scoresByDate;

  @override
  State<MonthlyParticipationCalendar> createState() => _State();
}

class _State extends State<MonthlyParticipationCalendar> {
  late DateTime _view; // 표시 중인 달의 1일

  @override
  void initState() {
    super.initState();
    final t = KstDate.today();
    _view = DateTime(t.year, t.month, 1);
  }

  Color _cellColor(double score) {
    if (score >= 80) return const Color(0xFF047857);
    if (score >= 60) return const Color(0xFF34D399);
    return const Color(0xFFA7F3D0); // 참여했으나 낮은 점수
  }

  DateTime get _minMonth {
    if (widget.scoresByDate.isEmpty) return _view;
    final keys = widget.scoresByDate.keys.toList()..sort();
    final d = DateTime.parse(keys.first);
    return DateTime(d.year, d.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final today = KstDate.today();
    final year = _view.year, month = _view.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leading = DateTime(year, month, 1).weekday % 7; // 일요일=0 시작

    // 이번 달 참여/미참여 집계
    var participated = 0, missed = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(year, month, d);
      final has = widget.scoresByDate.containsKey(KstDate.formatYmd(day));
      if (has) {
        participated++;
      } else if (!day.isAfter(today)) {
        missed++;
      }
    }

    final thisMonth = DateTime(today.year, today.month, 1);
    final canNext = _view.isBefore(thisMonth);
    final canPrev = _view.isAfter(_minMonth);

    // 날짜 셀
    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(year, month, d);
      cells.add(_dayCell(
        d,
        widget.scoresByDate[KstDate.formatYmd(day)],
        KstDate.isSameDay(day, today),
        day.isAfter(today),
        day.weekday % 7,
      ));
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox());
    }
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(Row(
        children: [
          for (var j = i; j < i + 7; j++)
            Expanded(child: AspectRatio(aspectRatio: 1, child: cells[j])),
        ],
      ));
    }

    const dows = ['일', '월', '화', '수', '목', '금', '토'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 월 이동 헤더
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              visualDensity: VisualDensity.compact,
              onPressed: canPrev
                  ? () => setState(
                      () => _view = DateTime(year, month - 1, 1))
                  : null,
            ),
            Expanded(
              child: Text(
                '$year년 $month월',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                    fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              visualDensity: VisualDensity.compact,
              onPressed: canNext
                  ? () => setState(
                      () => _view = DateTime(year, month + 1, 1))
                  : null,
            ),
          ],
        ),
        // 참여 요약
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Row(
            children: [
              _summaryChip('참여 $participated일', const Color(0xFF047857)),
              const SizedBox(width: 6),
              _summaryChip('미참여 $missed일', AppColors.textTertiary),
            ],
          ),
        ),
        // 요일 헤더
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    dows[i],
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: i == 0
                          ? const Color(0xFFEF4444)
                          : i == 6
                              ? const Color(0xFF3B82F6)
                              : AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        ...rows,
        const SizedBox(height: 10),
        // 범례
        Row(
          children: [
            _legendDot(const Color(0xFF047857)),
            Text(' 참여  ',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11, color: AppColors.textTertiary)),
            _legendDot(AppColors.borderLight),
            Text(' 미참여',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11, color: AppColors.textTertiary)),
          ],
        ),
      ],
    );
  }

  Widget _summaryChip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: GoogleFonts.notoSansKr(
                fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      );

  Widget _legendDot(Color c) => Container(
        width: 12,
        height: 12,
        decoration:
            BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
      );

  Widget _dayCell(
      int day, double? score, bool isToday, bool isFuture, int dow) {
    final participated = score != null;
    final dowColor = dow == 0
        ? const Color(0xFFEF4444)
        : dow == 6
            ? const Color(0xFF3B82F6)
            : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.all(2.5),
      child: Container(
        decoration: BoxDecoration(
          color: participated
              ? _cellColor(score)
              : isFuture
                  ? Colors.transparent
                  : AppColors.borderLight.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: participated
                      ? Colors.white
                      : isFuture
                          ? AppColors.textTertiary.withValues(alpha: 0.35)
                          : dowColor,
                ),
              ),
              if (participated)
                Text(
                  '${score.round()}',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
