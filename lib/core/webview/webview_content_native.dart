import 'package:flutter/material.dart';
import 'package:langgry/core/localization/app_text.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewContent extends StatefulWidget {
  const WebViewContent({required this.url, super.key});

  final String url;

  @override
  State<WebViewContent> createState() => _WebViewContentState();
}

class _WebViewContentState extends State<WebViewContent> {
  WebViewController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _createController(widget.url);
  }

  @override
  void didUpdateWidget(covariant WebViewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _load(widget.url);
    }
  }

  void _createController(String url) {
    try {
      final controller = WebViewController();
      _controller = controller;
      controller
          .setJavaScriptMode(JavaScriptMode.unrestricted)
          .then((_) => _load(url), onError: (Object error, StackTrace stack) {
        if (mounted) setState(() => _error = '페이지를 불러오지 못했습니다.');
      });
    } on AssertionError catch (error) {
      if (!error.toString().contains('WebViewPlatform.instance != null')) {
        rethrow;
      }
      _error = '이 플랫폼에서는 웹뷰를 사용할 수 없습니다.';
    }
  }

  Future<void> _load(String url) async {
    final controller = _controller;
    if (controller == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      if (mounted) setState(() => _error = 'http 또는 https 주소를 입력해 주세요.');
      return;
    }
    try {
      await controller.loadRequest(uri);
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = '페이지를 불러오지 못했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AppText(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: controller);
  }
}
