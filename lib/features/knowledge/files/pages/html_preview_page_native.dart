import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class HtmlPreviewPage extends StatefulWidget {
  const HtmlPreviewPage({
    required this.title,
    required this.html,
    super.key,
  });

  final String title;
  final String html;

  @override
  State<HtmlPreviewPage> createState() => _HtmlPreviewPageState();
}

class _HtmlPreviewPageState extends State<HtmlPreviewPage> {
  WebViewController? _controller;
  Future<void>? _loadPage;

  @override
  void initState() {
    super.initState();
    try {
      final controller = WebViewController();
      _controller = controller;
      _loadPage = controller
          .setJavaScriptMode(JavaScriptMode.unrestricted)
          .then((_) => controller.loadHtmlString(widget.html));
    } on AssertionError catch (error) {
      if (!error.toString().contains('WebViewPlatform.instance != null')) {
        rethrow;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _controller == null
          ? Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('이 플랫폼에서는 HTML을 원본 텍스트로 표시합니다.'),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(widget.html),
                  ),
                ),
              ],
            )
          : FutureBuilder<void>(
              future: _loadPage,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('HTML 파일을 표시하지 못했습니다: ${snapshot.error}'),
                    ),
                  );
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return WebViewWidget(controller: _controller!);
              },
            ),
    );
  }
}
