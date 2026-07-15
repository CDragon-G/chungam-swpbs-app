import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/school_code_generator.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../../shared/widgets/website_link_button.dart';
import '../../../shared/widgets/wizard.dart';
import '../../../shared/widgets/wizard_stack.dart';
import '../../school/models/school.dart';
import '../../school/providers/school_provider.dart';
import '../providers/auth_provider.dart';

enum _Mode { newSchool, joinSchool }

class TeacherSignupScreen extends ConsumerStatefulWidget {
  const TeacherSignupScreen({super.key});

  @override
  ConsumerState<TeacherSignupScreen> createState() => _State();
}

class _State extends ConsumerState<TeacherSignupScreen> {
  static const _totalSteps = 6;
  final _scrollController = ScrollController();
  int _step = 0;

  _Mode _mode = _Mode.newSchool;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _schoolName = TextEditingController();
  String _region = AppStrings.regions.first;
  String _level = '중학교';

  final _schoolCode = TextEditingController();
  School? _verifiedSchool;
  bool _verifying = false;
  String? _codeError;

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _schoolNameFocus = FocusNode();
  final _schoolCodeFocus = FocusNode();

  bool _agreedPrivacy = false;
  bool _loading = false;
  String? _stepError;

  @override
  void dispose() {
    _scrollController.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _schoolName.dispose();
    _schoolCode.dispose();
    for (final f in [
      _nameFocus,
      _emailFocus,
      _passwordFocus,
      _schoolNameFocus,
      _schoolCodeFocus,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _isLast => _step == _totalSteps - 1;

  String? _validateStep() {
    switch (_step) {
      case 0:
        return null; // mode select
      case 1:
        if (_name.text.trim().isEmpty) return '이름을 입력해주세요.';
        return null;
      case 2:
        final v = _email.text.trim();
        if (v.isEmpty) return '이메일을 입력해주세요.';
        if (!v.contains('@') || !v.contains('.')) {
          return '이메일 형식이 올바르지 않아요. 예: name@gmail.com';
        }
        return null;
      case 3:
        if (_password.text.isEmpty) return '비밀번호를 입력해주세요.';
        if (_password.text.length < 6) {
          return '비밀번호는 6자 이상이어야 해요. (현재 ${_password.text.length}자)';
        }
        return null;
      case 4:
        if (_mode == _Mode.newSchool) {
          if (_schoolName.text.trim().isEmpty) return '학교명을 입력해주세요.';
          return null;
        } else {
          if (_verifiedSchool == null) {
            return '교사 코드를 입력하고 "확인" 버튼을 눌러주세요.';
          }
          return null;
        }
      case 5:
        if (!_agreedPrivacy) return '개인정보처리방침에 동의해주세요.';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusCurrent();
      _scrollToBottom();
    });
  }

  void _focusCurrent() {
    switch (_step) {
      case 1:
        _nameFocus.requestFocus();
        break;
      case 2:
        _emailFocus.requestFocus();
        break;
      case 3:
        _passwordFocus.requestFocus();
        break;
      case 4:
        if (_mode == _Mode.newSchool) {
          _schoolNameFocus.requestFocus();
        } else {
          _schoolCodeFocus.requestFocus();
        }
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
    if (code.length < 6) {
      setState(() {
        _codeError = '교사 코드를 다시 확인해주세요.';
        _verifiedSchool = null;
      });
      return;
    }
    setState(() {
      _verifying = true;
      _codeError = null;
    });
    try {
      // 교사는 교사 전용 코드(teacher_code)로 검증 (학생 코드와 분리)
      final s = await ref.read(schoolRepositoryProvider).findByTeacherCode(code);
      setState(() {
        _verifiedSchool = s;
        if (s == null) {
          _codeError = '교사 코드가 일치하지 않아요. 학교 관리자에게 받은 코드인지 확인해주세요.';
        }
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

      String schoolId;
      String teacherRole;
      if (_mode == _Mode.newSchool) {
        final school = await ref.read(schoolRepositoryProvider).createSchool(
              name: _schoolName.text.trim(),
              region: _region,
              level: _level,
            );
        schoolId = school.id;
        teacherRole = 'admin';
      } else {
        schoolId = _verifiedSchool!.id;
        teacherRole = 'regular';
      }
      await auth.createProfile(
        role: 'teacher',
        nickname: _name.text.trim(),
        schoolId: schoolId,
        teacherRole: teacherRole,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_login_email', _email.text.trim());
      ref.invalidate(profileProvider);
      if (!mounted) return;
      context.go('/teacher/home');
    } catch (e) {
      setState(() => _stepError = translateError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _labelFor(int step) {
    switch (step) {
      case 0:
        return '시작 방식';
      case 1:
        return '이름';
      case 2:
        return '이메일';
      case 3:
        return '비밀번호';
      case 4:
        return _mode == _Mode.newSchool ? '학교 정보' : '교사 코드';
      case 5:
        return '동의';
    }
    return '';
  }

  String _summaryFor(int step) {
    switch (step) {
      case 0:
        return _mode == _Mode.newSchool ? '👑 새 학교 등록' : '👥 기존 학교 참여';
      case 1:
        return _name.text.trim();
      case 2:
        return _email.text.trim();
      case 3:
        return '•' * _password.text.length;
      case 4:
        if (_mode == _Mode.newSchool) {
          return '${_schoolName.text} · $_region · $_level';
        } else {
          return _verifiedSchool == null
              ? ''
              : '${_verifiedSchool!.name} (${_verifiedSchool!.region})';
        }
      case 5:
        return '동의 완료';
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
              color: AppColors.teacherNavy,
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < _step; i++)
                      WizardSummaryTile(
                        label: _labelFor(i),
                        value: _summaryFor(i),
                        accentColor: AppColors.teacherNavy,
                        onTap: () => _jumpToStep(i),
                      ),
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
              color: AppColors.teacherNavy,
              lastLabel:
                  _mode == _Mode.newSchool ? '학교 만들고 가입' : '학교에 참여하기',
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
          prompt: '어떻게\n시작할까요?',
          helper: '새 학교 등록은 관리자가 되고, 기존 학교 참여는 일반 교사가 돼요.',
          input: Column(
            children: [
              _ModeOption(
                selected: _mode == _Mode.newSchool,
                emoji: '👑',
                title: '새 학교 등록',
                subtitle: '자동으로 관리자 권한 부여\n규칙·교환소·공지 편집 가능',
                onTap: () => setState(() => _mode = _Mode.newSchool),
              ),
              const SizedBox(height: 12),
              _ModeOption(
                selected: _mode == _Mode.joinSchool,
                emoji: '👥',
                title: '기존 학교 참여',
                subtitle: '일반 교사로 가입\n관리자가 권한 승급 가능',
                onTap: () => setState(() => _mode = _Mode.joinSchool),
              ),
            ],
          ),
        );
      case 1:
        return WizardActiveStep(
          prompt: '선생님 이름을\n입력해주세요',
          helper: '학교 동료·학생들에게 표시됩니다.',
          input: PbsTextField(
            controller: _name,
            focusNode: _nameFocus,
            label: '이름',
            hint: '예: 김선생',
            onChanged: (_) {
              if (_stepError != null) setState(() => _stepError = null);
            },
            onSubmitted: (_) => _next(),
          ),
        );
      case 2:
        return WizardActiveStep(
          prompt: '이메일을\n입력해주세요',
          helper: '로그인 시 사용합니다.',
          input: PbsTextField(
            controller: _email,
            focusNode: _emailFocus,
            label: '이메일',
            hint: 'teacher@school.kr',
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) {
              if (_stepError != null) setState(() => _stepError = null);
            },
            onSubmitted: (_) => _next(),
          ),
        );
      case 3:
        return WizardActiveStep(
          prompt: '비밀번호를\n설정해주세요',
          helper: '6자 이상 입력해주세요.',
          input: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PbsTextField(
                controller: _password,
                focusNode: _passwordFocus,
                label: '비밀번호',
                hint: '6자 이상',
                obscure: true,
                onChanged: (_) => setState(() {
                  if (_stepError != null) _stepError = null;
                }),
                onSubmitted: (_) => _next(),
              ),
              const SizedBox(height: 10),
              WizardPasswordStrength(text: _password.text),
            ],
          ),
        );
      case 4:
        return _mode == _Mode.newSchool ? _stepNewSchool() : _stepJoinSchool();
      case 5:
        return WizardActiveStep(
          prompt: '마지막이에요!\n동의해주세요',
          helper: '개인정보처리방침 동의 후 가입을 완료합니다.',
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
            ],
          ),
        );
    }
    return const SizedBox.shrink();
  }

  Widget _stepNewSchool() => WizardActiveStep(
        prompt: '학교 정보를\n입력해주세요',
        helper: '학교명·지역·학교급을 선택하세요. 가입 후 6자리 학교 코드가 자동 발급됩니다.',
        input: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PbsTextField(
              controller: _schoolName,
              focusNode: _schoolNameFocus,
              label: '학교명',
              hint: '예: 충암중학교',
              onChanged: (_) {
                if (_stepError != null) setState(() => _stepError = null);
              },
            ),
            const SizedBox(height: AppSizes.lg),
            Text(
              '지역',
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _region,
                  isExpanded: true,
                  items: [
                    for (final r in AppStrings.regions)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: (v) => setState(() => _region = v ?? _region),
                ),
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Text(
              '학교급',
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final lv in const ['초등학교', '중학교', '고등학교']) ...[
                  Expanded(
                    child: ChoiceChip(
                      label: Text(lv),
                      selected: _level == lv,
                      onSelected: (_) => setState(() => _level = lv),
                      selectedColor: AppColors.teacherNavy,
                      labelStyle: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w700,
                        color: _level == lv
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSizes.radiusMd),
                        side: BorderSide(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 12),
                    ),
                  ),
                  if (lv != '고등학교') const SizedBox(width: AppSizes.sm),
                ],
              ],
            ),
            const SizedBox(height: 12),
            const WebsiteLinkButton(),
          ],
        ),
      );

  Widget _stepJoinSchool() => WizardActiveStep(
        prompt: '교사 코드를\n입력해주세요',
        helper: '학교 관리자(최초 등록 교사)에게 받은 8자리 교사 코드를 입력하세요.\n'
            '학생용 학교 코드와는 다른 코드예요.',
        input: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: PbsTextField(
                    controller: _schoolCode,
                    focusNode: _schoolCodeFocus,
                    label: '교사 코드',
                    hint: '예: K7M2X9PQ',
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 8,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
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
                        backgroundColor: AppColors.teacherNavy,
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
                color: AppColors.teacherNavyLight,
                border: Border.all(color: AppColors.teacherNavy),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.teacherNavy),
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
            const SizedBox(height: 10),
            const WebsiteLinkButton(),
          ],
        ),
      );
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.selected,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(AppSizes.lg),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.teacherNavyLight : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.teacherNavy : AppColors.borderLight,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.teacherNavy, size: 24),
          ],
        ),
      ),
    );
  }
}
