import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../providers/auth_provider.dart';

/// 비밀번호 찾기 — 이메일로 6자리 코드를 받아 새 비밀번호를 설정한다.
/// 성공하면 곧바로 로그인 상태가 되어 홈으로 이동한다.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _sent = false; // 코드 발송 완료 → 2단계
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _pw1.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = '이메일 형식이 올바르지 않아요.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
      setState(() => _sent = true);
    } catch (e) {
      setState(() => _error = translateError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = '이메일로 받은 6자리 코드를 입력해주세요.');
      return;
    }
    if (_pw1.text.length < 6) {
      setState(() => _error = '새 비밀번호는 6자 이상이어야 해요.');
      return;
    }
    if (_pw1.text != _pw2.text) {
      setState(() => _error = '새 비밀번호가 서로 달라요. 다시 확인해주세요.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).confirmPasswordReset(
            email: _email.text.trim(),
            token: code,
            newPassword: _pw1.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('비밀번호가 변경됐어요. 자동으로 로그인합니다.',
              style: GoogleFonts.notoSansKr()),
        ),
      );
      // verifyOTP 성공 시 세션이 생기므로 라우터가 홈으로 보낸다.
      context.go('/splash');
    } catch (e) {
      setState(() => _error = translateError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '비밀번호 찾기',
                style: GoogleFonts.notoSansKr(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _sent
                    ? '${_email.text.trim()} 로 6자리 코드를 보냈어요.\n메일함(스팸함 포함)을 확인해주세요.'
                    : '가입할 때 사용한 이메일을 입력하면\n재설정 코드를 보내드려요.',
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSizes.xxl),

              if (!_sent) ...[
                PbsTextField(
                  controller: _email,
                  label: '이메일',
                  keyboardType: TextInputType.emailAddress,
                  hint: 'example@school.kr',
                ),
              ] else ...[
                PbsTextField(
                  controller: _code,
                  label: '인증 코드 (6자리)',
                  keyboardType: TextInputType.number,
                  hint: '이메일로 받은 숫자 코드',
                ),
                const SizedBox(height: AppSizes.lg),
                PbsTextField(
                  controller: _pw1,
                  label: '새 비밀번호 (6자 이상)',
                  obscure: true,
                ),
                const SizedBox(height: AppSizes.lg),
                PbsTextField(
                  controller: _pw2,
                  label: '새 비밀번호 확인',
                  obscure: true,
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: AppSizes.md),
                Container(
                  padding: const EdgeInsets.all(AppSizes.md),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    _error!,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: AppSizes.xxl),
              PbsPrimaryButton(
                label: _sent ? '비밀번호 변경' : '재설정 코드 보내기',
                loading: _loading,
                onPressed: _sent ? _confirm : _sendCode,
              ),
              if (_sent) ...[
                const SizedBox(height: AppSizes.sm),
                TextButton(
                  onPressed: _loading ? null : _sendCode,
                  child: Text(
                    '코드가 안 왔어요 → 다시 보내기',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: AppSizes.xl),
              PbsCard(
                color: AppColors.studentGreenLight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🎒 학생인가요?',
                      style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.studentGreen,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '이메일이 기억나지 않거나 메일을 확인하기 어려우면,\n'
                      '담임 선생님께 요청하세요. 선생님이 앱에서\n'
                      '이메일 확인과 비밀번호 초기화를 바로 해줄 수 있어요.',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
