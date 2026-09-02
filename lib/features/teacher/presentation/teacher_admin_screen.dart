import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';

class TeacherAccount {
  const TeacherAccount({
    required this.profileId,
    required this.userId,
    required this.name,
    required this.isAdmin,
    this.grade,
    this.classNum,
  });

  final String profileId;
  final String userId;
  final String name;
  final bool isAdmin;
  final int? grade;
  final int? classNum;

  String? get homeroom =>
      (grade == null || classNum == null) ? null : '$grade학년 $classNum반';

  factory TeacherAccount.fromMap(Map<String, dynamic> m) => TeacherAccount(
        profileId: m['id'] as String,
        userId: m['user_id'] as String,
        name: (m['name'] as String?) ?? (m['nickname'] as String?) ?? '이름 없음',
        isAdmin: (m['teacher_role'] as String?) == 'admin',
        grade: (m['grade'] as num?)?.toInt(),
        classNum: (m['class_num'] as num?)?.toInt(),
      );
}

final teacherAccountsProvider =
    FutureProvider<List<TeacherAccount>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile?.schoolId == null) return [];
  final rows = await SupabaseService.client
      .from('profiles')
      .select('id, user_id, name, nickname, teacher_role, grade, class_num')
      .eq('school_id', profile!.schoolId!)
      .eq('role', 'teacher')
      .order('name');
  return rows.map((m) => TeacherAccount.fromMap(m)).toList();
});

/// 👩‍🏫 선생님 관리 — 관리자 전용.
/// 비밀번호를 잊은 선생님을 즉시 초기화하고, 떠난 선생님 계정을 정리한다.
/// 메일 발송은 시간당 2건 제한이라 현장에서 쓸 수 없어 직접 처리한다.
class TeacherAdminScreen extends ConsumerWidget {
  const TeacherAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(teacherAccountsProvider);
    final me = ref.watch(profileProvider).value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('👩‍🏫 선생님 관리',
            style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(teacherAccountsProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(translateError(e))),
          data: (teachers) => ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              PbsCard(
                color: AppColors.teacherNavyLight,
                child: Text(
                  '비밀번호를 잊으신 선생님은 여기서 바로 초기화할 수 있어요.\n'
                  '임시 비밀번호를 정해 알려드리면 됩니다.',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 12.5,
                      height: 1.6,
                      color: AppColors.teacherNavy),
                ),
              ),
              const SectionHeader(title: '선생님 목록'),
              ...teachers.map((t) => _TeacherTile(
                    t: t,
                    isMe: t.userId == me?.userId,
                  )),
              const SizedBox(height: AppSizes.xxxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeacherTile extends ConsumerWidget {
  const _TeacherTile({required this.t, required this.isMe});
  final TeacherAccount t;
  final bool isMe;

  /// 읽어주기 쉬운 임시 비밀번호. 헷갈리는 글자(0/O, 1/l)는 뺀다.
  static String _tempPassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final pw = _tempPassword();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('${t.name} 선생님 비밀번호 초기화',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('아래 임시 비밀번호로 바꿉니다.',
                style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                pw,
                textAlign: TextAlign.center,
                style: GoogleFonts.robotoMono(
                    fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 2),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '이 비밀번호를 선생님께 직접 알려주세요.\n'
              '로그인하신 뒤 바꾸시면 됩니다.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 12, height: 1.6, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('취소')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.teacherNavy),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final res = await SupabaseService.client.rpc('reset_teacher_password',
          params: {'p_profile_id': t.profileId, 'p_new_password': pw});
      final m = Map<String, dynamic>.from(res as Map);
      if (m['ok'] != true) throw StateError(m['error'] as String? ?? '실패');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text('${t.name} 선생님 임시 비밀번호: $pw'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('${t.name} 선생님 계정 삭제',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
        content: Text(
          '이 선생님의 계정을 삭제할까요?\n\n'
          '로그인할 수 없게 되고, 되돌릴 수 없어요.\n'
          '남기신 칭찬과 기록은 그대로 있습니다.',
          style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('삭제하기'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final res = await SupabaseService.client
          .rpc('delete_teacher', params: {'p_profile_id': t.profileId});
      final m = Map<String, dynamic>.from(res as Map);
      if (m['ok'] != true) throw StateError(m['error'] as String? ?? '실패');
      ref.invalidate(teacherAccountsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${m['name']} 선생님 계정을 삭제했어요.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: PbsCard(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md, vertical: AppSizes.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(t.name,
                          style: GoogleFonts.notoSansKr(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      if (t.isAdmin) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.teacherNavy
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('관리자',
                              style: GoogleFonts.notoSansKr(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.teacherNavy)),
                        ),
                      ],
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Text('(나)',
                            style: GoogleFonts.notoSansKr(
                                fontSize: 11, color: AppColors.textTertiary)),
                      ],
                    ],
                  ),
                  if (t.homeroom != null)
                    Text('담임 ${t.homeroom}',
                        style: GoogleFonts.notoSansKr(
                            fontSize: 11.5, color: AppColors.textTertiary)),
                ],
              ),
            ),
            if (!isMe)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppColors.textTertiary),
                onSelected: (v) {
                  if (v == 'reset') _reset(context, ref);
                  if (v == 'delete') _delete(context, ref);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'reset', child: Text('비밀번호 초기화')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('계정 삭제',
                        style: TextStyle(color: AppColors.danger)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
