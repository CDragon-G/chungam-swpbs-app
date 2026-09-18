import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';

// ══════════════════ 모델 ══════════════════

/// 그날을 어떻게 표시할지 (서버 class_week_checkins 의 phase).
enum WeekPhase { past, todayOpen, todayClosed, future }

class WeekDay {
  const WeekDay({
    required this.date,
    required this.ymd,
    required this.schoolDay,
    required this.phase,
  });

  final DateTime date;
  final String ymd;
  final bool schoolDay;
  final WeekPhase phase;

  /// 점검할 수 있었던 날인가 (합계의 분모).
  bool get counts =>
      schoolDay && (phase == WeekPhase.past || phase == WeekPhase.todayOpen);

  factory WeekDay.fromMap(Map<String, dynamic> m) {
    final ymd = m['date'] as String;
    return WeekDay(
      date: DateTime.parse(ymd),
      ymd: ymd,
      schoolDay: m['school_day'] as bool? ?? true,
      phase: switch (m['phase'] as String?) {
        'today_open' => WeekPhase.todayOpen,
        'today_closed' => WeekPhase.todayClosed,
        'future' => WeekPhase.future,
        _ => WeekPhase.past,
      },
    );
  }
}

class WeekStudent {
  const WeekStudent({
    required this.nickname,
    required this.studentNum,
    required this.scores,
  });

  final String nickname;
  final int? studentNum;

  /// 'yyyy-MM-dd' → 그날 점수. 점검한 날만 들어 있다.
  final Map<String, int> scores;

  factory WeekStudent.fromMap(Map<String, dynamic> m) => WeekStudent(
        nickname: (m['nickname'] as String?) ?? '',
        studentNum: (m['student_num'] as num?)?.toInt(),
        scores: {
          for (final e in ((m['scores'] as Map?) ?? const {}).entries)
            e.key as String: (e.value as num).round(),
        },
      );
}

class ClassWeek {
  const ClassWeek({required this.days, required this.students});
  final List<WeekDay> days;
  final List<WeekStudent> students;
}

typedef ClassWeekKey = ({int grade, int classNum, String weekStart});

