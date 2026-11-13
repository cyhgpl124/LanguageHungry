import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:langgry/core/localization/app_text.dart';
import 'package:langgry/core/permissions/permission_gate.dart';
import 'package:langgry/core/permissions/permission_policy.dart';
import 'package:langgry/features/knowledge/memos/services/memo_canvas_service.dart';
import 'package:langgry/features/knowledge/memos/services/memo_mode_assistant.dart';
import 'package:langgry/features/knowledge/models/knowledge_node.dart';
import 'package:langgry/features/knowledge/services/knowledge_store.dart';
import 'package:langgry/features/knowledge/workspace/widgets/unified_memo_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _MemoViewMode { grid, list }

enum _MemoSearchMode { all, tags, title, content }

enum _MemoSortMode { newest, tags, kind, newestAndKind }

class MemoCanvasWorkspaceScreen extends StatefulWidget {
  const MemoCanvasWorkspaceScreen({
    required this.store,
    this.initialKind = MemoDocumentKind.memo,
    this.initialComponentKind,
    this.openCreateDialog = false,
    super.key,
  });

  final KnowledgeStore store;
  final MemoDocumentKind initialKind;
  final MemoComponentKind? initialComponentKind;
  final bool openCreateDialog;

  @override
  State<MemoCanvasWorkspaceScreen> createState() =>
      _MemoCanvasWorkspaceScreenState();
}

class _MemoCanvasWorkspaceScreenState extends State<MemoCanvasWorkspaceScreen> {
  late final MemoCanvasService _service = MemoCanvasService(widget.store);
  List<KnowledgeNode> _documents = const [];
  List<KnowledgeNode> _allNodes = const [];
  KnowledgeNode? _selectedDocument;
  List<KnowledgeNode> _components = const [];
  String _query = '';
  _MemoSearchMode _searchMode = _MemoSearchMode.all;
  String _leftSplitQuery = '';
  String _rightSplitQuery = '';
  _MemoSearchMode _leftSplitSearchMode = _MemoSearchMode.all;
  _MemoSearchMode _rightSplitSearchMode = _MemoSearchMode.all;
  String? _leftSplitDocumentId;
  String? _rightSplitDocumentId;
  _MemoSortMode _sortMode = _MemoSortMode.newest;
  _MemoViewMode _viewMode = _MemoViewMode.grid;
  bool _splitMode = false;
  bool _outlineVisible = true;
  bool _loading = true;
  bool _busy = false;
  bool _initialActionStarted = false;
  String? _error;
  final _componentKeys = <String, GlobalKey>{};

