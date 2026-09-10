import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../data/knowledge_database.dart';
import '../../data/memo_ai_service.dart';
import '../../domain/entities/knowledge_node.dart';
import '../dynamic_list_screen.dart';
import '../plot_mode_screen.dart';

class GlobalMemoFab extends StatelessWidget {
  const GlobalMemoFab({required this.store, super.key});

  final KnowledgeStore store;

  Future<void> _createMemo(BuildContext context) async {
    final controller = TextEditingController();
    String? text;
    try {
      text = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('새 메모'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: '첫 단어는 제목, 나머지는 내용으로 저장됩니다.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('저장'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (text == null || text.trim().isEmpty || !context.mounted) return;

    final words = text.trim().split(RegExp(r'\s+'));
    final now = DateTime.now();
    try {
      final title = words.first;
      final content = words.length == 1 ? '' : words.skip(1).join(' ');
      final analysis = await MemoAiService().analyze(title, content);
      await store.insertNode(
        KnowledgeNode(
          id: const Uuid().v4(),
          type: 'knowledge',
          title: title,
          content: content,
          createdAt: now,
          updatedAt: now,
          tags: analysis.tags,
          embedding: analysis.embedding,
          metadata: const {'mode': 'memo', 'display': '메모'},
        ),
      );
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Firebase 저장 실패 (${error.code}): ${error.message ?? '권한 또는 App Check 설정을 확인해 주세요.'}',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메모 저장 실패: $error')),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메모를 저장했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () async {
        final mode = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.sticky_note_2_rounded),
                  title: const Text('메모 모드'),
                  onTap: () => Navigator.pop(context, 'memo'),
                ),
                ListTile(
                  leading: const Icon(Icons.table_chart_rounded),
                  title: const Text('리스트 모드'),
                  onTap: () => Navigator.pop(context, 'list'),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_graph_rounded),
                  title: const Text('플롯 모드'),
                  onTap: () => Navigator.pop(context, 'plot'),
                ),
              ],
            ),
          ),
        );
        if (!context.mounted) return;
        if (mode == 'memo') {
          await _createMemo(context);
        } else if (mode == 'list') {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DynamicListScreen(store: store)),
          );
        } else if (mode == 'plot') {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PlotModeScreen(store: store)),
          );
        }
      },
      tooltip: '메모 추가',
      child: const Icon(Icons.add_comment_rounded),
    );
  }
}
