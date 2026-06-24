import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/school_code_generator.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../../shared/widgets/wizard.dart';
import '../../../shared/widgets/wizard_stack.dart';
import '../../school/models/school.dart';
import '../../school/providers/school_provider.dart';
import '../providers/auth_provider.dart';

/// 토스 스타일 누적식 회원가입 화면.
/// 이전 입력은 위로 쌓이고, 새 입력 필드는 항상 아래(키보드 위)에 등장합니다.
class StudentSignupScreen extends ConsumerStatefulWidget {
  const StudentSignupScreen({super.key});

  @override
  ConsumerState<StudentSignupScreen> createState() => _State();
}

class _State extends ConsumerState<StudentSignupScreen> {
  static const _totalSteps = 6;

  final _scrollController = ScrollController();
  int _step = 0;

  final _nickname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _schoolCode = TextEditingController();
  final _grade = TextEditingController();
  final _classNum = TextEditingController();
  final _studentNum = TextEditingController();

  final _nicknameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _schoolFocus = FocusNode();
  final _gradeFocus = FocusNode();

  School? _verifiedSchool;
  bool _verifying = false;
  String? _codeError;

  bool _agreedPrivacy = false;
  bool _agreedAge = false;

  bool _loading = false;
  String? _stepError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nicknameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final c in [
      _nickname,
      _email,
      _password,
      _schoolCode,
      _grade,
      _classNum,
      _studentNum,
    ]) {
      c.dispose();
    }
    for (final f in [
      _nicknameFocus,
      _emailFocus,
      _passwordFocus,
      _schoolFocus,
      _gradeFocus,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _isLast => _step == _totalSteps - 1;

  String? _validateStep() {
    switch (_step) {
      case 0:
        final v = _nickname.text.trim();
        if (v.isEmpty) return '이름(닉네임)을 입력해주세요.';
        if (v.length > 20) return '이름은 20자 이하로 입력해주세요.';
        return null;
      case 1:
        final v = _email.text.trim();
        if (v.isEmpty) return '이메일을 입력해주세요.';
        if (!v.contains('@') || !v.contains('.')) {
          return '이메일 형식이 올바르지 않아요. 예: name@gmail.com';
        }
        return null;
      case 2:
        if (_password.text.isEmpty) return '비밀번호를 입력해주세요.';
        if (_password.text.length < 6) {
          return '비밀번호는 6자 이상이어야 해요. (현재 ${_password.text.length}자)';
        }
        return null;
      case 3:
        if (_verifiedSchool == null) {
          return '학교 코드를 입력하고 "확인" 버튼을 눌러주세요.';
        }
        return null;
      case 4:
        if (int.tryParse(_grade.text) == null) return '학년을 숫자로 입력해주세요.';
        if (int.tryParse(_classNum.text) == null) return '반을 숫자로 입력해주세요.';
        if (int.tryParse(_studentNum.text) == null) return '번호를 숫자로 입력해주세요.';
        return null;
      case 5:
        if (!_agreedPrivacy) return '개인정보처리방침에 동의해주세요.';
        if (!_agreedAge) return '만 14세 이상 또는 보호자 동의가 필요해요.';
        return null;
    }
    return null;
  }

  Future<void> _next() async {
    final err = _validateStep();
    if (err != null) {
      setState(() => _stepError = err);
      return;
    }
    setState(() => _stepError = null);
    if (_isLast) {
      FocusScope.of(context).unfocus();
      await _submit();
      return;
    }
    setState(() => _step++);
    // 다음 스텝의 입력 필드로 포커스 이동 + 스크롤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusCurrent();
      _scrollToBottom();
    });
  }

  void _focusCurrent() {
    switch (_step) {
      case 1:
        _emailFocus.requestFocus();
        break;
      case 2:
        _passwordFocus.requestFocus();
        break;
      case 3:
        _schoolFocus.requestFocus();
        break;
      case 4:
        _gradeFocus.requestFocus();
        break;
      default:
        FocusScope.of(context).unfocus();
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    if (_step == 0) {
      context.go('/signup-select');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _step--;
      _stepError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusCurrent());
  }

  void _jumpToStep(int target) {
    if (target >= _step) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _step = target;
      _stepError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusCurrent());
  }

  Future<void> _verifyCode() async {
    final code = SchoolCodeGenerator.normalize(_schoolCode.text);
    if (code.length < 4) {
      setState(() {
        _codeError = '학교 코드를 다시 확인해주세요.';
        _verifiedSchool = null;
      });
      return;
    }
    setState(() {
      _verifying = true;
      _codeError = null;
    });
    try {
      final s = await ref.read(schoolRepositoryProvider).findByCode(code);
      setState(() {
        _verifiedSchool = s;
        if (s == null) _codeError = '학교 코드가 일치하지 않아요.';
      });
    } catch (e) {
      setState(() => _codeError = translateError(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _stepError = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      // 가입 시도 (이미 존재하는 이메일이면 로그인으로 복구)
      await auth.signUpOrRecover(
        email: _email.text.trim(),
        password: _password.text,
      );
      await auth.createProfile(
        role: 'student',
        nickname: _nickname.text.trim(),
        schoolId: _verifiedSchool!.id,
        grade: int.parse(_grade.text),
        classNum: int.parse(_classNum.text),
        studentNum: int.parse(_studentNum.text),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_login_email', _email.text.trim());
      ref.invalidate(profileProvider);
      if (!mounted) return;
      context.go('/student/home');
    } catch (e) {
      setState(() => _stepError = translateError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── 토스 스타일: 완료된 스텝들을 위에 누적해서 보여줌 ──────────────

  String _summaryFor(int step) {
    switch (step) {
      case 0:
        return _nickname.text.trim();
      case 1:
        return _email.text.trim();
      case 2:
        return '•' * _password.text.length;
      case 3:
        return _verifiedSchool == null
            ? ''
            : '${_verifiedSchool!.name} (${_verifiedSchool!.region})';
      case 4:
        return '${_grade.text}학년 ${_classNum.text}반 ${_studentNum.text}번';
      case 5:
        return '동의 완료';
    }
    return '';
  }

  String _labelFor(int step) {
    switch (step) {
      case 0:
        return '이름';
      case 1:
        return '이메일';
      case 2:
        return '비밀번호';
      case 3:
        return '학교';
      case 4:
        return '학년·반·번호';
      case 5:
        return '동의';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            WizardHeader(
              step: _step,
              total: _totalSteps,
              onBack: _back,
              color: AppColors.studentGreen,
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ① 이전 입력들 — 가장 오래된 것이 위, 최신이 아래
                    for (int i = 0; i < _step; i++)
                      WizardSummaryTile(
                        label: _labelFor(i),
                        value: _summaryFor(i),
                        accentColor: AppColors.studentGreen,
                        onTap: () => _jumpToStep(i),
                      ),
                    // ② 현재 스텝 — 항상 맨 아래 (키보드 바로 위)
                    _activeStep(),
                  ],
                ),
              ),
            ),
            WizardFooter(
              error: _stepError,
              loading: _loading,
              isLast: _isLast,
              onNext: _next,
              color: AppColors.studentGreen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeStep() {
    switch (_step) {
      case 0:
        return WizardActiveStep(
          prompt: '안녕하세요!\n어떻게 불러드릴까요?',
          helper: '닉네임 또는 이름을 입력하면 화면에 표시돼요.',
          input: PbsTextField(
            controller: _nickname,
            focusNode: _nicknameFocus,
            label: '이름 / 닉네임',
            hint: '예: 홍길동',
            onChanged: (_) {
              if (_stepError != null) setState(() => _stepError = null);
            },
            onSubmitted: (_) => _next(),
          ),
        );
      case 1:
        return WizardActiveStep(
          prompt: '이메일을\n입력해주세요',
          helper: '로그인 시 사용해요. 평소 쓰는 이메일을 추천합니다.',
          input: PbsTextField(
            controller: _email,
            focusNode: _emailFocus,
            label: '이메일',
            hint: 'name@gmail.com',
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) {
              if (_stepError != null) setState(() => _stepError = null);
            },
            onSubmitted: (_) => _next(),
          ),
        );
      case 2:
        return WizardActiveStep(
          prompt: '비밀번호를\n설정해주세요',
          helper: '6자 이상 입력해주세요. 단순한 비밀번호는 피해주세요.',
          input: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PbsTextField(
                controller: _password,
                focusNode: _passwordFocus,
                label: '비밀번호',
                hint: '6자 이상',
                obscure: true,
                onChanged: (_) {
                  setState(() {
                    if (_stepError != null) _stepError = null;
                  });
                },
                onSubmitted: (_) => _next(),
              ),
              const SizedBox(height: 10),
              WizardPasswordStrength(text: _password.text),
            ],
          ),
        );
      case 3:
        return WizardActiveStep(
          prompt: '학교 코드를\n입력해주세요',
          helper: '담임선생님께 받은 6자리 코드를 입력하세요.',
          input: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: PbsTextField(
                      controller: _schoolCode,
                      focusNode: _schoolFocus,
                      label: '학교 코드',
                      hint: '예: AA8585',
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Z0-9]')),
                      ],
                      onChanged: (_) => setState(() {
                        _verifiedSchool = null;
                        _codeError = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Padding(
                    padding: const EdgeInsets.only(top: 22),
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _verifying ? null : _verifyCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.studentGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppSizes.radiusMd),
                          ),
                        ),
                        child: _verifying
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                '확인',
                                style: GoogleFonts.notoSansKr(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_codeError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _codeError!,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                  ),
                ),
              ],
              if (_verifiedSchool != null) ...[
                const SizedBox(height: 12),
                PbsCard(
                  color: AppColors.studentGreenLight,
                  border: Border.all(color: AppColors.studentGreen),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.studentGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_verifiedSchool!.name} (${_verifiedSchool!.region})',
                          style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      case 4:
        return WizardActiveStep(
          prompt: '학년·반·번호를\n입력해주세요',
          helper: '담임선생님이 학급별 관리에 사용해요.',
          input: Row(
            children: [
              Expanded(
                child: PbsTextField(
                  controller: _grade,
                  focusNode: _gradeFocus,
                  label: '학년',
                  keyboardType: TextInputType.number,
                  onChanged: (_) {
                    if (_stepError != null) setState(() => _stepError = null);
                  },
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: PbsTextField(
                  controller: _classNum,
                  label: '반',
                  keyboardType: TextInputType.number,
                  onChanged: (_) {
                    if (_stepError != null) setState(() => _stepError = null);
                  },
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: PbsTextField(
                  controller: _studentNum,
                  label: '번호',
                  keyboardType: TextInputType.number,
                  onChanged: (_) {
                    if (_stepError != null) setState(() => _stepError = null);
                  },
                ),
              ),
            ],
          ),
        );
      case 5:
        return WizardActiveStep(
          prompt: '마지막이에요!\n동의가 필요해요',
          helper: '두 항목 모두 체크해야 가입할 수 있어요.',
          input: Column(
            children: [
              WizardConsentTile(
                checked: _agreedPrivacy,
                label: '개인정보처리방침에 동의합니다 (필수)',
                onChanged: (v) => setState(() {
                  _agreedPrivacy = v;
                  if (_stepError != null) _stepError = null;
                }),
              ),
              WizardConsentTile(
                checked: _agreedAge,
                label: '만 14세 이상이거나, 법정대리인(보호자)의 동의를 받았습니다 (필수)',
                onChanged: (v) => setState(() {
                  _agreedAge = v;
                  if (_stepError != null) _stepError = null;
                }),
              ),
            ],
          ),
        );
    }
    return const SizedBox.shrink();
  }
}
