import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/update/update_gate.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/school_code_generator.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../providers/auth_provider.dart';

/// 🎪 강의 · 연수 체험 입장 (079).
///
/// 체험 코드 하나만 넣으면 PIN · 이메일 · 비밀번호 없이 학생으로 들어온다.
/// 서버가 '대구체험학생12' 처럼 번호와 반을 매긴다.
/// 강사가 열어 둔 체험 학교에서만 되고, 실제 학교 코드는 받지 않는다.
class DemoJoinScreen extends ConsumerStatefulWidget {
  const DemoJoinScreen({super.key});

  @override
  ConsumerState<DemoJoinScreen> createState() => _DemoJoinScreenState();
}

class _DemoJoinScreenState extends ConsumerState<DemoJoinScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = SchoolCodeGenerator.normalize(_code.text);
    if (code.length < 6) {
      setState(() => _error = '체험 코드 6자리를 넣어 주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!await ensureUpToDate(context)) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      await ref.read(authRepositoryProvider).joinDemoSchool(code);
      ref.invalidate(profileProvider);
      if (!mounted) return;
      context.go('/student/home');
    } catch (e) {
      if (mounted) setState(() => _error = translateError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 체험을 시작하지 않고 나가면, 만들어 둔 익명 로그인을 정리한다.
  Future<void> _leave() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo.isAnonymous && ref.read(profileProvider).value == null) {
      await repo.signOut();
    }
    if (mounted) context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _leave,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '체험 코드로 둘러보기',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '강의 · 연수에서 받은 체험 코드를 넣으면\n바로 학생 화면을 체험할 수 있어요.',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSizes.xxl),
                PbsTextField(
                  controller: _code,
                  label: '체험 코드',
                  hint: '예: AB12CD',
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _join(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    _error!,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
                ],
                const SizedBox(height: AppSizes.lg),
                PbsPrimaryButton(
                  label: '체험 시작',
                  icon: Icons.play_arrow_rounded,
                  color: AppColors.studentGreen,
                  loading: _loading,
                  onPressed: _join,
                ),
                const SizedBox(height: AppSizes.xl),
                PbsCard(
                  color: AppColors.studentGreenLight,
                  child: Text(
                    '· 이름 · 이메일 · 비밀번호를 받지 않아요.\n'
                    '· 번호가 붙은 체험 이름이 자동으로 정해져요.\n'
                    '· 로그아웃하면 같은 번호로는 못 들어와요.\n'
                    '· 체험 계정은 강의가 끝나면 지워져요.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12.5,
                      height: 1.7,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
