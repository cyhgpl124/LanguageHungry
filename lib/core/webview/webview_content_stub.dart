import 'package:flutter/material.dart';
import 'package:langgry/core/localization/app_text.dart';

class WebViewContent extends StatelessWidget {
  const WebViewContent({required this.url, super.key});

  final String url;

  @override
  Widget build(BuildContext context) => const Center(
        child: AppText('이 플랫폼에서는 웹뷰를 사용할 수 없습니다.'),
      );
}
