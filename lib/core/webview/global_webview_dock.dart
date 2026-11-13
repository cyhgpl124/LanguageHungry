import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:langgry/core/localization/app_text.dart';
import 'package:langgry/core/permissions/permission_gate.dart';
import 'package:langgry/core/permissions/permission_policy.dart';
import 'webview_content.dart';

class GlobalWebViewDock extends StatefulWidget {
  const GlobalWebViewDock({super.key});

  @override
  State<GlobalWebViewDock> createState() => _GlobalWebViewDockState();
}

class _GlobalWebViewDockState extends State<GlobalWebViewDock> {
  static const _handleHeight = 16.0;
  static const _toolbarHeight = 44.0;
  static const _webViewMinimumHeight = 200.0;
  static const _minimumHeight =
      _handleHeight + _toolbarHeight + _webViewMinimumHeight + 1;

  final _address = TextEditingController(text: 'https://www.youtube.com');
  double _height = 0;
  double _dragStartHeight = 0;
  double _dragDelta = 0;
  String _url = 'https://www.youtube.com';

  bool get _isOpen => _height > 0;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (!await requireFeatureAccess(context, PermissionFeatures.webView)) {
      return;
    }
    if (!mounted) return;
    setState(() => _height = _minimumHeight);
  }

  void _dragStarted(DragStartDetails details) {
    _dragStartHeight = _height;
    _dragDelta = 0;
  }

  void _dragUpdated(DragUpdateDetails details, double maxHeight) {
    _dragDelta += details.delta.dy;
    if (_dragStartHeight == 0) return;
    setState(() {
      _height = (_dragStartHeight - _dragDelta)
          .clamp(_handleHeight, maxHeight)
          .toDouble();
    });
  }

  Future<void> _dragEnded(DragEndDetails details) async {
    if (_dragStartHeight == 0) {
      if (_dragDelta < -24 || details.velocity.pixelsPerSecond.dy < -200) {
        await _open();
      }
      return;
    }

    final downward =
        _dragDelta > 0 || details.velocity.pixelsPerSecond.dy > 200;
    if (!downward) return;
    if (_dragStartHeight > _minimumHeight + 1) {
      setState(() => _height = _minimumHeight);
      return;
    }
    if (_dragDelta > 32 || details.velocity.pixelsPerSecond.dy > 450) {
      setState(() => _height = 0);
    } else {
      setState(() => _height = _minimumHeight);
    }
  }

  Future<void> _navigate() async {
    if (!await requireFeatureAccess(context, PermissionFeatures.webView)) {
      return;
    }
    if (!mounted) return;
    final value = _address.text.trim();
    final normalized = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(normalized);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('http 또는 https 주소를 입력해 주세요.')),
      );
      return;
    }
    setState(() => _url = uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = math.max(
      _minimumHeight,
      screenHeight - MediaQuery.paddingOf(context).top - 80,
    );
    if (!_isOpen) {
      return GestureDetector(
        key: const Key('webview-hidden-handle'),
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        onVerticalDragStart: _dragStarted,
        onVerticalDragUpdate: (details) => _dragUpdated(details, maxHeight),
        onVerticalDragEnd: _dragEnded,
        child: SizedBox(
          height: 10,
          child: Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: _height.clamp(_minimumHeight, maxHeight).toDouble(),
      child: Material(
        key: const Key('webview-panel'),
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            GestureDetector(
              key: const Key('webview-drag-handle'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: _dragStarted,
              onVerticalDragUpdate: (details) =>
                  _dragUpdated(details, maxHeight),
              onVerticalDragEnd: _dragEnded,
              child: SizedBox(
                height: _handleHeight,
                child: Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: _toolbarHeight,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _address,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _navigate(),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: AppText.localize(context, '웹 주소 입력'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _navigate,
                    tooltip: AppText.localize(context, '웹페이지 이동'),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: WebViewContent(
                key: ValueKey(_url),
                url: _url,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