  StreamSubscription<void>? _changesSubscription;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
    _changesSubscription = widget.store.changes.listen((_) {
      if (mounted) _loadDocuments();
    });
  }

  @override
  void dispose() {
    _changesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    try {
      final documents = await _service.loadDocuments();
      final allNodes = await widget.store.listNodes();
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _allNodes = allNodes;
        _selectedDocument = documents
            .where((document) => document.id == _selectedDocument?.id)
            .firstOrNull;
        if (!documents.any((document) => document.id == _leftSplitDocumentId)) {
          _leftSplitDocumentId = null;
        }
        if (!documents
                .any((document) => document.id == _rightSplitDocumentId) ||
            _rightSplitDocumentId == _leftSplitDocumentId) {
          _rightSplitDocumentId = null;
        }
        _loading = false;
        _error = null;
      });
      if (!_initialActionStarted &&
          (widget.initialComponentKind != null || widget.openCreateDialog)) {
        _initialActionStarted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (widget.initialComponentKind case final kind?) {
            _createInitialComponent(kind);
          } else {
            _createDocument();
          }
        });
      }
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message ?? error.code;
        _loading = false;
      });
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _openDocument(KnowledgeNode document) async {
    setState(() {
      _selectedDocument = document;
      _busy = true;
    });
    try {
      var components = await _service.loadComponents(document.id);
      if (components.isEmpty) {
        final outline = await _service.createComponent(
          document: document,
          kind: MemoComponentKind.outline,
          title: '개요',
          content: document.title,
          order: 0,
          source: 'migration',
        );
        components = [outline];
        final docModeKey = document.metadata['mode'] ??
            document.metadata['componentKind'] ??
            document.metadata['documentKind'];
        final compKind = switch (docModeKey) {
          'table' => MemoComponentKind.table,
          'graph' => MemoComponentKind.graph,
          'mindMap' => MemoComponentKind.mindMap,
          'image' => MemoComponentKind.image,
          'outline' => MemoComponentKind.outline,
          _ => MemoComponentKind.text,
        };
        components.add(
          await _service.createComponent(
            document: document,
            kind: compKind,
            title: document.title,
            content: document.content,
            order: 1,
            source: 'migration',
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _components = components;
        _componentKeys
          ..clear()
          ..addEntries(components.map((component) => MapEntry(
                component.id,
                GlobalKey(),
              )));
      });
      await _incrementUsage(document);
    } on FirebaseException catch (error) {
      if (mounted) _showError(error.message ?? error.code);
    } on StateError catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _incrementUsage(KnowledgeNode document) async {
    final usage = int.tryParse(document.metadata['usageCount'] ?? '') ?? 0;
    final updated = document.copyWith(
      updatedAt: DateTime.now(),
      metadata: {...document.metadata, 'usageCount': '${usage + 1}'},
    );
    await widget.store.upsertNode(updated);
    if (mounted) {
      setState(() {
        _documents = _documents
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
        _selectedDocument = updated;
      });
    }
  }

  Future<void> _createDocument() async {
    final result = await showDialog<UnifiedMemoResult>(
      context: context,
      builder: (_) => const UnifiedMemoDialog(
        dialogTitle: '새 문서 작성',
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final title =
          result.title.trim().isEmpty ? '새 문서' : result.title.trim();
      final kind = switch (result.mode) {
        AssistantDisplayMode.table => MemoComponentKind.table,
        AssistantDisplayMode.graph => MemoComponentKind.graph,
        AssistantDisplayMode.mindMap => MemoComponentKind.mindMap,
        AssistantDisplayMode.image => MemoComponentKind.image,
        AssistantDisplayMode.outline => MemoComponentKind.outline,
        _ => MemoComponentKind.text,
      };
      final document = await _service.createDocument(
        title: title,
        content: '',
        kind: MemoDocumentKind.memo,
        options: const MemoCanvasAiOptions(),
        outlineContent:
            kind == MemoComponentKind.outline ? result.content : null,
      );
      if (kind != MemoComponentKind.outline && result.content.isNotEmpty) {
        await _service.createComponent(
          document: document,
          kind: kind,
          title: title,
          content: result.content,
          order: 1,
          parentId: result.parentId,
        );
      }
      if (result.tags.isNotEmpty) {
        await widget.store.upsertNode(
          document.copyWith(
            tags: result.tags,
            updatedAt: DateTime.now(),
          ),
        );
      }
      await _loadDocuments();
      await _openDocument(document);
    } on FirebaseException catch (error) {
      _showError(error.message ?? error.code);
    } on StateError catch (error) {
      _showError(error.message);
    } on FormatException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createInitialComponent(MemoComponentKind kind) async {
    final initialMode = switch (kind) {
      MemoComponentKind.table => AssistantDisplayMode.table,
      MemoComponentKind.graph => AssistantDisplayMode.graph,
      MemoComponentKind.mindMap => AssistantDisplayMode.mindMap,
      MemoComponentKind.image => AssistantDisplayMode.image,
      MemoComponentKind.outline => AssistantDisplayMode.outline,
      _ => AssistantDisplayMode.memo,
    };
    final result = await showDialog<UnifiedMemoResult>(
      context: context,
      builder: (_) => UnifiedMemoDialog(
        dialogTitle: '구성요소 추가',
        initialMode: initialMode,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final title =
          result.title.trim().isEmpty ? kind.label : result.title.trim();
      final document = await _service.createDocument(
        title: title,
        content: '',
        kind: MemoDocumentKind.memo,
        options: const MemoCanvasAiOptions(),
        outlineContent:
            kind == MemoComponentKind.outline ? result.content : null,
      );
      if (kind != MemoComponentKind.outline) {
        final compKind = switch (result.mode) {
          AssistantDisplayMode.table => MemoComponentKind.table,
          AssistantDisplayMode.graph => MemoComponentKind.graph,
          AssistantDisplayMode.mindMap => MemoComponentKind.mindMap,
          AssistantDisplayMode.image => MemoComponentKind.image,
          AssistantDisplayMode.outline => MemoComponentKind.outline,
          _ => MemoComponentKind.text,
        };
        await _service.createComponent(
          document: document,
          kind: compKind,
          title: title,
          content: result.content,
          order: 1,
          parentId: result.parentId,
        );
      }
      await _loadDocuments();
      await _openDocument(document);
    } on FirebaseException catch (error) {
      _showError(error.message ?? error.code);
    } on StateError catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addComponent({
    KnowledgeNode? before,
    KnowledgeNode? after,
  }) async {
    final document = _selectedDocument;
    if (document == null) return;
    final currentComponents = await _service.loadComponents(document.id);
    if (!mounted) return;
    final result = await showDialog<UnifiedMemoResult>(
      context: context,
      builder: (_) => UnifiedMemoDialog(
        dialogTitle: '구성요소 추가',
        parentComponents: currentComponents,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final components = await _service.loadComponents(document.id);
      final kind = switch (result.mode) {
        AssistantDisplayMode.table => MemoComponentKind.table,
        AssistantDisplayMode.graph => MemoComponentKind.graph,
        AssistantDisplayMode.mindMap => MemoComponentKind.mindMap,
        AssistantDisplayMode.image => MemoComponentKind.image,
        AssistantDisplayMode.outline => MemoComponentKind.outline,
        _ => MemoComponentKind.text,
      };
      var order = components.length;
      if (before != null) {
        final index = components.indexWhere((item) => item.id == before.id);
        if (index >= 0) order = index;
      } else if (after != null) {
        final index = components.indexWhere((item) => item.id == after.id);
        if (index >= 0) order = index + 1;
      }
      final component = await _service.createComponent(
        document: document,
        kind: kind,
        title: result.title,
        content: result.content,
        order: order,
        parentId: result.parentId,
      );
      await widget.store.upsertNode(
        component.copyWith(
          tags: result.tags,
          updatedAt: DateTime.now(),
          metadata: {
            ...component.metadata,
            'mode': result.mode.key,
            'componentKind': kind.key,
            'documentKind': result.mode.key,
            'display': result.mode.label,
          },
        ),
      );
      if (before != null || after != null) {
        await _reorderComponents(component, order);
      }
      await _refreshComponents();
    } on FirebaseException catch (error) {
      _showError(error.message ?? error.code);
    } on StateError catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reorderComponents(
    KnowledgeNode inserted,
    int index,
  ) async {
    final components = await _service.loadComponents(_selectedDocument!.id);
    final sorted = components.where((item) => item.id != inserted.id).toList();
    sorted.insert(index.clamp(0, sorted.length).toInt(), inserted);
    for (var order = 0; order < sorted.length; order++) {
      await widget.store.upsertNode(
        sorted[order].copyWith(
          updatedAt: DateTime.now(),
          metadata: {...sorted[order].metadata, 'order': '$order'},
        ),
      );
    }
  }

  Future<void> _moveComponent(
    int oldIndex,
    int newIndex, {
    bool indexAlreadyAdjusted = false,
  }) async {
    if (!indexAlreadyAdjusted && newIndex > oldIndex) newIndex--;
    if (newIndex == oldIndex ||
        oldIndex < 0 ||
        oldIndex >= _components.length ||
        newIndex < 0 ||
        newIndex >= _components.length) {
      return;
    }
    final reordered = [..._components];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    setState(() => _busy = true);
    try {
      for (var index = 0; index < reordered.length; index++) {
        final component = reordered[index];
        await widget.store.upsertNode(
          component.copyWith(
            updatedAt: DateTime.now(),
            metadata: {...component.metadata, 'order': '$index'},
          ),
        );
      }
      await _refreshComponents();
    } on FirebaseException catch (error) {
      _showError(error.message ?? error.code);
    } on StateError catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshComponents() async {
    final document = _selectedDocument;
    if (document == null) return;
    final components = await _service.loadComponents(document.id);
    final allNodes = await widget.store.listNodes();
    if (!mounted) return;
    setState(() {
      _components = components;
      _allNodes = allNodes;
      _componentKeys
        ..clear()
        ..addEntries(components.map((component) => MapEntry(
              component.id,
              GlobalKey(),
            )));
    });
  }

  Future<void> _editComponent(KnowledgeNode component) async {
    final input = await showDialog<_ComponentEdit>(
      context: context,
      builder: (_) => _ComponentEditDialog(component: component),
    );
    if (input == null || !mounted) return;
    if (input.assisted &&
        !await requireFeatureAccess(
            context, PermissionFeatures.memoAssistant)) {
      return;
    }
    try {
      if (input.assisted) {
        await _service.addRevision(component, revisionType: 'beforeAi');
      }
      await widget.store.upsertNode(
        component.copyWith(
          title: input.title,
          content: input.content,
          updatedAt: DateTime.now(),
          metadata: {
            ...component.metadata,
            if (MemoComponentKind.fromKey(
                  component.metadata['componentKind'],
                ) ==
                MemoComponentKind.graph)
              'graphType': input.graphType.key,
          },
        ),
      );
      await _saveDraftSnapshot();
      await _refreshComponents();
    } on FirebaseException catch (error) {
      _showError(error.message ?? error.code);
    } on StateError catch (error) {
      _showError(error.message);
    }
  }

  Future<void> _assistComponent(KnowledgeNode component) async {
    if (!await requireFeatureAccess(
        context, PermissionFeatures.memoAssistant)) {
      return;
    }
    if (!mounted) return;
    final request = await _askAiInstruction();
    if (request == null || !mounted) return;
    try {
      final options = await _loadAiOptions();
      await _service.addRevision(component, revisionType: 'beforeAi');
      final result = await _service.assist(
        component: component,
        instruction: 'create',
        request: request,
      );
      if (options.keepAiHistory) {
        await _service.saveAiHistory(
          component,
          response: result,
          request: request,
        );
      }
      if (!mounted) return;
      await _editComponent(
        component.copyWith(content: result),
      );
    } on FirebaseException catch (error) {
      _showError(error.message ?? error.code);
    } on StateError catch (error) {
      _showError(error.message);
    }
  }

  Future<MemoCanvasAiOptions> _loadAiOptions() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('memoCanvas.aiOptions');
    if (raw == null) return const MemoCanvasAiOptions();
    return MemoCanvasAiOptions.fromMap(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<String?> _askAiInstruction() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const AppText('AI 어시스턴트'),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: AppText.localize(context, '수정 요청'),
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const AppText('취소'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) return;
                Navigator.pop(context, controller.text.trim());
              },
              child: const AppText('생성'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteComponent(KnowledgeNode component) async {
    if (component.metadata['componentKind'] == MemoComponentKind.outline.key) {
      _showError('문서 개요는 필수이므로 삭제할 수 없습니다.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('구성요소 삭제'),
        content: AppText('“${component.title}” 구성요소를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.deleteNode(component.id);
    await _refreshComponents();
  }

  Future<void> _showComponentHistory(KnowledgeNode component) async {
    if (!await requireFeatureAccess(context, PermissionFeatures.memoHistory)) {
      return;
    }
    if (!mounted) return;
    final history = await _service.loadHistory(component.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('버전 및 AI 히스토리'),
        content: SizedBox(
          width: 520,
          child: history.isEmpty
              ? const AppText('저장된 버전이나 AI 답변이 없습니다.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in history)
                      ListTile(
                        leading: Icon(
                          item.metadata['historyFor'] == component.id
                              ? Icons.auto_awesome_rounded
                              : Icons.history_rounded,
                        ),
                        title: AppText(
                          item.metadata['historyFor'] == component.id
                              ? 'AI 답변'
                              : '이전 버전',
                        ),
                        subtitle: Text(
                          item.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          await _service.addRevision(
                            component,
                            revisionType: 'beforeRestore',
                          );
                          await widget.store.upsertNode(
                            component.copyWith(
                              content: item.content,
                              updatedAt: DateTime.now(),
                            ),
                          );
                          if (context.mounted) Navigator.pop(context);
                          await _refreshComponents();
                        },
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDocument(KnowledgeNode document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('문서 삭제'),
        content: AppText('“${document.title}” 문서와 구성요소를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.deleteDocument(document);
    if (!mounted) return;
    setState(() {
      _selectedDocument = null;
      _components = const [];
    });
    await _loadDocuments();
  }

  Future<void> _saveDraftSnapshot() async {
    final document = _selectedDocument;
    if (document == null) return;
    final preferences = await SharedPreferences.getInstance();
    final key = 'memoCanvas.backDrafts.${document.id}';
    final drafts = (jsonDecode(preferences.getString(key) ?? '[]') as List)
        .whereType<String>()
        .toList();
    drafts.insert(
      0,
      jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'documentTitle': document.title,
        'documentMetadata': document.metadata,
        'components': _components
            .map((component) => {
                  'id': component.id,
                  'title': component.title,
                  'content': component.content,
                  'updatedAt': component.updatedAt.toIso8601String(),
                  'createdAt': component.createdAt.toIso8601String(),
                  'kind': component.metadata['componentKind'],
                  'order': component.metadata['order'],
                  'depth': component.metadata['depth'],
                  'parentId': component.metadata['parentId'],
                  'source': component.metadata['source'],
                })
            .toList(),
      }),
    );
    await preferences.setString(key, jsonEncode(drafts.take(10).toList()));
  }

  Future<void> _showDrafts() async {
    final document = _selectedDocument;
    if (document == null) return;
    final preferences = await SharedPreferences.getInstance();
    final drafts = (jsonDecode(
      preferences.getString('memoCanvas.backDrafts.${document.id}') ?? '[]',
    ) as List)
        .whereType<String>()
        .toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('임시 저장 기록'),
        content: SizedBox(
          width: 440,
          child: drafts.isEmpty
              ? const AppText('뒤로가기 임시 저장 기록이 없습니다.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (var index = 0; index < drafts.length; index++)
                      ListTile(
                        leading: const Icon(Icons.history_rounded),
                        title: AppText('임시 저장 ${index + 1}회'),
                        subtitle: Text(
                          (jsonDecode(drafts[index]) as Map)['savedAt']
                              as String,
                        ),
                        onTap: () async {
                          await _restoreDraft(document, drafts[index]);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreDraft(KnowledgeNode document, String json) async {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final title = decoded['documentTitle'] as String?;
    final metadata = decoded['documentMetadata'];
    var restoredDocument = document;
    if (title != null && metadata is Map) {
      restoredDocument = document.copyWith(
        title: title,
        updatedAt: DateTime.now(),
        metadata: Map<String, String>.from(metadata),
      );
      await widget.store.upsertNode(
        restoredDocument,
      );
    }
    final saved = decoded['components'] as List? ?? const [];
    final savedIds = <String>{};
    for (final raw in saved.whereType<Map>()) {
      final data = Map<String, dynamic>.from(raw);
      final id = data['id'] as String?;
      if (id == null) continue;
      savedIds.add(id);
      final current = await widget.store.findNode(id);
      final now = DateTime.now();
      final component = KnowledgeNode(
        id: id,
        type: 'memo',
        title: data['title'] as String? ?? current?.title ?? '',
        content: data['content'] as String? ?? current?.content ?? '',
        createdAt: current?.createdAt ??
            DateTime.tryParse(data['createdAt'] as String? ?? '') ??
            now,
        updatedAt: now,
        metadata: {
          ...?current?.metadata,
          'mode': 'memo',
          'documentId': document.id,
          'componentKind': data['kind'] as String? ?? 'text',
          'order': data['order'] as String? ?? '0',
          'depth': data['depth'] as String? ?? '1',
          'source': data['source'] as String? ?? 'draft',
          if (data['parentId'] is String)
            'parentId': data['parentId'] as String,
        },
      );
      if (current == null) {
        await widget.store.insertNode(component);
      } else {
        await widget.store.upsertNode(component);
      }
    }
    for (final component in await _service.loadComponents(document.id)) {
      if (!savedIds.contains(component.id) &&
          component.metadata['componentKind'] !=
              MemoComponentKind.outline.key) {
        await widget.store.deleteNode(component.id);
      }
    }
    await _openDocument(restoredDocument);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: AppText(message)),
    );
  }

  List<KnowledgeNode> _filterDocuments(
    String rawQuery,
    _MemoSearchMode searchMode,
  ) {
    final query = rawQuery.trim().toLowerCase();
    final matches = _documents.where((document) {
      final componentText = _allNodes
          .where((component) => component.metadata['documentId'] == document.id)
          .map((component) => component.content)
          .join(' ')
          .toLowerCase();
      final matchesQuery = query.isEmpty ||
          switch (searchMode) {
            _MemoSearchMode.tags =>
              document.tags.any((tag) => tag.toLowerCase().contains(query)),
            _MemoSearchMode.title =>
              document.title.toLowerCase().contains(query),
            _MemoSearchMode.content =>
              document.content.toLowerCase().contains(query) ||
                  componentText.contains(query),
            _MemoSearchMode.all =>
              document.title.toLowerCase().contains(query) ||
                  document.content.toLowerCase().contains(query) ||
                  componentText.contains(query) ||
                  document.tags.any((tag) => tag.toLowerCase().contains(query)),
          };
      return matchesQuery;
    }).toList();
    switch (_sortMode) {
      case _MemoSortMode.newest:
        matches.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _MemoSortMode.tags:
        final popularity = <String, int>{};
        for (final document in _documents) {
          for (final tag in document.tags) {
            popularity.update(
              tag.toLowerCase(),
              (tagCount) => tagCount + 1,
              ifAbsent: () => 1,
            );
          }
        }
        int popularityOf(KnowledgeNode document) => document.tags.fold(
              0,
              (total, tag) => total + (popularity[tag.toLowerCase()] ?? 0),
            );
        matches.sort((a, b) {
          final tagCompare = popularityOf(b).compareTo(popularityOf(a));
          return tagCompare != 0
              ? tagCompare
              : b.updatedAt.compareTo(a.updatedAt);
        });
      case _MemoSortMode.kind:
        matches.sort((a, b) => MemoDocumentKind.fromKey(
              a.metadata['documentKind'],
            ).index.compareTo(MemoDocumentKind.fromKey(
                  b.metadata['documentKind'],
                ).index));
      case _MemoSortMode.newestAndKind:
        matches.sort((a, b) {
          final kindCompare = MemoDocumentKind.fromKey(
            a.metadata['documentKind'],
          ).index.compareTo(MemoDocumentKind.fromKey(
                b.metadata['documentKind'],
              ).index);
          return kindCompare != 0
              ? kindCompare
              : b.updatedAt.compareTo(a.updatedAt);
        });
    }
    return matches;
  }

  List<KnowledgeNode> get _filteredDocuments =>
      _filterDocuments(_query, _searchMode);

  Widget _searchModeDropdown({
    required _MemoSearchMode value,
    required ValueChanged<_MemoSearchMode> onChanged,
    String? key,
  }) =>
      SizedBox(
        width: 76,
        child: DropdownButton<_MemoSearchMode>(
          key: key == null ? null : ValueKey(key),
          isExpanded: true,
          isDense: true,
          underline: const SizedBox.shrink(),
          value: value,
          selectedItemBuilder: (context) => [
            for (final label in ['전체', '태그', '제목', '내용'])
              Center(child: AppText(label)),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
          items: [
            _searchItem(_MemoSearchMode.all, '전체검색'),
            _searchItem(_MemoSearchMode.tags, '태그검색'),
            _searchItem(_MemoSearchMode.title, '제목검색'),
            _searchItem(_MemoSearchMode.content, '내용검색'),
          ],
        ),
      );

  Widget _sortDropdown({String? key}) => Tooltip(
        message: AppText.localize(context, '정렬'),
        child: SizedBox(
          width: 72,
          child: DropdownButton<_MemoSortMode>(
            key: key == null ? null : ValueKey(key),
            isExpanded: true,
            isDense: true,
            underline: const SizedBox.shrink(),
            value: _sortMode,
            selectedItemBuilder: (context) => [
              for (final _ in _MemoSortMode.values)
                const Center(child: Icon(Icons.sort_rounded, size: 20)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _sortMode = value);
            },
            items: [
              _sortItem(_MemoSortMode.newest, '최신순'),
              _sortItem(_MemoSortMode.tags, '태그 사용순'),
              _sortItem(_MemoSortMode.kind, '메모 종류별'),
              _sortItem(_MemoSortMode.newestAndKind, '최신순 + 메모 종류별'),
            ],
          ),
        ),
      );

  KnowledgeNode? _findDocument(String? id) => id == null
      ? null
      : _documents.where((document) => document.id == id).firstOrNull;

  Widget _buildSplitLibrary() {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    return isWide
        ? Row(
            children: [
              Expanded(
                child: _buildSplitPane(
                  side: 'left',
                  query: _leftSplitQuery,
                  searchMode: _leftSplitSearchMode,
                  selectedDocument: _findDocument(_leftSplitDocumentId),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _buildSplitPane(
                  side: 'right',
                  query: _rightSplitQuery,
                  searchMode: _rightSplitSearchMode,
                  selectedDocument: _findDocument(_rightSplitDocumentId),
                ),
              ),
            ],
          )
        : Column(
            children: [
              Expanded(
                child: _buildSplitPane(
                  side: 'left',
                  query: _leftSplitQuery,
                  searchMode: _leftSplitSearchMode,
                  selectedDocument: _findDocument(_leftSplitDocumentId),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _buildSplitPane(
                  side: 'right',
                  query: _rightSplitQuery,
                  searchMode: _rightSplitSearchMode,
                  selectedDocument: _findDocument(_rightSplitDocumentId),
                ),
              ),
            ],
          );
  }

  Widget _buildSplitPane({
    required String side,
    required String query,
    required _MemoSearchMode searchMode,
    required KnowledgeNode? selectedDocument,
  }) {
    final isLeft = side == 'left';
    final results = _filterDocuments(query, searchMode);
    final selectedComponents = selectedDocument == null
        ? <KnowledgeNode>[]
        : _allNodes
            .where(
              (node) => node.metadata['documentId'] == selectedDocument.id,
            )
            .toList();
    selectedComponents.sort((a, b) {
      final first = int.tryParse(a.metadata['order'] ?? '') ?? 0;
      final second = int.tryParse(b.metadata['order'] ?? '') ?? 0;
      return first.compareTo(second);
    });
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('memo-split-search-$side'),
                  onChanged: (value) => setState(() {
                    if (isLeft) {
                      _leftSplitQuery = value;
                    } else {
                      _rightSplitQuery = value;
                    }
                  }),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: AppText.localize(context, '메모 검색'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _searchModeDropdown(
                value: searchMode,
                key: 'memo-split-search-mode-$side',
                onChanged: (value) => setState(() {
                  if (isLeft) {
                    _leftSplitSearchMode = value;
                  } else {
                    _rightSplitSearchMode = value;
                  }
                }),
              ),
              const SizedBox(width: 2),
              _sortDropdown(key: 'memo-split-sort-$side'),
            ],
          ),
          Expanded(
            child: selectedDocument != null
                ? _buildSplitDocument(
                    side: side,
                    document: selectedDocument,
                    components: selectedComponents,
                  )
                : _buildSplitResults(
                    side: side,
                    results: results,
                    selectedDocument: selectedDocument,
                    isLeft: isLeft,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitResults({
    required String side,
    required List<KnowledgeNode> results,
    required KnowledgeNode? selectedDocument,
    required bool isLeft,
  }) {
    if (results.isEmpty) {
      return const Center(child: AppText('검색 결과가 없습니다.'));
    }
    void select(KnowledgeNode document) {
      setState(() {
        if (isLeft) {
          _leftSplitDocumentId = document.id;
          if (_rightSplitDocumentId == document.id) {
            _rightSplitDocumentId = null;
          }
        } else {
          _rightSplitDocumentId = document.id;
          if (_leftSplitDocumentId == document.id) {
            _leftSplitDocumentId = null;
          }
        }
      });
    }

    if (_viewMode == _MemoViewMode.list) {
      return ListView.builder(
        key: PageStorageKey('memo-split-results-$side'),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final document = results[index];
          return ListTile(
            key: ValueKey('memo-split-result-$side-${document.id}'),
            dense: true,
            selected: selectedDocument?.id == document.id,
            leading: const Icon(Icons.description_outlined),
            title: AppText(
              document.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(MemoDocumentKind.fromKey(
                  document.metadata['documentKind'],
                ).label),
                AppText('생성일: ${_createdAtLabel(document.createdAt)}'),
              ],
            ),
            onTap: () => select(document),
          );
        },
      );
    }

    return GridView.builder(
      key: PageStorageKey('memo-split-results-$side'),
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 112,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final document = results[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('memo-split-result-$side-${document.id}'),
            onTap: () => select(document),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  AppText(
                    MemoDocumentKind.fromKey(
                      document.metadata['documentKind'],
                    ).label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSplitDocument({
    required String side,
    required KnowledgeNode document,
    required List<KnowledgeNode> components,
  }) {
    final outline = components
        .where(
          (component) =>
              component.metadata['componentKind'] ==
              MemoComponentKind.outline.key,
        )
        .toList();
    final content = components
        .where(
          (component) =>
              component.metadata['componentKind'] !=
              MemoComponentKind.outline.key,
        )
        .toList();
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              key: ValueKey('memo-split-back-$side'),
              tooltip: AppText.localize(context, '뒤로'),
              onPressed: () => setState(() {
                if (side == 'left') {
                  _leftSplitDocumentId = null;
                } else {
                  _rightSplitDocumentId = null;
                }
              }),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Text(
                document.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (outline.isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: Card(
              margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppText('개요'),
                    const SizedBox(height: 4),
                    for (final item in outline)
                      Text(
                        item.content,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: content.isEmpty
              ? const Center(child: AppText('내용이 없습니다.'))
              : ListView.builder(
                  key: ValueKey('memo-split-document-$side-${document.id}'),
                  itemCount: content.length,
                  itemBuilder: (context, index) {
                    final component = content[index];
                    final kind = MemoComponentKind.fromKey(
                      component.metadata['componentKind'],
                    );
                    return Card(
                      margin: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              component.title,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            _componentContent(component, kind),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = _selectedDocument;
    return Scaffold(
      appBar: AppBar(
        leading: document == null
            ? null
            : IconButton(
                tooltip: AppText.localize(context, '뒤로'),
                onPressed: () async {
                  await _saveDraftSnapshot();
                  if (mounted) setState(() => _selectedDocument = null);
                },
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: document == null ? const AppText('메모') : Text(document.title),
        actions: document == null
            ? [
                IconButton(
                  key: const ValueKey('memo-view-mode-toggle'),
                  tooltip: AppText.localize(context, '보기 방식'),
                  onPressed: () => setState(() {
                    _viewMode = _viewMode == _MemoViewMode.grid
                        ? _MemoViewMode.list
                        : _MemoViewMode.grid;
                  }),
                  icon: Icon(_viewMode == _MemoViewMode.grid
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded),
                ),
                IconButton(
                  tooltip: AppText.localize(context, '분할 화면'),
                  onPressed: () => setState(() => _splitMode = !_splitMode),
                  icon: Icon(_splitMode
                      ? Icons.view_agenda_rounded
                      : Icons.view_sidebar_rounded),
                ),
              ]
            : [
                IconButton(
                  tooltip: AppText.localize(context, '문서 제목 수정'),
                  onPressed: () => _editDocument(document),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: AppText.localize(context, '임시 저장 기록'),
                  onPressed: _showDrafts,
                  icon: const Icon(Icons.history_rounded),
                ),
                IconButton(
                  tooltip: AppText.localize(context, '개요 표시'),
                  onPressed: () => setState(
                    () => _outlineVisible = !_outlineVisible,
                  ),
                  icon: const Icon(Icons.menu_open_rounded),
                ),
              ],
      ),
      floatingActionButton: document == null && !_splitMode
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _createDocument,
              icon: const Icon(Icons.add_rounded),
              label: const AppText('새 문서'),
            )
          : null,
      body: _loading || _busy && document == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: AppText('메모를 불러오지 못했습니다: $_error'))
              : document == null
                  ? _splitMode
                      ? _buildSplitLibrary()
                      : _buildLibrary()
                  : _buildDocument(document),
    );
  }

  Widget _buildLibrary() {
    final documents = _filteredDocuments;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: AppText.localize(context, '메모 검색'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _searchModeDropdown(
                value: _searchMode,
                key: 'memo-library-search-mode',
                onChanged: (value) => setState(() => _searchMode = value),
              ),
              const SizedBox(width: 4),
              _sortDropdown(key: 'memo-library-sort'),
            ],
          ),
        ),
        Expanded(
          child: documents.isEmpty
              ? const Center(
                  child: AppText('저장된 문서가 없습니다. 새 문서를 만들어 보세요.'),
                )
              : _viewMode == _MemoViewMode.grid
                  ? GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 360,
                        mainAxisExtent: 148,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: documents.length,
                      itemBuilder: (context, index) =>
                          _documentCard(documents[index]),
                    )
                  : ListView.builder(
                      itemCount: documents.length,
                      itemBuilder: (context, index) =>
                          _documentListTile(documents[index]),
                    ),
        ),
      ],
    );
  }

  DropdownMenuItem<_MemoSearchMode> _searchItem(
    _MemoSearchMode mode,
    String label,
  ) =>
      DropdownMenuItem(value: mode, child: AppText(label));

  DropdownMenuItem<_MemoSortMode> _sortItem(
    _MemoSortMode mode,
    String label,
  ) =>
      DropdownMenuItem(value: mode, child: AppText(label));

  String _createdAtLabel(DateTime value) {
    final date = value.toLocal();
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Widget _documentCard(KnowledgeNode document) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openDocument(document),
          onLongPress: () => _deleteDocument(document),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        document.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'delete') _deleteDocument(document);
                        if (action == 'edit') _editDocument(document);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: AppText('문서 수정'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: AppText('삭제'),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                AppText('생성일: ${_createdAtLabel(document.createdAt)}'),
                AppText(MemoDocumentKind.fromKey(
                  document.metadata['documentKind'],
                ).label),
                Wrap(
                  spacing: 6,
                  children: document.tags
                      .take(3)
                      .map((tag) => AppText('#$tag'))
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _documentListTile(KnowledgeNode document) => ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(document.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(MemoDocumentKind.fromKey(
              document.metadata['documentKind'],
            ).label),
            AppText('생성일: ${_createdAtLabel(document.createdAt)}'),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'delete') _deleteDocument(document);
            if (action == 'edit') _editDocument(document);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: AppText('문서 수정')),
            const PopupMenuItem(value: 'delete', child: AppText('삭제')),
          ],
        ),
        onTap: () => _openDocument(document),
      );

  Future<void> _editDocument(KnowledgeNode document) async {
    final input = await showDialog<_NewDocumentInput>(
      context: context,
      builder: (_) => _NewDocumentDialog(existing: document),
    );
    if (input == null) return;
    await widget.store.upsertNode(
      document.copyWith(
        title: input.title,
        content: input.content,
        updatedAt: DateTime.now(),
        metadata: {
          ...document.metadata,
          'documentKind': input.kind.key,
        },
      ),
    );
    await _loadDocuments();
  }

  Widget _buildDocument(KnowledgeNode document) {
    final orientation = MediaQuery.orientationOf(context);
    final isMobilePortrait = MediaQuery.sizeOf(context).width < 700 &&
        orientation == Orientation.portrait;
    final outline = _outlinePanel();
    final canvas = _componentCanvas(document);
    if (!_outlineVisible) return canvas;
    return isMobilePortrait
        ? Row(
            children: [
              SizedBox(width: 44, child: outline),
              const VerticalDivider(width: 1),
              Expanded(child: canvas),
            ],
          )
        : Row(
            children: [
              SizedBox(width: 220, child: outline),
              const VerticalDivider(width: 1),
              Expanded(child: canvas),
            ],
          );
  }

  Widget _outlinePanel() {
    final entries = _components;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Expanded(child: AppText('개요')),
              IconButton(
                tooltip: AppText.localize(context, '개요 숨기기'),
                onPressed: () => setState(() => _outlineVisible = false),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final component in entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.only(
                    left: 8 +
                        (int.tryParse(component.metadata['depth'] ?? '1') ??
                                1) *
                            12,
                    right: 4,
                  ),
                  leading: Icon(
                    _componentIcon(
                      MemoComponentKind.fromKey(
                        component.metadata['componentKind'],
                      ),
                    ),
                    size: 18,
                  ),
                  title: Text(
                    component.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _jumpTo(component),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _jumpTo(KnowledgeNode component) {
    final context = _componentKeys[component.id]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 250),
      alignment: 0.1,
    );
  }

  Widget _componentCanvas(KnowledgeNode document) {
    if (_components.isEmpty) {
      return const Center(child: AppText('개요 구성요소를 준비하고 있습니다.'));
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
      buildDefaultDragHandles: false,
      itemCount: _components.length + (_outlineVisible ? 0 : 1),
      onReorderItem: (oldIndex, newIndex) {
        final offset = _outlineVisible ? 0 : 1;
        final targetIndex =
            !_outlineVisible && newIndex == 0 ? 0 : newIndex - offset;
        _moveComponent(
          oldIndex - offset,
          targetIndex,
          indexAlreadyAdjusted: true,
        );
      },
      itemBuilder: (context, index) {
        if (!_outlineVisible && index == 0) {
          return SizedBox(
            key: const ValueKey('memo-outline-toggle'),
            height: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _outlineVisible = true),
                icon: const Icon(Icons.menu_book_rounded),
                label: const AppText('개요 표시'),
              ),
            ),
          );
        }
        final componentIndex = index - (_outlineVisible ? 0 : 1);
        final component = _components[componentIndex];
        return ReorderableDelayedDragStartListener(
          key: ValueKey('memo-reorder-${component.id}'),
          index: index,
          child: Padding(
            key: _componentKeys[component.id],
            padding: const EdgeInsets.only(bottom: 4),
            child: _componentCard(document, component),
          ),
        );
      },
    );
  }

  Widget _componentCard(KnowledgeNode document, KnowledgeNode component) {
    final kind = MemoComponentKind.fromKey(
      component.metadata['componentKind'],
    );
    final borderColor = Theme.of(context).dividerColor.withValues(alpha: 0.55);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: borderColor, width: 0.7),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(_componentIcon(kind), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                component.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'edit') _editComponent(component);
                                if (action == 'delete') {
                                  _deleteComponent(component);
                                }
                                if (action == 'assist') {
                                  _assistComponent(component);
                                }
                                if (action == 'history') {
                                  _showComponentHistory(component);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: AppText('수정'),
                                ),
                                const PopupMenuItem(
                                  value: 'assist',
                                  child: AppText('AI 어시스턴트'),
                                ),
                                const PopupMenuItem(
                                  value: 'history',
                                  child: AppText('버전 및 AI 히스토리'),
                                ),
                                if (kind != MemoComponentKind.outline)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: AppText('삭제'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: () => _editComponent(component),
                            child: _componentContent(component, kind),
                          ),
                        ),
                        if (document.metadata['documentKind'] ==
                            MemoDocumentKind.research.key)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _assistComponent(component),
                              icon: const Icon(Icons.auto_awesome_rounded),
                              label: const AppText('AI로 표·그래프 만들기'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            _componentAddButton(
              component,
            ),
          ],
        ),
      ),
    );
  }

  Widget _componentAddButton(
    KnowledgeNode component,
  ) =>
      SizedBox(
        height: 28,
        child: IconButton(
          key: ValueKey('memo-add-bottom-${component.id}'),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 28),
          tooltip: AppText.localize(context, '아래에 구성요소 추가'),
          onPressed: _busy ? null : () => _addComponent(after: component),
          icon: Icon(
            Icons.add_circle_outline_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
          ),
        ),
      );

  Widget _componentContent(KnowledgeNode component, MemoComponentKind kind) {
    final mode = switch (kind) {
      MemoComponentKind.table => AssistantDisplayMode.table,
      MemoComponentKind.graph => AssistantDisplayMode.graph,
      MemoComponentKind.mindMap => AssistantDisplayMode.mindMap,
      MemoComponentKind.image => AssistantDisplayMode.image,
      MemoComponentKind.outline => AssistantDisplayMode.outline,
      _ => AssistantDisplayMode.fromKey(component.metadata['mode'] ?? 'memo'),
    };
    return MemoModeContentDisplay(
      content: component.content,
      mode: mode,
    );
  }

  IconData _componentIcon(MemoComponentKind kind) => switch (kind) {
        MemoComponentKind.text ||
        MemoComponentKind.customText =>
          Icons.notes_rounded,
        MemoComponentKind.table => Icons.table_chart_rounded,
        MemoComponentKind.graph => Icons.bar_chart_rounded,
        MemoComponentKind.mindMap => Icons.hub_rounded,
        MemoComponentKind.outline => Icons.account_tree_rounded,
        MemoComponentKind.image => Icons.image_outlined,
      };
}

class _MemoGraphPainter extends CustomPainter {
  const _MemoGraphPainter(this.values, this.type);

  final List<double> values;
  final MemoGraphType type;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    if (type == MemoGraphType.pie) {
      _paintPie(canvas, size);
      return;
    }
    final maxValue = values.map((value) => value.abs()).reduce(
          (a, b) => a > b ? a : b,
        );
    final paint = Paint()
      ..color = const Color(0xff4969cf)
      ..style = PaintingStyle.fill;
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final normalized = maxValue == 0 ? 0.0 : values[index] / maxValue;
      final x = values.length == 1
          ? size.width / 2
          : index * size.width / (values.length - 1);
      final y = size.height - ((normalized + 1) / 2 * size.height);
      points.add(Offset(x, y));
      if (type == MemoGraphType.bar) {
        final barWidth = size.width / (values.length * 1.6);
        final left = (index + 0.5) * size.width / values.length - barWidth / 2;
        final barHeight = values[index].abs() /
            (maxValue == 0 ? 1 : maxValue) *
            (size.height * 0.9);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, size.height - barHeight, barWidth, barHeight),
            const Radius.circular(4),
          ),
          paint,
        );
      }
    }
    if (type == MemoGraphType.line) {
      final linePaint = Paint()
        ..color = const Color(0xff4969cf)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, linePaint);
      final pointPaint = Paint()
        ..color = const Color(0xfff28c28)
        ..style = PaintingStyle.fill;
      for (final point in points) {
        canvas.drawCircle(point, 5, pointPaint);
      }
    }
  }

  void _paintPie(Canvas canvas, Size size) {
    final total = values.fold<double>(
      0,
      (totalValue, value) => totalValue + value.abs(),
    );
    if (total == 0) return;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.height * 0.9,
      height: size.height * 0.9,
    );
    const colors = [
      Color(0xff4969cf),
      Color(0xfff28c28),
      Color(0xff42a57a),
      Color(0xffc64c65),
      Color(0xff8b63bd),
    ];
    var startAngle = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index].abs() / total * math.pi * 2;
      canvas.drawArc(
        rect,
        startAngle,
        sweep,
        true,
        Paint()..color = colors[index % colors.length],
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _MemoGraphPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.type != type;
}

class _NewDocumentInput {
  const _NewDocumentInput({
    required this.title,
    required this.content,
    required this.kind,
    required this.options,
  });

  final String title;
  final String content;
  final MemoDocumentKind kind;
  final MemoCanvasAiOptions options;
}

class _NewDocumentDialog extends StatefulWidget {
  const _NewDocumentDialog({required this.existing});

  final KnowledgeNode existing;

  @override
  State<_NewDocumentDialog> createState() => _NewDocumentDialogState();
}

class _NewDocumentDialogState extends State<_NewDocumentDialog> {
  late final _title = TextEditingController(text: widget.existing.title);
  late final _content = TextEditingController(text: widget.existing.content);
  late MemoDocumentKind _kind =
      MemoDocumentKind.fromKey(widget.existing.metadata['documentKind']);
  MemoCanvasAiOptions _options = const MemoCanvasAiOptions();

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _aiSettings() async {
    final options = await showDialog<MemoCanvasAiOptions>(
      context: context,
      builder: (_) => _MemoCanvasAiOptionsDialog(initial: _options),
    );
    if (options != null && mounted) setState(() => _options = options);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const AppText('문서 수정'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: AppText.localize(context, '제목'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<MemoDocumentKind>(
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: AppText.localize(context, '메모 종류'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final kind in MemoDocumentKind.values)
                      DropdownMenuItem(
                        value: kind,
                        child: AppText(kind.label),
                      ),
                  ],
                  onChanged: (kind) {
                    if (kind != null) setState(() => _kind = kind);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _content,
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: AppText.localize(context, '내용'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _aiSettings,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const AppText('저장 시 AI 처리 설정'),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('취소'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                context,
                _NewDocumentInput(
                  title: _title.text.trim(),
                  content: _content.text.trim(),
                  kind: _kind,
                  options: _options,
                ),
              );
            },
            child: const AppText('저장'),
          ),
        ],
      );
}

class _MemoCanvasAiOptionsDialog extends StatefulWidget {
  const _MemoCanvasAiOptionsDialog({required this.initial});

  final MemoCanvasAiOptions initial;

  @override
  State<_MemoCanvasAiOptionsDialog> createState() =>
      _MemoCanvasAiOptionsDialogState();
}

class _MemoCanvasAiOptionsDialogState
    extends State<_MemoCanvasAiOptionsDialog> {
  late MemoCanvasAiOptions _options = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const AppText('저장 시 AI 처리 설정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _option(
              '태그 생성',
              _options.generateTags,
              (value) => _options = _options.copyWith(generateTags: value),
            ),
            _option(
              '제목 생성',
              _options.generateTitle,
              (value) => _options = _options.copyWith(generateTitle: value),
            ),
            _option(
              '개요 생성',
              _options.generateOutline,
              (value) => _options = _options.copyWith(generateOutline: value),
            ),
            _option(
              '메모 종류 파악',
              _options.detectKind,
              (value) => _options = _options.copyWith(detectKind: value),
            ),
            _option(
              'AI 답변 히스토리 저장',
              _options.keepAiHistory,
              (value) => _options = _options.copyWith(keepAiHistory: value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('취소'),
          ),
          FilledButton(
            onPressed: () async {
              final preferences = await SharedPreferences.getInstance();
              await preferences.setString(
                'memoCanvas.aiOptions',
                jsonEncode(_options.toMap()),
              );
              if (context.mounted) Navigator.pop(context, _options);
            },
            child: const AppText('적용'),
          ),
        ],
      );

  Widget _option(
    String title,
    bool value,
    ValueChanged<bool> update,
  ) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: AppText(title),
        value: value,
        onChanged: (next) => setState(() => update(next)),
      );
}

class _ComponentInput {
  const _ComponentInput({
    required this.kind,
    required this.title,
    required this.content,
    required this.source,
    required this.instruction,
    required this.graphType,
    this.reuseFrom,
    this.parentId,
  });

  final MemoComponentKind kind;
  final String title;
  final String content;
  final String source;
  final String instruction;
  final MemoGraphType graphType;
  final String? reuseFrom;
  final String? parentId;
}

class _ComponentDialog extends StatefulWidget {
  const _ComponentDialog({
    required this.reusableComponents,
    required this.parentComponents,
    this.initialKind = MemoComponentKind.text,
    this.quickCreate = false,
    this.onQuickCreate,
  });

  final List<KnowledgeNode> reusableComponents;
  final List<KnowledgeNode> parentComponents;
  final MemoComponentKind initialKind;
  final bool quickCreate;
  final Future<void> Function(_ComponentInput input)? onQuickCreate;

  @override
  State<_ComponentDialog> createState() => _ComponentDialogState();
}

class _ComponentDialogState extends State<_ComponentDialog> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _imageDescription = TextEditingController();
  final _instruction = TextEditingController();
  late MemoComponentKind _kind = widget.initialKind;
  MemoGraphType _graphType = MemoGraphType.bar;
  String _source = 'created';
  String? _reuseFrom;
  String? _parentId;
  String? _validationError;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _imageDescription.dispose();
    _instruction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: AppText(widget.quickCreate ? _kind.label : '구성요소 추가'),
        content: SizedBox(
          width: math.min(
            520,
            math.max(0, MediaQuery.sizeOf(context).width - 80),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.quickCreate) ...[
                  DropdownButtonFormField<MemoComponentKind>(
                    initialValue: _kind,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: AppText.localize(context, '구성요소 종류'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final kind in MemoComponentKind.values)
                        DropdownMenuItem(
                          value: kind,
                          child: AppText(kind.label),
                        ),
                    ],
                    onChanged: (kind) {
                      if (kind != null) setState(() => _kind = kind);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _source,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: AppText.localize(context, '구성 방식'),
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'created',
                        child: AppText('직접 생성'),
                      ),
                      DropdownMenuItem(
                        value: 'ai',
                        child: AppText('AI 도움으로 생성'),
                      ),
                      DropdownMenuItem(
                        value: 'reuse',
                        child: AppText('기존 구성요소 그대로 사용'),
                      ),
                      DropdownMenuItem(
                        value: 'editReuse',
                        child: AppText('기존 구성요소 수정 후 사용'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _source = value);
                    },
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('memo-component-title'),
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: AppText.localize(context, '제목'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (!widget.quickCreate &&
                    (_source == 'reuse' || _source == 'editReuse')) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _reuseFrom,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: AppText.localize(context, '기존 구성요소 선택'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final component in widget.reusableComponents)
                        DropdownMenuItem(
                          value: component.id,
                          child: Text(
                            '${component.title} · ${MemoComponentKind.fromKey(component.metadata['componentKind']).label}',
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _reuseFrom = value);
                      final component = widget.reusableComponents
                          .where((item) => item.id == value)
                          .firstOrNull;
                      if (component != null) {
                        _title.text = component.title;
                        _content.text = component.content;
                        _kind = MemoComponentKind.fromKey(
                          component.metadata['componentKind'],
                        );
                      }
                    },
                  ),
                ],
                if (!widget.quickCreate)
                  DropdownButtonFormField<String?>(
                    initialValue: _parentId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: AppText.localize(context, '상위 개요'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: AppText('최상위'),
                      ),
                      for (final component in widget.parentComponents)
                        DropdownMenuItem<String?>(
                          value: component.id,
                          child: Text(component.title),
                        ),
                    ],
                    onChanged: (value) => setState(() => _parentId = value),
                  ),
                if (!widget.quickCreate) const SizedBox(height: 8),
                if (_kind == MemoComponentKind.graph)
                  DropdownButtonFormField<MemoGraphType>(
                    initialValue: _graphType,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: AppText.localize(context, '그래프 종류'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final type in MemoGraphType.values)
                        DropdownMenuItem(
                          value: type,
                          child: AppText(type.label),
                        ),
                    ],
                    onChanged: (type) {
                      if (type != null) setState(() => _graphType = type);
                    },
                  ),
                if (_kind == MemoComponentKind.graph) const SizedBox(height: 8),
                if (_source == 'created' || _source == 'editReuse')
                  TextField(
                    key: const ValueKey('memo-component-content'),
                    controller: _content,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: AppText.localize(
                        context,
                        switch (_kind) {
                          MemoComponentKind.graph => '그래프 데이터',
                          MemoComponentKind.image => '이미지 URL',
                          _ => '내용',
                        },
                      ),
                      hintText: AppText.localize(context, _contentHint),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                if (widget.quickCreate &&
                    (_source == 'created' || _source == 'editReuse')) ...[
                  if (_kind == MemoComponentKind.image)
                    TextField(
                      key: const ValueKey('memo-image-description'),
                      controller: _imageDescription,
                      readOnly: true,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: AppText.localize(context, 'AI 이미지 설명'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  MemoModeAssistantPanel(
                    mode: _kind.key,
                    onTextGenerated: (response) {
                      setState(() {
                        if (_kind == MemoComponentKind.image) {
                          _imageDescription.text = response;
                        } else {
                          _content.text = response;
                        }
                      });
                    },
                    imagePrompt: () => _imageDescription.text.trim().isNotEmpty
                        ? _imageDescription.text
                        : _content.text,
                    onImageGenerated: _kind == MemoComponentKind.image
                        ? (url) => setState(() => _content.text = url)
                        : null,
                    onApplyModeDisplay: (content, mode) {
                      setState(() {
                        _kind = switch (mode) {
                          AssistantDisplayMode.table => MemoComponentKind.table,
                          AssistantDisplayMode.graph => MemoComponentKind.graph,
                          AssistantDisplayMode.mindMap =>
                            MemoComponentKind.mindMap,
                          AssistantDisplayMode.image => MemoComponentKind.image,
                          AssistantDisplayMode.outline =>
                            MemoComponentKind.outline,
                          _ => MemoComponentKind.text,
                        };
                        _content.text = content;
                      });
                    },
                  ),
                  if (_kind == MemoComponentKind.image &&
                      Uri.tryParse(_content.text.trim())?.hasScheme == true)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: Image.network(
                        _content.text.trim(),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const AppText(
                          '이미지를 불러오지 못했습니다.',
                        ),
                      ),
                    ),
                ],
                if (_validationError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: AppText(
                        _validationError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (_source == 'ai')
                  TextField(
                    controller: _instruction,
                    minLines: 3,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: AppText.localize(context, 'AI 생성 요청'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('취소'),
          ),
          FilledButton(
            onPressed: () async {
              if (_saving) return;
              if (widget.quickCreate && _content.text.trim().isEmpty) {
                setState(() => _validationError = '내용을 입력해 주세요.');
                return;
              }
              if (widget.quickCreate &&
                  _kind == MemoComponentKind.graph &&
                  !_content.text
                      .split(RegExp(r'[\s,;]+'))
                      .any((value) => double.tryParse(value) != null)) {
                setState(
                  () => _validationError = '그래프에 사용할 숫자를 입력해 주세요.',
                );
                return;
              }
              if ((_source == 'reuse' || _source == 'editReuse') &&
                  _reuseFrom == null) {
                return;
              }
              var content = _content.text;
              if (_source == 'reuse' && _reuseFrom != null) {
                final node = widget.reusableComponents
                    .where((component) => component.id == _reuseFrom)
                    .firstOrNull;
                content = node?.content ?? content;
              }
              if (!context.mounted) return;
              final input = _ComponentInput(
                kind: _kind,
                title: _title.text.trim(),
                content: content,
                source: _source == 'editReuse' ? 'created' : _source,
                instruction: _instruction.text.trim(),
                graphType: _graphType,
                reuseFrom: _reuseFrom,
                parentId: _parentId,
              );
              final onQuickCreate = widget.onQuickCreate;
              if (!widget.quickCreate || onQuickCreate == null) {
                Navigator.pop(context, input);
                return;
              }
              setState(() {
                _saving = true;
                _validationError = null;
              });
              try {
                await onQuickCreate(input);
                if (context.mounted) Navigator.pop(context);
              } on FirebaseException catch (error) {
                if (mounted) {
                  setState(
                      () => _validationError = error.message ?? error.code);
                }
              } on StateError catch (error) {
                if (mounted) setState(() => _validationError = error.message);
              } on FormatException catch (error) {
                if (mounted) setState(() => _validationError = error.message);
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : AppText(widget.quickCreate ? '저장' : '계속'),
          ),
        ],
      );

  String get _contentHint => switch (_kind) {
        MemoComponentKind.text || MemoComponentKind.customText => '텍스트를 입력하세요.',
        MemoComponentKind.table => '표 데이터를 탭 또는 쉼표로 구분해 입력하세요.',
        MemoComponentKind.graph => '쉼표로 구분된 숫자를 입력하세요. 예: 5, 3, 8',
        MemoComponentKind.mindMap => '중심 주제와 하위 주제를 한 줄에 하나씩 입력하세요.',
        MemoComponentKind.outline => '개요 항목을 한 줄에 하나씩 입력하세요.',
        MemoComponentKind.image => '표시할 이미지의 URL을 입력하세요.',
      };
}

Future<void> showMemoCanvasQuickCreateDialog({
  required BuildContext context,
  required KnowledgeStore store,
  required MemoComponentKind kind,
}) async {
  final service = MemoCanvasService(store);
  final initialMode = switch (kind) {
    MemoComponentKind.table => AssistantDisplayMode.table,
    MemoComponentKind.graph => AssistantDisplayMode.graph,
    MemoComponentKind.mindMap => AssistantDisplayMode.mindMap,
    MemoComponentKind.image => AssistantDisplayMode.image,
    MemoComponentKind.outline => AssistantDisplayMode.outline,
    _ => AssistantDisplayMode.memo,
  };
  final result = await showDialog<UnifiedMemoResult>(
    context: context,
    builder: (_) => UnifiedMemoDialog(
      dialogTitle: '구성요소 추가',
      initialMode: initialMode,
    ),
  );
  if (result == null || !context.mounted) return;
  final title = result.title.trim().isEmpty ? kind.label : result.title.trim();
  final document = await service.createDocument(
    title: title,
    content: '',
    kind: MemoDocumentKind.memo,
    options: const MemoCanvasAiOptions(),
    outlineContent: kind == MemoComponentKind.outline ? result.content : null,
  );
  if (kind != MemoComponentKind.outline) {
    final compKind = switch (result.mode) {
      AssistantDisplayMode.table => MemoComponentKind.table,
      AssistantDisplayMode.graph => MemoComponentKind.graph,
      AssistantDisplayMode.mindMap => MemoComponentKind.mindMap,
      AssistantDisplayMode.image => MemoComponentKind.image,
      AssistantDisplayMode.outline => MemoComponentKind.outline,
      _ => MemoComponentKind.text,
    };
    await service.createComponent(
      document: document,
      kind: compKind,
      title: title,
      content: result.content,
      order: 1,
      parentId: result.parentId,
    );
  }
}

Future<void> showMemoPromptQuickCreateDialog({
  required BuildContext context,
  required KnowledgeStore store,
}) async {
  final draft = await showDialog<_QuickPromptDraft>(
    context: context,
    builder: (_) => const _QuickPromptDialog(),
  );
  if (draft == null || !context.mounted) return;
  try {
    await MemoCanvasService(store).createDocument(
      title: draft.title,
      content: draft.content,
      kind: MemoDocumentKind.prompt,
      options: const MemoCanvasAiOptions(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('프롬프트를 저장했습니다.')),
      );
    }
  } on FirebaseException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            '프롬프트 저장 실패: Firebase ${error.code}: ${error.message ?? '권한 또는 App Check 설정을 확인해 주세요.'}',
          ),
        ),
      );
    }
  } on StateError catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('프롬프트 저장 실패: ${error.message}')),
      );
    }
  } on FormatException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('프롬프트 저장 실패: ${error.message}')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('프롬프트 저장 실패: $error')),
      );
    }
  }
}

