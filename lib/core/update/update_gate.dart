import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_colors.dart';
import 'update_service.dart';

/// 앱을 켤 때 한 번, 최신 버전이 아니면 안내 팝업을 띄운다.
/// 최소 지원 버전보다 낮으면 닫을 수 없는 팝업으로 업데이트를 요구한다.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_checked) return;
    _checked = true;
    final info = await UpdateService.check();
    if (!mounted || !info.updateAvailable) return;
    // '나중에' 를 누른 뒤 같은 실행 중에 또 뜨지 않도록 한 번만 띄운다.
    await showUpdateDialog(context, info);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 업데이트 안내 팝업. force면 닫을 수 없다.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !info.force,
    builder: (dialogCtx) => PopScope(
      canPop: !info.force,
      child: AlertDialog(
        title: Row(
          children: [
            const Text('🌱', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                info.force ? '업데이트가 필요해요' : '새 버전이 나왔어요',
                style: GoogleFonts.notoSansKr(
                    fontWeight: FontWeight.w900, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.force
                  ? '지금 버전으로는 자람을 계속 쓸 수 없어요.\n'
                      '스토어에서 업데이트한 뒤 다시 열어주세요.'
                  : '자람이 새로워졌어요.\n'
                      '스토어에서 업데이트하면 바뀐 기능을 바로 쓰실 수 있어요.',
              style: GoogleFonts.notoSansKr(fontSize: 13.5, height: 1.6),
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text('지금 ${info.current}',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 12, color: AppColors.textTertiary)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 14, color: AppColors.textTertiary),
                  const SizedBox(width: 8),
                  Text('최신 ${info.latest}',
                      style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppColors.studentGreen)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!info.force)
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('나중에',
                  style: GoogleFonts.notoSansKr(
                      color: AppColors.textTertiary)),
            ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.studentGreen),
            onPressed: () async {
              final uri = Uri.tryParse(info.storeUrl);
              if (uri == null) return;
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              // 강제 업데이트면 스토어에서 돌아와도 팝업을 유지한다.
              if (!info.force && dialogCtx.mounted) Navigator.pop(dialogCtx);
            },
            child: Text('업데이트하기',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ),
  );
}
