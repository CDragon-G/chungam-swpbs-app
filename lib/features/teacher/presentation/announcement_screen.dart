import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/error_messages.dart';
import '../../../shared/providers/profile_provider.dart';
import '../../../shared/widgets/pbs_card.dart';
import '../../growth/growth_celebration.dart';
import '../../notice/school_event.dart';
import '../../points/providers/points_provider.dart';
import '../../school/data/school_repository.dart';
import '../../school/providers/school_provider.dart';

/// 📢 공지 — 일반 공지와 이벤트 공지(홈 배너 · 팝업으로 홍보).
class AnnouncementScreen extends ConsumerStatefulWidget {
  const AnnouncementScreen({super.key});

  @override
  ConsumerState<AnnouncementScreen> createState() => _State();
}

class _State extends ConsumerState<AnnouncementScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _saving = false;

  // ── 이벤트 옵션 ──
  bool _isEvent = false;
  EventTheme _theme = EventTheme.warm;
  DateTime? _start;
  DateTime? _end;
  String? _itemId;
  Uint8List? _image;
  String _imageExt = 'jpg';

  @override
  void initState() {
    super.initState();
    // 미리보기 배너가 제목을 따라 바뀌게
    _title.addListener(() {
      if (_isEvent) setState(() {});
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickImage() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1440,
        maxHeight: 1800,
        imageQuality: 85,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.lengthInBytes > 3 * 1024 * 1024) {
        _snack('이미지가 너무 커요 (3MB 이하로 골라주세요)');
        return;
      }
      final name = x.name.toLowerCase();
      setState(() {
        _image = bytes;
        _imageExt = name.endsWith('.png')
            ? 'png'
            : name.endsWith('.webp')
                ? 'webp'
                : 'jpg';
      });
    } catch (e) {
      _snack('이미지를 불러오지 못했어요: ${translateError(e)}');
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final today = KstDate.today();
    final init = (start ? _start : _end) ?? _start ?? today;
    final d = await showDatePicker(
      context: context,
      initialDate: init.isBefore(today) ? today : init,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      locale: const Locale('ko'),
      helpText: start ? '이벤트 시작일' : '이벤트 마지막 날',
    );
    if (d == null) return;
    setState(() {
      if (start) {
        _start = d;
        if (_end != null && _end!.isBefore(d)) _end = d;
      } else {
        _end = d;
        if (_start != null && _start!.isAfter(d)) _start = d;
      }
    });
  }

  /// '따뜻한 등굣길' 예시로 채우기 — 날짜와 강화물은 선생님이 고른다.
  void _fillWarmExample() {
    setState(() {
      _isEvent = true;
      _theme = EventTheme.warm;
      _title.text = '🍢 따뜻한 등굣길 캠페인';
      _body.text = '추운 아침, 등굣길에서 따뜻한 어묵을 나눠요!\n'
          '교환소에서 자람 포인트로 어묵을 신청하고, 아침 등교 시간에 정문에서 받아 가세요.\n\n'
          '· 받는 곳: 정문 앞\n'
          '· 받는 때: 등교 시간\n'
          '· 신청: 교환소 → 따뜻한 어묵';
    });
  }

  Future<void> _post() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _snack('제목과 내용을 모두 써주세요');
      return;
    }
    if (_isEvent && _end == null) {
      _snack('이벤트 마지막 날을 골라주세요 — 그날이 지나면 배너가 내려가요');
      return;
    }
    final profile = ref.read(profileProvider).value;
    if (profile?.schoolId == null) return;
    final repo = ref.read(schoolRepositoryProvider);
    setState(() => _saving = true);
    try {
      NoticeEventOptions? event;
      if (_isEvent) {
        String? url;
        if (_image != null) {
          url = await repo.uploadNoticeImage(
            schoolId: profile!.schoolId!,
            bytes: _image!,
            ext: _imageExt,
          );
        }
        event = NoticeEventOptions(
          start: _start,
          end: _end,
          theme: _theme.key,
          imageUrl: url,
          itemId: _itemId,
        );
      }
      await repo.postAnnouncement(
        schoolId: profile!.schoolId!,
        title: title,
        body: body,
        event: event,
      );
      _title.clear();
      _body.clear();
      setState(() {
        _isEvent = false;
        _image = null;
        _start = null;
        _end = null;
        _itemId = null;
      });
      ref.invalidate(announcementsProvider);
      if (mounted) {
        celebrateGrowth(context, ref,
            headline: event != null ? '이벤트를 홈에 띄웠어요 📣' : '공지를 등록했어요 📢');
      }
    } catch (e) {
      _snack('실패: ${translateError(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final annsAsync = ref.watch(announcementsProvider);
    final isAdmin = ref.watch(profileProvider).value?.isAdminTeacher ?? false;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '공지 · 이벤트',
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
          if (isAdmin) _composer(),
          const SectionHeader(title: '최근 공지'),
          annsAsync.when(
            loading: () => const PbsCard(child: SizedBox(height: 60)),
            error: (e, _) => PbsCard(child: Text('오류: ${translateError(e)}')),
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
                children: [
                  for (final a in anns) _NoticeRow(row: a, canDelete: isAdmin),
                ],
              );
            },
          ),
          const SizedBox(height: AppSizes.xxxl),
        ],
      ),
    );
  }

  // ═══════════ 작성 카드 ═══════════

  Widget _composer() {
    return PbsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '새 공지 작성',
                  maxLines: 1,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: _fillWarmExample,
                child: Text('🍢 예시 채우기',
                    maxLines: 1,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          PbsTextField(controller: _title, label: '제목'),
          const SizedBox(height: 5),
          Text(
            '👀 제목은 학생들 홈 화면 배너에 가장 먼저 보여요 — 한눈에 들어오게 써주세요!',
            style: GoogleFonts.notoSansKr(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
              height: 1.4,
            ),
          ),
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
            maxLines: 5,
            style: GoogleFonts.notoSansKr(fontSize: 14),
            decoration: InputDecoration(
              hintText: '학생들에게 전달할 내용을 입력하세요',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: AppSizes.md),

          // ── 이벤트로 홍보하기 ──
          Container(
            decoration: BoxDecoration(
              color: _isEvent ? const Color(0xFFFFF7ED) : AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              border: Border.all(
                  color: _isEvent ? const Color(0xFFFDBA74) : AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  value: _isEvent,
                  onChanged: (v) => setState(() => _isEvent = v),
                  title: Text('📣 이벤트로 홈에 홍보하기',
                      maxLines: 1,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  subtitle: Text('배너 · 하루 한 번 팝업 · 포스터 이미지',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 11.5, color: AppColors.textSecondary)),
                ),
                if (_isEvent) _eventOptions(),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          PbsPrimaryButton(
            label: _isEvent ? '이벤트 올리기' : '공지 등록',
            color: _isEvent ? const Color(0xFFE8452C) : AppColors.teacherNavy,
            loading: _saving,
            onPressed: _post,
          ),
        ],
      ),
    );
  }

  Widget _eventOptions() {
    final items = (ref.watch(allStoreItemsProvider).value ?? const [])
        .where((i) => i.isActive && !i.isClassItem && !i.isClosed)
        .toList();
    final f = DateFormat('M월 d일(E)', 'ko');
    final title = _title.text.trim().isEmpty ? '이벤트 제목' : _title.text.trim();
    final preview = SchoolEvent(
      id: 'preview',
      title: title,
      body: _body.text,
      createdAt: DateTime.now(),
      start: _start,
      end: _end,
      theme: _theme,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 미리보기
          _label('홈 배너 미리보기'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF9BD27A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: EventBanner(event: preview, onTap: () {}),
          ),
          const SizedBox(height: 12),

          // 색
          _label('배너 색'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in EventTheme.all)
                ChoiceChip(
                  selected: _theme == t,
                  onSelected: (_) => setState(() => _theme = t),
                  avatar: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                        gradient: t.gradient, shape: BoxShape.circle),
                  ),
                  label: Text('${t.emoji} ${t.label}',
                      maxLines: 1,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 기간
          _label('기간 — 마지막 날이 지나면 배너가 저절로 내려가요'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(start: true),
                  child: Text(
                    _start == null ? '시작일 (선택)' : f.format(_start!),
                    maxLines: 1,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('~'),
              ),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(start: false),
                  child: Text(
                    _end == null ? '마지막 날' : f.format(_end!),
                    maxLines: 1,
                    style: GoogleFonts.notoSansKr(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '시작일을 정하면 그 전까지 배너에 D-day 가 붙어요. 지금 올려 두면 미리 알릴 수 있어요.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11, height: 1.45, color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(height: 12),

          // 포스터
          _label('포스터 이미지 (선택)'),
          if (_image == null)
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text('사진 보관함에서 고르기',
                  maxLines: 1,
                  style: GoogleFonts.notoSansKr(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            )
          else
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_image!,
                      height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.5)),
                    onPressed: () => setState(() => _image = null),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '이미지가 없으면 고른 색으로 포스터를 만들어 보여줘요. 학생 얼굴이 나온 사진은 피해 주세요.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11, height: 1.45, color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(height: 12),

          // 연결 강화물
          _label('교환소 강화물 연결 (선택)'),
          DropdownButtonFormField<String?>(
            initialValue: items.any((i) => i.id == _itemId) ? _itemId : null,
            isExpanded: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text('연결 안 함',
                    maxLines: 1, style: GoogleFonts.notoSansKr(fontSize: 13.5)),
              ),
              for (final i in items)
                DropdownMenuItem<String?>(
                  value: i.id,
                  child: Text('${i.emoji} ${i.name} · ${i.costPoints}P',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(fontSize: 13.5)),
                ),
            ],
            onChanged: (v) => setState(() => _itemId = v),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              items.isEmpty
                  ? '먼저 교환소에 강화물(예: 따뜻한 어묵)을 등록하면 여기서 고를 수 있어요.'
                  : '연결하면 팝업에 \'교환소에서 신청하기\' 버튼이 생겨요.',
              style: GoogleFonts.notoSansKr(
                  fontSize: 11, height: 1.45, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansKr(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary)),
      );
}

/// 최근 공지 한 줄. 이벤트면 색 띠 · D-day · 포스터 썸네일, 누르면 학생이 보는 팝업 미리보기.
class _NoticeRow extends ConsumerWidget {
  const _NoticeRow({required this.row, required this.canDelete});
  final Map<String, dynamic> row;
  final bool canDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ev = SchoolEvent.fromNotice(row);
    final created = DateTime.tryParse('${row['created_at']}')?.toLocal();
    final status = ev == null
        ? null
        : ev.isActive
            ? (ev.dDay ?? '홍보 중')
            : '끝남';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: ev == null
            ? null
            : () => showEventSheet(context, ev, isTeacher: true),
        child: PbsCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ev != null)
                Container(
                  width: 52,
                  height: 52,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    gradient: ev.theme.gradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: ev.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: ev.imageUrl!,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                        )
                      : Text(ev.emoji, style: const TextStyle(fontSize: 24)),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ev != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                gradient:
                                    ev.isActive ? ev.theme.gradient : null,
                                color: ev.isActive ? null : AppColors.border,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text('이벤트 · $status',
                                  maxLines: 1,
                                  style: GoogleFonts.notoSansKr(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      color: ev.isActive
                                          ? Colors.white
                                          : AppColors.textSecondary)),
                            ),
                            if (ev.periodText != null) ...[
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(ev.periodText!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.notoSansKr(
                                        fontSize: 11,
                                        color: AppColors.textTertiary)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    Text(
                      row['title'] as String,
                      style:
                          GoogleFonts.notoSansKr(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row['body'] as String,
                      maxLines: ev == null ? null : 2,
                      overflow: ev == null ? null : TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (created != null)
                      Text(
                        DateFormat('yyyy.MM.dd HH:mm').format(created),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              if (canDelete)
                IconButton(
                  tooltip: '삭제',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: AppColors.danger,
                  onPressed: () async {
                    await ref.read(schoolRepositoryProvider).deleteAnnouncement(
                          row['id'] as String,
                          imageUrl: ev?.imageUrl,
                        );
                    ref.invalidate(announcementsProvider);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
