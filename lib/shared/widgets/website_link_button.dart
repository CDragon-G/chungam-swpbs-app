import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';

/// 🌐 자람 웹사이트로 이동하는 작은 링크 버튼.
/// 가입 중 학교 코드가 없는 선생님이 도입 안내·요금제를 볼 수 있게 한다.
class WebsiteLinkButton extends StatelessWidget {
  const WebsiteLinkButton({
    super.key,
    this.label = '아직 자람을 안 쓰는 학교인가요? 도입 안내 · 요금 보기',
    this.path = '/#price',
  });

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => launchUrl(
          Uri.parse('https://jaramedu.kr$path'),
          mode: LaunchMode.externalApplication,
        ),
        icon: const Icon(Icons.open_in_new_rounded,
            size: 14, color: AppColors.primary),
        label: Text(
          label,
          style: GoogleFonts.notoSansKr(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
