import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

class WebViewContent extends StatefulWidget {
  const WebViewContent({required this.url, super.key});

  final String url;

  @override
  State<WebViewContent> createState() => _WebViewContentState();
}

class _WebViewContentState extends State<WebViewContent> {
  late final String _viewType;
  late final web.HTMLIFrameElement _frame;

  @override
  void initState() {
    super.initState();
    _viewType = 'app-webview-${const Uuid().v4()}';
    _frame = _createFrame(widget.url);
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (_) => _frame,
    );
  }

  @override
  void didUpdateWidget(covariant WebViewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _frame.src = _embedUrl(widget.url);
    }
  }

  web.HTMLIFrameElement _createFrame(String url) {
    final frame = web.HTMLIFrameElement()
      ..src = _embedUrl(url)
      ..setAttribute(
          'allow',
          'accelerometer; autoplay; clipboard-write; '
              'encrypted-media; gyroscope; picture-in-picture; web-share')
      ..setAttribute('allowfullscreen', '')
      ..setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
    frame.style
      ..border = '0'
      ..width = '100%'
      ..height = '100%';
    return frame;
  }

  String _embedUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    final host = uri.host.toLowerCase();
    final videoId = uri.queryParameters['v'];
    if ((host == 'youtube.com' || host == 'www.youtube.com') &&
        uri.path == '/watch' &&
        videoId != null &&
        videoId.isNotEmpty) {
      return Uri.https('www.youtube-nocookie.com', '/embed/$videoId')
          .toString();
    }
    if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
      return Uri.https(
        'www.youtube-nocookie.com',
        '/embed/${uri.pathSegments.first}',
      ).toString();
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      viewType: _registeredViewType,
    );
  }

  String get _registeredViewType => _viewType;
}
