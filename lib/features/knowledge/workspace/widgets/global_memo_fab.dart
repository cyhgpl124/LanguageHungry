import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../services/knowledge_database.dart';
import '../../services/memo_ai_service.dart';
import '../../models/directed_edge.dart';
import '../../models/knowledge_node.dart';
import '../../list/pages/dynamic_list_screen.dart';
import '../../plot/pages/plot_mode_screen.dart';

class GlobalMemoFab extends StatelessWidget {
  const GlobalMemoFab({required this.store, super.key});

  final KnowledgeStore store;

  Future<void> _createMemo(BuildContext context) async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    _MemoDraft? draft;
    try {
      draft = await showDialog<_MemoDraft>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('새 메모'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  maxLength: 10,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    hintText: '10자 이내',
                  ),
                ),
                TextField(
                  controller: contentController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: '1단계 메모 본문',
                    hintText: '여러 주제는 문단을 나누어 작성하세요. #태그도 입력할 수 있습니다.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                final content = contentController.text.trim();
                if (title.isEmpty || content.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('제목과 메모 본문을 입력해 주세요.')),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(
                  _MemoDraft(title: title, content: content),
                );
              },
              child: const Text('저장'),
            ),
          ],
        ),
      );
    } finally {
      titleController.dispose();
      contentController.dispose();
    }
    if (draft == null || !context.mounted) return;

    final now = DateTime.now();
    try {
      final service = MemoAiService();
      final analysis = await service.analyze(draft.title, draft.content);
      final manualTags = RegExp(r'#([^\s#]+)')
          .allMatches(draft.content)
          .map((match) => match.group(1)!)
          .map((tag) => tag.replaceAll(RegExp(r'[.,!?;:)\]}]+$'), '').trim())
          .where((tag) => tag.isNotEmpty);
      final tags = <String>{...analysis.tags, ...manualTags}.toList();
      final topics = analysis.topics;

      KnowledgeNode createNode({
        required String title,
        required String content,
        required int level,
        String? parentId,
      }) {
        final memoTitle = _titleLimit(title);
        return KnowledgeNode(
          id: const Uuid().v4(),
          type: 'memo',
          title: memoTitle.isEmpty ? '새 메모' : memoTitle,
          content: content,
          createdAt: now,
          updatedAt: now,
          tags: tags,
          embedding: service.embeddingFor('$memoTitle $content'),
          metadata: {
            'mode': 'memo',
            'display': '메모',
            'language': analysis.language,
            'level': '$level',
            'generated': 'true',
            if (parentId != null) 'parentId': parentId,
          },
        );
      }

      Future<void> saveChild(KnowledgeNode parent, KnowledgeNode child) async {
        await store.insertNode(child);
        await store.upsertEdge(
          DirectedEdge(
            id: const Uuid().v4(),
            fromId: parent.id,
            toId: child.id,
            relation: '포함관계',
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      if (topics.length <= 2) {
        await store.insertNode(createNode(
          title: draft.title,
          content: draft.content,
          level: 1,
        ));
      } else if (topics.length <= 5) {
        final root = createNode(
          title: draft.title,
          content: _topicSummary(topics),
          level: 1,
        );
        await store.insertNode(root);
        for (final topic in topics) {
          await saveChild(
              root,
              createNode(
                title: topic.title,
                content: topic.content,
                level: 2,
                parentId: root.id,
              ));
        }
      } else if (topics.length <= 8) {
        for (final group in _partition(topics, 2)) {
          final parent = createNode(
            title: group.map((topic) => topic.title).join(' · '),
            content: _topicSummary(group),
            level: 1,
          );
          await store.insertNode(parent);
          for (final topic in group) {
            await saveChild(
                parent,
                createNode(
                  title: topic.title,
                  content: topic.content,
                  level: 2,
                  parentId: parent.id,
                ));
          }
        }
      } else if (topics.length <= 11) {
        final root = createNode(
          title: draft.title,
          content: _topicSummary(topics),
          level: 1,
        );
        await store.insertNode(root);
        for (final group in _partition(topics, 3)) {
          final parent = createNode(
            title: group.map((topic) => topic.title).join(' · '),
            content: _topicSummary(group),
            level: 2,
            parentId: root.id,
          );
          await saveChild(root, parent);
          for (final topic in group) {
            await saveChild(
                parent,
                createNode(
                  title: topic.title,
                  content: topic.content,
                  level: 3,
                  parentId: parent.id,
                ));
          }
        }
      } else {
        final root = createNode(
          title: draft.title,
          content: _topicSummary(topics),
          level: 1,
        );
        await store.insertNode(root);

        Future<void> addBranches(
          KnowledgeNode parent,
          List<MemoTopic> branchTopics,
          int childLevel,
        ) async {
          if (branchTopics.length <= 3) {
            for (final topic in branchTopics) {
              await saveChild(
                  parent,
                  createNode(
                    title: topic.title,
                    content: topic.content,
                    level: childLevel,
                    parentId: parent.id,
                  ));
            }
            return;
          }
          for (final group in _partition(branchTopics, 3)) {
            final child = createNode(
              title: group.map((topic) => topic.title).join(' · '),
              content: _topicSummary(group),
              level: childLevel,
              parentId: parent.id,
            );
            await saveChild(parent, child);
            await addBranches(child, group, childLevel + 1);
          }
        }

        await addBranches(root, topics, 2);
      }
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
        const SnackBar(content: Text('메모와 주제별 단계 메모를 저장했습니다.')),
      );
    }
  }

  List<List<MemoTopic>> _partition(List<MemoTopic> topics, int count) {
    final result = <List<MemoTopic>>[];
    final baseSize = topics.length ~/ count;
    final extra = topics.length % count;
    var offset = 0;
    for (var index = 0; index < count; index++) {
      final size = baseSize + (index < extra ? 1 : 0);
      result.add(topics.skip(offset).take(size).toList());
      offset += size;
    }
    return result.where((group) => group.isNotEmpty).toList();
  }

  String _topicSummary(List<MemoTopic> topics) =>
      topics.map((topic) => '${topic.title}: ${topic.summary}').join('\n');

  String _titleLimit(String value) =>
      String.fromCharCodes(value.runes.take(10)).trim();

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

class _MemoDraft {
  const _MemoDraft({required this.title, required this.content});

  final String title;
  final String content;
}
