import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';

/// 이름·학년·반·번호로 검색해 학생 1명을 고르는 바텀시트.
/// 수백 명 규모에서도 빠르게 찾도록 검색 필드를 제공한다.
/// 선택된 학생 Map을 반환하고, 취소하면 null.
class StudentPickerSheet {
  static Future<Map<String, dynamic>?> show(
    BuildContext context,
    List<Map<String, dynamic>> students, {
    String title = '학생 선택',
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PickerBody(students: students, title: title),
    );
  }
}

class _PickerBody extends StatefulWidget {
  const _PickerBody({required this.students, required this.title});
  final List<Map<String, dynamic>> students;
  final String title;

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  String _query = '';

  bool _matches(Map<String, dynamic> s) {
    if (_query.trim().isEmpty) return true;
    final q = _query.toLowerCase().replaceAll(' ', '');
    final name = (s['nickname'] as String? ?? '').toLowerCase();
    final g = '${s['grade']}';
    final c = '${s['class_num']}';
    final n = '${s['student_num']}';
    final combos = [
      name,
      '$g-$c-$n',
      '$g학년$c반$n번',
      '$g$c$n',
      n, // 번호만으로도
    ];
    return combos.any((x) => x.contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.students.where(_matches).toList();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
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
                  Text(widget.title,
                      style: GoogleFonts.notoSansKr(
                          fontWeight: FontWeight.w900, fontSize: 16)),
                  const Spacer(),
                  Text('${filtered.length}명',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 12, color: AppColors.textTertiary)),
                ],
              ),
            ),
            // 검색 필드
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
              child: TextField(
                autofocus: false,
                style: GoogleFonts.notoSansKr(fontSize: 14),
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: '이름 또는 학번 검색 (예: 신창용, 1-2-10, 10)',
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
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
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
                        final name = s['nickname'] as String? ?? '';
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.teacherNavy,
                            child: Text(
                              name.characters.isEmpty
                                  ? '?'
                                  : name.characters.first,
                              style: GoogleFonts.notoSansKr(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          title: Text(name,
                              style: GoogleFonts.notoSansKr(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text(
                            '${s['grade']}학년 ${s['class_num']}반 ${s['student_num']}번',
                            style: GoogleFonts.notoSansKr(
                                fontSize: 11, color: AppColors.textSecondary),
                          ),
                          onTap: () => Navigator.pop(context, s),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