class _QuickPromptDraft {
  const _QuickPromptDraft({required this.title, required this.content});

  final String title;
  final String content;
}

class _QuickPromptDialog extends StatefulWidget {
  const _QuickPromptDialog();

  @override
  State<_QuickPromptDialog> createState() => _QuickPromptDialogState();
}

class _QuickPromptDialogState extends State<_QuickPromptDialog> {
  final _title = TextEditingController();
  final _content = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('제목과 프롬프트 내용을 입력해 주세요.')),
      );
      return;
    }
    Navigator.pop(
      context,
      _QuickPromptDraft(title: title, content: content),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const AppText('새 프롬프트'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('quick-prompt-title'),
                  controller: _title,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: AppText.localize(context, '제목'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('quick-prompt-content'),
                  controller: _content,
                  minLines: 5,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: AppText.localize(context, '프롬프트 내용'),
                    hintText: AppText.localize(context, '프롬프트를 입력하세요.'),
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                MemoModeAssistantPanel(
                  mode: 'prompt',
                  onTextGenerated: (response) {
                    setState(() => _content.text = response);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('취소'),
          ),
          FilledButton(
            onPressed: _save,
            child: const AppText('저장'),
          ),
        ],
      );
}

class _ComponentEdit {
  const _ComponentEdit({
    required this.title,
    required this.content,
    required this.graphType,
    this.assisted = false,
  });

  final String title;
  final String content;
  final MemoGraphType graphType;
  final bool assisted;
}

class _ComponentEditDialog extends StatefulWidget {
  const _ComponentEditDialog({required this.component});

  final KnowledgeNode component;

  @override
  State<_ComponentEditDialog> createState() => _ComponentEditDialogState();
}

class _ComponentEditDialogState extends State<_ComponentEditDialog> {
  late final _title = TextEditingController(text: widget.component.title);
  late final _content = TextEditingController(text: widget.component.content);
  late MemoGraphType _graphType =
      MemoGraphType.fromKey(widget.component.metadata['graphType']);
  bool _assisted = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const AppText('구성요소 수정'),
        content: SizedBox(
          width: math.min(
            520,
            math.max(0, MediaQuery.sizeOf(context).width - 80),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: AppText.localize(context, '제목'),
                  ),
                ),
                TextField(
                  controller: _content,
                  minLines: 5,
                  maxLines: 12,
                  decoration: InputDecoration(
                    labelText: AppText.localize(
                      context,
                      MemoComponentKind.fromKey(
                                widget.component.metadata['componentKind'],
                              ) ==
                              MemoComponentKind.graph
                          ? '그래프 데이터'
                          : '내용',
                    ),
                    hintText: MemoComponentKind.fromKey(
                              widget.component.metadata['componentKind'],
                            ) ==
                            MemoComponentKind.graph
                        ? AppText.localize(
                            context,
                            '쉼표로 구분된 숫자를 입력하세요. 예: 5, 3, 8',
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (MemoComponentKind.fromKey(
                      widget.component.metadata['componentKind'],
                    ) ==
                    MemoComponentKind.graph)
                  DropdownButtonFormField<MemoGraphType>(
                    initialValue: _graphType,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: AppText.localize(context, '그래프 종류'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final type in MemoGraphType.values)
                        DropdownMenuItem(
                          value: type,
                          child: AppText(type.label),
                        ),
                    ],
                    onChanged: (type) {
                      if (type != null) setState(() => _graphType = type);
                    },
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const AppText('AI 보조 수정으로 버전 보관'),
                  value: _assisted,
                  onChanged: (value) =>
                      setState(() => _assisted = value ?? false),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _ComponentEdit(
                title: _title.text.trim(),
                content: _content.text,
                graphType: _graphType,
                assisted: _assisted,
              ),
            ),
            child: const AppText('저장'),
          ),
        ],
      );
}
