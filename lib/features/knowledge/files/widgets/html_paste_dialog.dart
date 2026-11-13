import 'package:flutter/material.dart';
import 'package:langgry/core/localization/app_text.dart';

class HtmlPasteInput {
  const HtmlPasteInput({
    required this.title,
    required this.html,
    required this.layoutRepaired,
  });

  final String title;
  final String html;
  final bool layoutRepaired;
}

class HtmlPasteDialog extends StatefulWidget {
  const HtmlPasteDialog({
    required this.recoverHtml,
    super.key,
  });

  final Future<String?> Function(String html) recoverHtml;

  @override
  State<HtmlPasteDialog> createState() => _HtmlPasteDialogState();
}

class _HtmlPasteDialogState extends State<HtmlPasteDialog> {
  final _titleController = TextEditingController();
  final _htmlController = TextEditingController();
  bool _isRecovering = false;
  bool _layoutRepaired = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _htmlController.dispose();
    super.dispose();
  }

  Future<void> _recoverLayout() async {
    if (_htmlController.text.trim().isEmpty) {
      setState(() => _error = 'HTML 내용을 입력해 주세요.');
      return;
    }
    setState(() {
      _isRecovering = true;
      _error = null;
    });
    try {
      final recovered = await widget.recoverHtml(_htmlController.text);
      if (!mounted || recovered == null) return;
      setState(() {
        _htmlController.text = recovered;
        _layoutRepaired = true;
      });
    } on Exception {
      if (mounted) {
        setState(() {
          _error = 'AI가 HTML 화면을 보완하지 못했습니다. 다시 시도해 주세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _isRecovering = false);
    }
  }

  void _save() {
    final title = _titleController.text.trim();
    final html = _htmlController.text.trim();
    if (title.isEmpty || html.isEmpty) {
      setState(() => _error = '파일 제목과 HTML 내용을 입력해 주세요.');
      return;
    }
    Navigator.of(context).pop(
      HtmlPasteInput(
        title: title,
        html: html,
        layoutRepaired: _layoutRepaired,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const AppText('HTML 내용 붙여넣기'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('html-paste-title'),
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: AppText.localize(context, '파일 제목'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('html-paste-content'),
                controller: _htmlController,
                minLines: 8,
                maxLines: 14,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: AppText.localize(context, 'HTML 내용'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const AppText(
                'HTML 내용을 붙여넣으면 AI가 누락된 문서 구조와 화면 구성을 보완합니다. '
                '보완을 위해 내용이 AI 서비스로 전송됩니다.',
              ),
              if (_layoutRepaired) ...[
                const SizedBox(height: 8),
                const AppText('AI가 화면 구성을 보완했습니다. 저장 전에 내용을 확인해 주세요.'),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                AppText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isRecovering ? null : _recoverLayout,
          child: _isRecovering
              ? const AppText('AI 보완 중...')
              : const AppText('AI로 화면 구성 보완'),
        ),
        TextButton(
          onPressed: _isRecovering ? null : () => Navigator.of(context).pop(),
          child: const AppText('취소'),
        ),
        FilledButton(
          onPressed: _isRecovering ? null : _save,
          child: const AppText('파일 저장'),
        ),
      ],
    );
  }
}