/// 한 반의 월~금 점검 여부.
final classWeekProvider = FutureProvider.autoDispose
    .family<ClassWeek, ClassWeekKey>((ref, key) async {
  final res = await SupabaseService.client.rpc('class_week_checkins', params: {
    'p_grade': key.grade,
    'p_class': key.classNum,
    'p_week_start': key.weekStart,
  });
  final m = Map<String, dynamic>.from(res as Map);
  if (m['ok'] != true) {
    throw StateError(m['error'] as String? ?? '불러오지 못했어요');
  }
  return ClassWeek(
    days: ((m['days'] as List?) ?? const [])
        .map((e) => WeekDay.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    students: ((m['students'] as List?) ?? const [])
        .map((e) => WeekStudent.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
});

// ══════════════════ 화면 ══════════════════

/// 📅 주간 점검표 — 반 학생들이 이번 주 어느 날 자기점검을 했는지.
/// 담임반 화면과 대시보드 반별 탭에서 쓴다. ◀ ▶ 로 지난주를 본다.
class WeeklyCheckinGrid extends ConsumerStatefulWidget {
  const WeeklyCheckinGrid({
    super.key,
    required this.grade,
    required this.classNum,
  });

  final int grade;
  final int classNum;

  @override
  ConsumerState<WeeklyCheckinGrid> createState() => _WeeklyCheckinGridState();
}

class _WeeklyCheckinGridState extends ConsumerState<WeeklyCheckinGrid> {
  static const _maxBack = 8; // 학기 정리 전 원본이 남아 있는 범위 안에서
  int _offset = 0; // 0 = 이번 주, -1 = 지난주 …

  static const _dayNames = ['월', '화', '수', '목', '금'];

  DateTime get _monday =>
      KstDate.startOfWeek().add(Duration(days: 7 * _offset));

  @override
  Widget build(BuildContext context) {
    final key = (
      grade: widget.grade,
      classNum: widget.classNum,
      weekStart: KstDate.formatYmd(_monday),
    );
    final async = ref.watch(classWeekProvider(key));
    final friday = _monday.add(const Duration(days: 4));

    return PbsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _offset == 0 ? '📅 이번 주 자기점검' : '📅 주간 자기점검',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 14.5, fontWeight: FontWeight.w900),
                ),
              ),
              _NavButton(
                icon: Icons.chevron_left_rounded,
                tooltip: '지난주',
                onTap: _offset > -_maxBack
                    ? () => setState(() => _offset--)
                    : null,
              ),
              Text(
                '${KstDate.formatShort(_monday)}~${KstDate.formatShort(friday)}',
                style: GoogleFonts.notoSansKr(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary),
              ),
              _NavButton(
                icon: Icons.chevron_right_rounded,
                tooltip: '다음 주',
                onTap: _offset < 0 ? () => setState(() => _offset++) : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          async.when(
            loading: () => const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(translateError(e),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12.5, color: AppColors.danger)),
            ),
            data: (w) => _table(w),
          ),
        ],
      ),
    );
  }

  Widget _table(ClassWeek w) {
    if (w.students.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('이 학급에 등록된 학생이 없어요.',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
                fontSize: 12.5, color: AppColors.textSecondary)),
      );
    }
    final countable = w.days.where((d) => d.counts).length;
    final never =
        w.students.where((s) => countable > 0 && s.scores.isEmpty).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (never > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _offset == 0
                  ? '이번 주 아직 한 번도 안 한 학생 $never명'
                  : '이 주에 한 번도 안 한 학생 $never명',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.danger),
            ),
          ),
        // 머리글
        _Row(
          name: Text('번호 · 이름',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11, color: AppColors.textTertiary)),
          cells: [
            for (var i = 0; i < w.days.length; i++)
              Text(
                i < _dayNames.length ? _dayNames[i] : '',
                style: GoogleFonts.notoSansKr(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: w.days[i].phase == WeekPhase.todayOpen ||
                          w.days[i].phase == WeekPhase.todayClosed
                      ? AppColors.teacherNavy
                      : AppColors.textSecondary,
                ),
              ),
          ],
          total: Text('합계',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11, color: AppColors.textTertiary)),
        ),
        const Divider(height: 8),
        for (final s in w.students)
          _Row(
            name: Text(
              '${s.studentNum ?? '-'} ${s.nickname}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: countable > 0 && s.scores.isEmpty
                    ? AppColors.danger
                    : AppColors.textPrimary,
              ),
            ),
            cells: [for (final d in w.days) _mark(d, s.scores[d.ymd])],
            total: Text(
              countable == 0
                  ? '-'
                  : '${w.days.where((d) => d.counts && s.scores.containsKey(d.ymd)).length}/$countable',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary),
            ),
          ),
        const Divider(height: 8),
        // 날마다 몇 명이 했나
        _Row(
          name: Text('한 학생',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11, color: AppColors.textTertiary)),
          cells: [
            for (final d in w.days)
              Text(
                d.schoolDay && d.phase != WeekPhase.future
                    ? '${w.students.where((s) => s.scores.containsKey(d.ymd)).length}'
                    : '',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.teacherNavy),
              ),
          ],
          total: Text('/${w.students.length}',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11, color: AppColors.textTertiary)),
        ),
        const SizedBox(height: 8),
        Text(
          '✓ 했음 · ✕ 안 함 · ○ 오늘 아직 · 휴 쉬는 날',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSansKr(
              fontSize: 11, color: AppColors.textTertiary),
        ),
      ],
    );
  }

  Widget _mark(WeekDay d, int? score) {
    if (score != null) {
      return Tooltip(
        message: '$score점',
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
        ),
      );
    }
    if (!d.schoolDay) {
      return Text('휴',
          style: GoogleFonts.notoSansKr(
              fontSize: 11, color: AppColors.textTertiary));
    }
    return switch (d.phase) {
      WeekPhase.past => Text('✕',
          style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppColors.danger)),
      WeekPhase.todayOpen => Text('○',
          style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppColors.warning)),
      WeekPhase.todayClosed || WeekPhase.future => const SizedBox.shrink(),
    };
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.name, required this.cells, required this.total});
  final Widget name;
  final List<Widget> cells;
  final Widget total;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(child: name),
          for (final c in cells) SizedBox(width: 30, child: Center(child: c)),
          SizedBox(
              width: 40,
              child: Align(alignment: Alignment.centerRight, child: total)),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.tooltip, this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(icon,
          size: 22,
          color: onTap == null ? AppColors.borderLight : AppColors.teacherNavy),
      onPressed: onTap,
    );
  }
}
