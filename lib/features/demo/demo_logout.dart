import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../auth/providers/auth_provider.dart';
import '../school/providers/school_provider.dart';

/// 체험용 계정이 실수로 로그아웃하지 않게 한 번 묻는다. 로그아웃해도 되면 true.
///
///   · 체험 코드로 들어온 계정(익명, 079) — 로그아웃하면 그 번호로는 다시 들어올 수 없다.
///   · 체험 부스 계정 — 부스 담당 선생님이 다시 로그인해야 한다.
/// 실제 학교 계정이면 묻지 않는다.
Future<bool> confirmDemoLogout(BuildContext context, WidgetRef ref) async {
  final anonymous = ref.read(authRepositoryProvider).isAnonymous;
  if (!anonymous && !ref.read(isDemoSchoolProvider)) return true;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('체험용 계정이에요',
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900)),
      content: Text(
        anonymous
            ? '로그아웃하면 이 번호로는 다시 못 들어와요.\n'
                '다시 하려면 체험 코드로 새로 시작해요.\n\n'
                '정말 로그아웃할까요?'
            : '로그아웃하면 부스 담당 선생님이 다시 로그인해야 해요.\n'
                '정말 로그아웃할까요?',
        style: GoogleFonts.notoSansKr(fontSize: 13, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('그대로 둘게요', style: GoogleFonts.notoSansKr()),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('로그아웃',
              style: GoogleFonts.notoSansKr(color: AppColors.danger)),
        ),
      ],
    ),
  );
  return ok == true;
}
