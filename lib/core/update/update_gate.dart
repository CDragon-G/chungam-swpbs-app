import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_colors.dart';
import '../router/root_navigator.dart';
import 'update_service.dart';

/// 최신 버전이 아니면 업데이트 안내 팝업을 띄운다.
///
/// 앱을 켤 때, 그리고 다른 앱에 갔다가 돌아올 때마다 확인한다.
/// 학생들은 앱을 끄지 않고 며칠씩 두기 때문에 켤 때 한 번만 보면
/// 안내를 거의 보지 못한다. '나중에' 를 눌렀으면 30분 동안은 다시 띄우지 않는다.
/// 최소 지원 버전보다 낮으면 닫을 수 없는 팝업으로 업데이트를 요구한다.
///
/// 이 위젯은 MaterialApp.builder 안, 즉 Navigator 보다 위에 있다.
/// 그래서 팝업은 자기 context 가 아니라 [rootNavigatorKey] 의 context 로 띄운다.
/// (예전에는 자기 context 로 띄워서 '새 버전이 나왔어요' 팝업이 한 번도 뜨지 못했다)
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  static const _remindAfter = Duration(minutes: 30);

  DateTime? _lastShown;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 첫 화면(스플래시)이 로그인·홈으로 넘어간 뒤에 띄운다.
    // 바로 띄우면 화면이 바뀌면서 팝업도 함께 닫힌다.
    Future.delayed(const Duration(seconds: 3), _check);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (!mounted || _busy) return;
    _busy = true;
    try {
      final info = await UpdateService.check();
      if (!mounted || !info.updateAvailable) return;
      final last = _lastShown;
      if (!info.force &&
          last != null &&
          DateTime.now().difference(last) < _remindAfter) {
        return;
      }
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      _lastShown = DateTime.now();
      await showUpdateDialog(ctx, info);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 로그인·가입을 하기 전에 버전을 확인한다.
/// 최소 지원 버전보다 낮으면 안내창을 띄우고 `false`를 돌려준다 —
/// 부르는 쪽에서 그대로 중단하면 된다.
///
/// 서버 확인이 실패하면 `true`를 돌려준다. 통신이 잠깐 끊겼다고
/// 학교 전체가 로그인을 못 하게 되는 편이 훨씬 위험하다.
Future<bool> ensureUpToDate(BuildContext context) async {
  final info = await UpdateService.check();
  if (!info.force) return true;
  if (!context.mounted) return false;
  await showUpdateDialog(context, info);
  return false;
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  style: GoogleFonts.notoSansKr(color: AppColors.textTertiary)),
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
