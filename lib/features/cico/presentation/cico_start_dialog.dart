import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../school/providers/school_provider.dart';
import '../providers/cico_provider.dart';

/// CICO 시작 다이얼로그 (공용).
/// CICO 홈과 K-ODR 현황 어디서든 학생을 지정해 시작할 수 있다.
Future<void> showCicoStartDialog(
  BuildContext context,
  WidgetRef ref, {
  required String studentUserId,
  required String studentName,
  String? initialReason,
}) async {
  final teachers = ref.read(schoolTeachersProvider).value ?? [];
  int goal = 80;
  String? mentorId; // null = 나(호출 교사)
  final reasonCtrl = TextEditingController(text: initialReason ?? '');
  var saving = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setSt) {
        Future<void> submit() async {
          setSt(() => saving = true);
          try {
            await ref.read(cicoRepositoryProvider).start(
                  studentUserId: studentUserId,
                  mentorId: mentorId,
                  goalPct: goal,
                  reason: reasonCtrl.text.trim().isEmpty
                      ? null
                      : reasonCtrl.text.trim(),
                );
            ref.invalidate(cicoEnrollmentsProvider);
            if (dialogCtx.mounted) Navigator.pop(dialogCtx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('$studentName 학생의 CICO를 시작했어요! 🤝'),
                backgroundColor: AppColors.studentGreen,
              ));
            }
          } catch (e) {
            if (!dialogCtx.mounted) return;
            setSt(() => saving = false);
            ScaffoldMessenger.of(dialogCtx)
                .showSnackBar(SnackBar(content: Text(translateError(e))));
          }
        }

        return AlertDialog(
          title: Text('$studentName 학생 CICO 시작',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('목표 달성률',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [60, 70, 80, 90].map((g) {
                      final sel = goal == g;
                      return ChoiceChip(
                        label: Text('$g%'),
                        selected: sel,
                        onSelected:
                            saving ? null : (_) => setSt(() => goal = g),
                        selectedColor: AppColors.teacherNavy,
                        labelStyle: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color:
                                sel ? Colors.white : AppColors.textPrimary),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text('멘토 선생님',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    initialValue: mentorId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd)),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('나 (담당 교사)',
                            style: GoogleFonts.notoSansKr(fontSize: 13)),
                      ),
                      ...teachers.map((t) => DropdownMenuItem<String?>(
                            value: t['user_id'] as String?,
                            child: Text('${t['nickname'] ?? ''} 선생님',
                                style: GoogleFonts.notoSansKr(fontSize: 13)),
                          )),
                    ],
                    onChanged:
                        saving ? null : (v) => setSt(() => mentorId = v),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    enabled: !saving,
                    style: GoogleFonts.notoSansKr(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: '시작 사유 (선택)',
                      hintText: '예: 6월 K-ODR 3건 — 수업 참여 지원',
                      labelStyle: GoogleFonts.notoSansKr(fontSize: 12),
                      hintStyle: GoogleFonts.notoSansKr(
                          fontSize: 12, color: AppColors.textTertiary),
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogCtx),
              child: Text('취소',
                  style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: saving ? null : submit,
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('시작하기',
                      style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w800,
                          color: AppColors.teacherNavy)),
            ),
          ],
        );
      },
    ),
  );
}
