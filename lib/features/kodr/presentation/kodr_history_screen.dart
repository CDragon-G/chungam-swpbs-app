import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../models/kodr.dart';
import '../providers/kodr_provider.dart';

/// 한 학생의 K-ODR 누적 기록.
///
/// 달이 바뀌어도, 학년이 바뀌어도 그 학생의 기록을 처음부터 본다.
/// 새 학기에 담임 · 교과 선생님이 바뀌었을 때 학생을 이해하는 출발점이다.
/// 같은 학교 선생님만 볼 수 있다.
class KodrHistoryScreen extends ConsumerWidget {
  const KodrHistoryScreen({
    super.key,
    required this.subjectId,
    required this.title,
  });

  final String subjectId;

  /// 불러오기 전에 보여줄 이름 (목록에서 누른 학생)
  final String title;

  static Future<void> open(
    BuildContext context, {
    required String subjectId,
    required String title,
  }) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => KodrHistoryScreen(subjectId: subjectId, title: title),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(kodrHistoryProvider(subjectId));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(async.value?.label ?? title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            Text('K-ODR 누적 기록',
                maxLines: 1,
                style: GoogleFonts.notoSansKr(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(kodrHistoryProvider(subjectId)),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(translateError(e),
                    textAlign: TextAlign.center,
                    style:
                        GoogleFonts.notoSansKr(color: AppColors.textSecondary)),
              ),
            ),
          ]),
          data: (h) => _Body(h),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.h);
  final KodrHistory h;

  @override
  Widget build(BuildContext context) {
    // 학년도 → 달 순서로 묶는다 (서버가 최신순으로 준다)
    final years = <int, List<KodrHistoryRecord>>{};
    for (final r in h.records) {
      years.putIfAbsent(r.schoolYear, () => []).add(r);
    }

    return ListView(
      padding: const EdgeInsets.all(AppSizes.lg),
      children: [
        _Overview(h),
        if (h.topBehaviors.isNotEmpty) ...[
          const SizedBox(height: AppSizes.md),
          _Tops('자주 기록된 행동', h.topBehaviors),
        ],
        if (h.topPlaces.isNotEmpty) ...[
          const SizedBox(height: AppSizes.sm),
          _Tops('자주 일어난 장소', h.topPlaces),
        ],
        for (final y in years.entries) ...[
          const SizedBox(height: AppSizes.lg),
          _YearHeader(year: y.key, records: y.value),
          ..._months(y.value),
        ],
        if (h.records.length < h.total)
          Padding(
            padding: const EdgeInsets.only(top: AppSizes.md),
            child: Text('최근 ${h.records.length}건까지 보여드려요.',
                maxLines: 1,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                    fontSize: 12, color: AppColors.textTertiary)),
          ),
        const SizedBox(height: 40),
      ],
    );
  }

  List<Widget> _months(List<KodrHistoryRecord> records) {
    final months = <String, List<KodrHistoryRecord>>{};
    for (final r in records) {
      final key = '${r.occurredDate.year}-${r.occurredDate.month}';
      months.putIfAbsent(key, () => []).add(r);
    }
    return [
      for (final m in months.values) ...[
        Padding(
          padding: const EdgeInsets.only(top: AppSizes.md, bottom: 6),
          child: Text(
            '${m.first.occurredDate.year}년 ${m.first.occurredDate.month}월 · ${m.length}건',
            maxLines: 1,
            style: GoogleFonts.notoSansKr(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary),
          ),
        ),
        for (final r in m) _RecordCard(r),
      ],
    ];
  }
}

/// 맨 위 요약 — 전체 · 이번 학년도 · 최근 N일.
class _Overview extends StatelessWidget {
  const _Overview(this.h);
  final KodrHistory h;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int n) => Expanded(
          child: Column(
            children: [
              Text('$n건',
                  maxLines: 1,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.teacherNavy)),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 11.5, color: AppColors.textSecondary)),
            ],
          ),
        );

    return PbsCard(
      child: Column(
        children: [
          Row(
            children: [
              stat('전체', h.total),
              stat('이번 학년도', h.yearCount),
              stat('최근 ${h.windowDays}일', h.windowCount),
            ],
          ),
          if (!h.isCurrent || !h.joined) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!h.isCurrent) const _Tag('졸업 · 전출'),
                if (h.isCurrent && !h.joined) const _Tag('앱 미가입'),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text('처벌이 아니라 학생을 이해하고 돕기 위한 기록이에요.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                  fontSize: 11.5, color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

class _Tops extends StatelessWidget {
  const _Tops(this.title, this.items);
  final String title;
  final List<(String, int)> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            maxLines: 1,
            style: GoogleFonts.notoSansKr(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (label, n) in items)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Text('$label $n',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ],
    );
  }
}

/// 학년도 구분 — 그 학년도에 몇 학년 몇 반이었는지 함께.
class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.year, required this.records});
  final int year;
  final List<KodrHistoryRecord> records;

  @override
  Widget build(BuildContext context) {
    // 기록 당시의 학년 · 반 (그 학년도의 가장 최근 기록 기준)
    final withClass = records
        .where((r) => r.studentGrade != null && r.studentClass != null)
        .toList();
    final cls = withClass.isEmpty
        ? ''
        : ' · ${withClass.first.studentGrade}학년 ${withClass.first.studentClass}반';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.teacherNavy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('$year학년도$cls',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKr(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.teacherNavy)),
          ),
          Text('${records.length}건',
              maxLines: 1,
              style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppColors.teacherNavy)),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard(this.r);
  final KodrHistoryRecord r;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final d = r.occurredDate;
    final where = [r.place, r.situation].whereType<String>().join(' · ');
    final who = [r.teacherName, r.authorRole].whereType<String>().join(' · ');

    Widget line(String label, String? value) => value == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 62,
                  child: Text(label,
                      maxLines: 1,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 11.5, color: AppColors.textTertiary)),
                ),
                Expanded(
                  child: Text(value,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 12.5,
                          height: 1.45,
                          color: AppColors.textSecondary)),
                ),
              ],
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PbsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${d.month}.${d.day} (${_weekdays[d.weekday - 1]})',
                    maxLines: 1,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.teacherNavy)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.behavior,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            line('장소 · 상황', where.isEmpty ? null : where),
            line('즉각 대응', r.immediateResponse),
            line('2차 대응', r.secondaryResponse),
            line('학생 반응', r.studentReaction),
            line('메모', r.note),
            line('기록', who.isEmpty ? null : who),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.borderLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          maxLines: 1,
          style: GoogleFonts.notoSansKr(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary)),
    );
  }
}
