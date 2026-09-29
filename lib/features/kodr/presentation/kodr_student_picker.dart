import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../models/kodr.dart';

/// K-ODR 학생 고르기 — 여러 명, 가입하지 않은 학생도.
///
/// 한 사건에 여러 학생이 함께 있었을 때 한 번에 고른다.
/// 명렬표 전체에서 고르므로 앱에 가입하지 않은 학생도 나온다 ('미가입' 표시).
/// 확인을 누르면 고른 학생 목록을, 닫으면 null 을 돌려준다.
class KodrStudentPicker {
  static Future<List<KodrStudentOption>?> show(
    BuildContext context,
    List<KodrStudentOption> students, {
    List<KodrStudentOption> initial = const [],
  }) {
    return showModalBottomSheet<List<KodrStudentOption>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _Body(students: students, initial: initial),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.students, required this.initial});
  final List<KodrStudentOption> students;
  final List<KodrStudentOption> initial;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  static const _max = 30;
  String _query = '';
  late final Set<String> _picked =
      widget.initial.map((s) => s.rosterId).toSet();

  bool _matches(KodrStudentOption s) {
    final q = _query.trim().replaceAll(' ', '');
    if (q.isEmpty) return true;
    final combos = [
      s.name.replaceAll(' ', ''),
      '${s.grade}-${s.classNum}-${s.studentNum}',
      '${s.grade}-${s.classNum}',
      '${s.grade}학년${s.classNum}반${s.studentNum}번',
      '${s.grade}학년${s.classNum}반',
      '${s.grade}${s.classNum.toString().padLeft(2, '0')}${s.studentNum.toString().padLeft(2, '0')}',
    ];
    return combos.any((x) => x.contains(q));
  }

  void _toggle(KodrStudentOption s) {
    setState(() {
      if (_picked.contains(s.rosterId)) {
        _picked.remove(s.rosterId);
      } else if (_picked.length < _max) {
        _picked.add(s.rosterId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('한 번에 30명까지 고를 수 있어요')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.students.where(_matches).toList();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.94,
        builder: (_, ctrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.lg, AppSizes.md, AppSizes.lg, AppSizes.sm),
              child: Row(
                children: [
                  Text('학생 고르기',
                      style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(width: 8),
                  Text('여러 명 고를 수 있어요',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 12, color: AppColors.textTertiary)),
                  const Spacer(),
                  if (_picked.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_picked.clear),
                      child: Text('모두 해제',
                          style: GoogleFonts.notoSansKr(fontSize: 12)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
              child: TextField(
                style: GoogleFonts.notoSansKr(fontSize: 14),
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: '이름 · 2-3 · 2-3-15',
                  hintMaxLines: 1,
                  hintStyle: GoogleFonts.notoSansKr(
                      fontSize: 13, color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.background,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: widget.students.isEmpty
                  ? Center(
                      child: Text('학생 명단이 비어 있어요.\n관리자 선생님께 명단 등록을 요청해 주세요.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansKr(
                              height: 1.6, color: AppColors.textTertiary)),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Text('검색 결과가 없어요.',
                              style: GoogleFonts.notoSansKr(
                                  color: AppColors.textTertiary)),
                        )
                      : ListView.builder(
                          controller: ctrl,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            final on = _picked.contains(s.rosterId);
                            return CheckboxListTile(
                              value: on,
                              onChanged: (_) => _toggle(s),
                              activeColor: AppColors.teacherNavy,
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(s.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.notoSansKr(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14)),
                                  ),
                                  if (!s.joined) ...[
                                    const SizedBox(width: 6),
                                    const _Tag('미가입'),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                '${s.grade}학년 ${s.classNum}반 ${s.studentNum}번',
                                style: GoogleFonts.notoSansKr(
                                    fontSize: 11,
                                    color: AppColors.textSecondary),
                              ),
                            );
                          },
                        ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSizes.lg, AppSizes.sm, AppSizes.lg, AppSizes.md),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.teacherNavy),
                    onPressed: _picked.isEmpty
                        ? null
                        : () => Navigator.pop(
                              context,
                              widget.students
                                  .where((s) => _picked.contains(s.rosterId))
                                  .toList(),
                            ),
                    child: Text(
                        _picked.isEmpty
                            ? '학생을 골라주세요'
                            : '${_picked.length}명 고르기',
                        style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.borderLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: GoogleFonts.notoSansKr(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary)),
    );
  }
}
