import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/utils/error_messages.dart';
import '../../shared/providers/profile_provider.dart';
import '../../shared/widgets/pbs_card.dart';

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.question,
    required this.answers,
    required this.isActive,
    this.hint,
  });

  final String id;
  final String question;
  final List<String> answers;
  final bool isActive;
  final String? hint;

  factory QuizQuestion.fromMap(Map<String, dynamic> m) => QuizQuestion(
        id: m['id'] as String,
        question: m['question'] as String,
        answers: ((m['answers'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        isActive: (m['is_active'] as bool?) ?? true,
        hint: m['hint'] as String?,
      );
}

final quizQuestionsProvider = FutureProvider<List<QuizQuestion>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  final rows = await SupabaseService.client
      .from('quiz_questions')
      .select()
      .eq('school_id', profile!.schoolId!)
      .order('created_at', ascending: false);
  return rows.map((m) => QuizQuestion.fromMap(m)).toList();
});

/// 🧠 퀴즈 문제 관리 — 관리자 전용.
/// 규칙 초성 퀴즈만으로는 단조로워서, 학교가 직접 문제를 낼 수 있게 한다.
/// 정답을 여러 개 적어두면 그중 하나만 맞아도 정답으로 인정된다.
class QuizAdminScreen extends ConsumerWidget {
  const QuizAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(quizQuestionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('🧠 퀴즈 문제 관리',
            style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.teacherNavy,
        onPressed: () => _showEditor(context, ref),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('문제 추가',
            style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w800, color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(quizQuestionsProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(translateError(e))),
          data: (items) => ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              PbsCard(
                color: AppColors.teacherNavyLight,
                child: Text(
                  '깜짝 퀴즈는 규칙 초성 문제와 여기 등록한 문제를 섞어서 냅니다.\n\n'
                  '정답을 여러 개 적어두면 그중 하나만 맞아도 정답이에요.\n'
                  '예) 3끝 · 삼끝 · 충암 3끝',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12.5,
                      height: 1.6,
                      color: AppColors.teacherNavy),
                ),
              ),
              const SectionHeader(title: '등록된 문제'),
              if (items.isEmpty)
                PbsCard(
                  child: Text('아직 등록된 문제가 없어요.',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13, color: AppColors.textTertiary)),
                ),
              ...items.map((q) => _QuestionTile(q: q)),
              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionTile extends ConsumerWidget {
  const _QuestionTile({required this.q});
  final QuizQuestion q;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: PbsCard(
        color: q.isActive ? AppColors.surface : AppColors.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(q.question,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.5)),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded,
                      size: 20, color: AppColors.textTertiary),
                  onSelected: (v) async {
                    if (v == 'edit') {
                      _showEditor(context, ref, existing: q);
                    } else if (v == 'toggle') {
                      await SupabaseService.client
                          .from('quiz_questions')
                          .update({'is_active': !q.isActive}).eq('id', q.id);
                      ref.invalidate(quizQuestionsProvider);
                    } else if (v == 'delete') {
                      await SupabaseService.client
                          .from('quiz_questions')
                          .delete()
                          .eq('id', q.id);
                      ref.invalidate(quizQuestionsProvider);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('편집')),
                    PopupMenuItem(
                        value: 'toggle',
                        child: Text(q.isActive ? '내리기' : '다시 올리기')),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('삭제',
                          style: TextStyle(color: AppColors.danger)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                for (final a in q.answers)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.studentGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(a,
                        style: GoogleFonts.notoSansKr(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.studentGreen)),
                  ),
              ],
            ),
            if (!q.isActive)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('내려둔 문제',
                    style: GoogleFonts.notoSansKr(
                        fontSize: 11, color: AppColors.textTertiary)),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showEditor(BuildContext context, WidgetRef ref,
    {QuizQuestion? existing}) async {
  final question = TextEditingController(text: existing?.question ?? '');
  final answers =
      TextEditingController(text: existing?.answers.join(', ') ?? '');
  final hint = TextEditingController(text: existing?.hint ?? '');
  final schoolId = ref.read(profileProvider).value?.schoolId;
  if (schoolId == null) return;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(existing == null ? '문제 추가' : '문제 편집',
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: question,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '문제',
                hintText: '예) 충암중학교 수업 규칙을 한 마디로 부르는 말은?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: answers,
              decoration: const InputDecoration(
                labelText: '정답 (쉼표로 구분)',
                hintText: '3끝, 삼끝, 충암 3끝',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Text('여러 개 적으면 그중 하나만 맞아도 정답이에요.',
                style: GoogleFonts.notoSansKr(
                    fontSize: 11.5, color: AppColors.textTertiary)),
            const SizedBox(height: 12),
            TextField(
              controller: hint,
              decoration: const InputDecoration(
                labelText: '힌트 (선택)',
                hintText: '비우면 첫 정답의 초성이 힌트로 나가요',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.teacherNavy),
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: const Text('저장'),
        ),
      ],
    ),
  );
  if (saved != true) return;

  final list = answers.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (question.text.trim().isEmpty || list.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문제와 정답을 모두 적어주세요.')),
      );
    }
    return;
  }

  try {
    final data = {
      'question': question.text.trim(),
      'answers': list,
      'hint': hint.text.trim().isEmpty ? null : hint.text.trim(),
    };
    if (existing == null) {
      await SupabaseService.client.from('quiz_questions').insert({
        ...data,
        'school_id': schoolId,
        'created_by': SupabaseService.client.auth.currentUser?.id,
      });
    } else {
      await SupabaseService.client
          .from('quiz_questions')
          .update(data)
          .eq('id', existing.id);
    }
    ref.invalidate(quizQuestionsProvider);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(translateError(e))));
    }
  }
}
