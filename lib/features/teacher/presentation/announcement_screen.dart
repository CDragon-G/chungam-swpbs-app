import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../growth/growth_celebration.dart';
import '../../school/providers/school_provider.dart';

class AnnouncementScreen extends ConsumerStatefulWidget {
  const AnnouncementScreen({super.key});

  @override
  ConsumerState<AnnouncementScreen> createState() => _State();
}

class _State extends ConsumerState<AnnouncementScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) return;
    final profile = ref.read(profileProvider).value;
    if (profile?.schoolId == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(schoolRepositoryProvider).postAnnouncement(
            schoolId: profile!.schoolId!,
            title: _title.text.trim(),
            body: _body.text.trim(),
          );
      _title.clear();
      _body.clear();
      ref.invalidate(announcementsProvider);
      if (mounted) {
        celebrateGrowth(context, ref, headline: '공지를 등록했어요 📢');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final annsAsync = ref.watch(announcementsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '공지',
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          if (ref.watch(profileProvider).value?.isAdminTeacher ?? false)
          PbsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '새 공지 작성',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                PbsTextField(controller: _title, label: '제목'),
                const SizedBox(height: AppSizes.md),
                Text(
                  '내용',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _body,
                  maxLines: 4,
                  style: GoogleFonts.notoSansKr(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '학생들에게 전달할 내용을 입력하세요',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                PbsPrimaryButton(
                  label: '공지 등록',
                  color: AppColors.teacherNavy,
                  loading: _saving,
                  onPressed: _post,
                ),
              ],
            ),
          ),
          const SectionHeader(title: '최근 공지'),
          annsAsync.when(
            loading: () => const PbsCard(child: SizedBox(height: 60)),
            error: (e, _) => PbsCard(child: Text('오류: $e')),
            data: (anns) {
              if (anns.isEmpty) {
                return PbsCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '아직 등록된 공지가 없어요.',
                      style: GoogleFonts.notoSansKr(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }
              return Column(
                children: anns.map((a) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: PbsCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a['title'] as String,
                                  style: GoogleFonts.notoSansKr(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  a['body'] as String,
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('yyyy.MM.dd HH:mm').format(
                                    DateTime.parse(a['created_at'] as String),
                                  ),
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 11,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '삭제',
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 20),
                            color: AppColors.danger,
                            onPressed: () async {
                              await ref
                                  .read(schoolRepositoryProvider)
                                  .deleteAnnouncement(a['id'] as String);
                              ref.invalidate(announcementsProvider);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: AppSizes.xxxl),
        ],
      ),
    );
  }
}
