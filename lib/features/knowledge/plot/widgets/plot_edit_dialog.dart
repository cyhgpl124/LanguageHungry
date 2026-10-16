import 'package:flutter/material.dart';

import 'package:langgry/features/knowledge/models/knowledge_node.dart';

class PlotEditDialog extends StatefulWidget {
  const PlotEditDialog({required this.node, super.key});

  final KnowledgeNode node;

  @override
  State<PlotEditDialog> createState() => _PlotEditDialogState();
}

class _PlotEditDialogState extends State<PlotEditDialog> {
  late final _titleController = TextEditingController(text: widget.node.title);
  late final _contentController =
      TextEditingController(text: widget.node.content);

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 입력해 주세요.')),
      );
      return;
    }
    Navigator.pop(
      context,
      widget.node.copyWith(
        title: title,
        content: content,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('플롯 수정'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '제목',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentController,
                minLines: 6,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: '내용',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('저장'),
        ),
      ],
    );
  }
}
