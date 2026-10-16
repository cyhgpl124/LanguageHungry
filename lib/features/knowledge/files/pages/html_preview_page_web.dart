import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

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
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'html-preview-${const Uuid().v4()}';
    final frame = web.HTMLIFrameElement()
      ..srcdoc = widget.html.toJS
      ..setAttribute('sandbox', 'allow-scripts allow-forms');
    frame.style
      ..border = '0'
      ..width = '100%'
      ..height = '100%';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (_) => frame,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: HtmlElementView(viewType: _viewType),
    );
  }
}
