import 'package:flutter/material.dart';
import 'package:langgry/core/localization/app_text.dart';

class HtmlPreviewPage extends StatelessWidget {
  const HtmlPreviewPage({
    required this.title,
    required this.html,
    super.key,
  });

  final String title;
  final String html;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: AppText('이 플랫폼에서는 HTML 미리보기를 지원하지 않습니다.')),
    );
  }
}
