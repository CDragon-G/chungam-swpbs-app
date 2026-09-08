import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';

/// 내가 보낸 칭찬 한 건.
class SentPraise {
  const SentPraise({
    required this.id,
    required this.studentName,
    required this.grade,
    required this.classNum,
    required this.studentNum,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String studentName;
  final int? grade;
  final int? classNum;
  final int? studentNum;
  final String message;
  final DateTime createdAt;

  /// '3학년 2반 14번 홍길동' — 학번이 없으면 이름만.
  String get label => (grade != null && classNum != null && studentNum != null)
      ? '$grade학년 $classNum반 $studentNum번 $studentName'
      : studentName;

  bool get isToday {
    final now = DateTime.now();
    return createdAt.year == now.year &&
        createdAt.month == now.month &&
        createdAt.day == now.day;
  }

  String get whenLabel {
    final d = createdAt.toLocal();
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return isToday ? '오늘 $hh:$mm' : '${d.month}월 ${d.day}일 $hh:$mm';
  }

  factory SentPraise.fromMap(Map<String, dynamic> m) => SentPraise(
        id: m['id'] as String,
        studentName: (m['student_name'] as String?) ?? '학생',
        grade: (m['grade'] as num?)?.toInt(),
        classNum: (m['class_num'] as num?)?.toInt(),
        studentNum: (m['student_num'] as num?)?.toInt(),
        message: (m['message'] as String?) ?? '',
        createdAt:
            DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );
}

final sentPraisesProvider = FutureProvider<List<SentPraise>>((ref) async {
  final rows = await SupabaseService.client
      .rpc('my_sent_praises', params: {'p_limit': 200});
  return ((rows as List?) ?? const [])
      .map((e) => SentPraise.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
});

/// 💚 내가 보낸 칭찬 — 정말 보냈는지, 누구에게 보냈는지 확인하는 화면.
///
/// 칭찬을 보내면 스낵바가 잠깐 떴다 사라져서 나중에 확인할 길이 없었다.
/// 같은 학생을 두 번 칭찬하거나, 보낸 줄 알았는데 안 보낸 일이 생긴다.
class PraiseSentScreen extends ConsumerWidget {
  const PraiseSentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sentPraisesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('내가 보낸 칭찬',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Text(translateError(e),
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(color: AppColors.textSecondary)),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('💚', style: TextStyle(fontSize: 44)),
                    const SizedBox(height: 10),
                    Text(
                      '아직 보낸 칭찬이 없어요.\n학생 목록에서 칭찬을 보내보세요.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          height: 1.7,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }

          final todayCount = items.where((p) => p.isToday).length;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(sentPraisesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSizes.lg),
              itemCount: items.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.md),
                    child: PbsCard(
                      color: const Color(0xFFF0FDF4),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                      child: Row(
                        children: [
                          const Text('💚', style: TextStyle(fontSize: 26)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  todayCount > 0
                                      ? '오늘 $todayCount명에게 칭찬을 보냈어요'
                                      : '오늘은 아직 칭찬을 보내지 않았어요',
                                  style: GoogleFonts.notoSansKr(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '전체 ${items.length}건 · 칭찬 한 번에 학생 +50P',
                                  style: GoogleFonts.notoSansKr(
                                      fontSize: 11.5,
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final p = items[i - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: PbsCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.md, vertical: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.notoSansKr(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              p.whenLabel,
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 11,
                                  color: AppColors.textTertiary),
                            ),
                          ],
                        ),
                        if (p.message.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            p.message,
                            style: GoogleFonts.notoSansKr(
                                fontSize: 12.5,
                                height: 1.5,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
