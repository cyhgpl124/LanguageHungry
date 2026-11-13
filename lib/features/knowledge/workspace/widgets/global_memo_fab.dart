import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:langgry/core/localization/app_text.dart';
import 'package:langgry/core/permissions/permission_gate.dart';
import 'package:langgry/core/permissions/permission_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../models/knowledge_node.dart';

import '../../memos/services/memo_mode_assistant.dart';
import '../../services/knowledge_database.dart';
import '../../services/memo_ai_service.dart';
import 'unified_memo_dialog.dart';

class GlobalMemoFab extends StatefulWidget {
  const GlobalMemoFab({required this.store, super.key});

  final KnowledgeStore store;

  @override
  State<GlobalMemoFab> createState() => _GlobalMemoFabState();
}

class _GlobalMemoFabState extends State<GlobalMemoFab> {
  static const _positionXKey = 'globalMemoFab.positionX';
  static const _positionYKey = 'globalMemoFab.positionY';
  static const _fabWidth = 56.0;
  static const _fabHeight = 56.0;

  double _positionX = 1;
  double _positionY = 1;
  double _maxLeft = 0;
  double _maxTop = 0;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _positionX =
          (preferences.getDouble(_positionXKey) ?? 1).clamp(0, 1).toDouble();
      _positionY =
          (preferences.getDouble(_positionYKey) ?? 1).clamp(0, 1).toDouble();
    });
  }

  Future<void> _savePosition() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_positionXKey, _positionX);
    await preferences.setDouble(_positionYKey, _positionY);
  }

  Future<void> _openUnifiedMemoDialog(BuildContext context) async {
    if (!await requireFeatureAccess(
      context,
      PermissionFeatures.globalMemo,
    )) {
      return;
    }
    if (!context.mounted) return;

    final result = await showDialog<UnifiedMemoResult>(
      context: context,
      builder: (_) => const UnifiedMemoDialog(),
    );

    if (result == null || !context.mounted) return;

    final now = DateTime.now();
    try {
      final service = MemoAiService();
      final memoTitle = result.title.isEmpty ? '새 메모' : result.title;
      await widget.store.insertNode(
        KnowledgeNode(
          id: const Uuid().v4(),
          type: 'memo',
          title: memoTitle,
          content: result.content,
          createdAt: now,
          updatedAt: now,
          tags: result.tags,
          embedding: service.embeddingFor('$memoTitle ${result.content}'),
          metadata: {
            'mode': result.mode.key,
            'documentKind': result.mode.key,
            'isDocument': 'true',
            'level': '1',
            'autoGenerateTitle': result.autoGenerateTitle.toString(),
            'autoGenerateTags': result.autoGenerateTags.toString(),
            if (result.mode == AssistantDisplayMode.list) ...{
              'display': '리스트',
              'listProperty': '항목',
              'listValue': result.content,
              'listDelimiter': '\n',
            },
            if (result.mode == AssistantDisplayMode.plot) ...{
              'display': '플롯',
            },
          },
        ),
      );
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
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
          SnackBar(content: AppText('메모 저장 실패: $error')),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('메모를 저장했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxLeft = (constraints.maxWidth - _fabWidth)
            .clamp(0, double.infinity)
            .toDouble();
        _maxTop = (constraints.maxHeight - _fabHeight)
            .clamp(0, double.infinity)
            .toDouble();
        final left = _positionX * _maxLeft;
        final top = _positionY * _maxTop;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: left,
              top: top,
              child: GestureDetector(
                key: const ValueKey('global-memo-fab-position'),
                onPanUpdate: (details) {
                  if (_maxLeft == 0 && _maxTop == 0) return;
                  setState(() {
                    if (_maxLeft > 0) {
                      _positionX =
                          ((left + details.delta.dx) / _maxLeft).clamp(0, 1);
                    }
                    if (_maxTop > 0) {
                      _positionY =
                          ((top + details.delta.dy) / _maxTop).clamp(0, 1);
                    }
                  });
                },
                onPanEnd: (_) => _savePosition(),
                child: FloatingActionButton(
                  key: const ValueKey('global-memo-fab-button'),
                  heroTag: 'global-memo-create-fab',
                  onPressed: () => _openUnifiedMemoDialog(context),
                  tooltip: AppText.localize(context, '메모 및 구성요소 작성'),
                  child: const Icon(Icons.add_comment_rounded),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
