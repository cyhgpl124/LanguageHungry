import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:langgry/features/knowledge/services/knowledge_database.dart';
import 'package:langgry/features/knowledge/services/memo_ai_service.dart';
import 'package:langgry/features/knowledge/models/directed_edge.dart';
import 'package:langgry/features/knowledge/models/knowledge_node.dart';
import 'package:langgry/features/knowledge/list/pages/dynamic_list_screen.dart';
import 'package:langgry/features/knowledge/plot/pages/plot_mode_screen.dart';
import 'package:langgry/features/knowledge/plot/widgets/plot_edit_dialog.dart';
import 'package:langgry/features/knowledge/workspace/pages/workspace_shell.dart';

enum _PlotAction { edit, delete }

class MemoWorkspaceScreen extends StatefulWidget {
  const MemoWorkspaceScreen({required this.store, super.key});

  final KnowledgeStore store;

  @override
  State<MemoWorkspaceScreen> createState() => _MemoWorkspaceScreenState();
}

class _MemoWorkspaceScreenState extends State<MemoWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  List<KnowledgeNode> _nodes = const [];
  List<KnowledgeNode> _plotNodes = const [];
  List<DirectedEdge> _edges = const [];
  KnowledgeNode? _selected;
  KnowledgeNode? _secondarySelected;
  bool _selectionMode = false;
  bool _splitMode = false;
  int _activeTab = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _drawerQuery = '';
  String _drawerSearchMode = '전체검색';
  String _leftSearchMode = '전체검색';
  String _rightSearchMode = '전체검색';
  String _leftQuery = '';
  String _rightQuery = '';
  final _selectedIds = <String>{};
  late final TabController _tabController;
  StreamSubscription<void>? _changesSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_syncActiveTab);
    _load();
    _changesSubscription = widget.store.changes.listen((_) => _load());
  }

  @override
  void dispose() {
    _changesSubscription?.cancel();
    _tabController
      ..removeListener(_syncActiveTab)
      ..dispose();
    super.dispose();
  }

  void _syncActiveTab() {
    if (_tabController.indexIsChanging ||
        _activeTab == _tabController.index ||
        !mounted) {
      return;
    }
    setState(() => _activeTab = _tabController.index);
  }

  void _syncSelectionModeVisibility() {
    SelectionModeScope.update(context, _selectionMode);
  }

  Future<void> _load() async {
    final nodes = await widget.store.listNodes();
    final edges = await widget.store.listEdges();
    if (!mounted) return;
    final memos = nodes.where((node) => node.mode == 'memo').toList();
    final plots = nodes.where((node) => node.mode == 'plot').toList();
    final currentSelectedId = _selected?.id;
    final currentSecondaryId = _secondarySelected?.id;
    setState(() {
      _nodes = memos;
      _plotNodes = plots;
      _edges = edges;
      _selected = _firstWhereOrNull(
            memos,
            (node) => node.id == currentSelectedId,
          ) ??
          _firstWhereOrNull(memos, (_) => true);
      _secondarySelected = _firstWhereOrNull(
            memos,
            (node) => node.id == currentSecondaryId && node.id != _selected?.id,
          ) ??
          _firstWhereOrNull(memos, (node) => node.id != _selected?.id);
    });
  }

  KnowledgeNode? _firstWhereOrNull(
    Iterable<KnowledgeNode> nodes,
    bool Function(KnowledgeNode) test,
  ) {
    for (final node in nodes) {
      if (test(node)) return node;
    }
    return null;
  }

  List<KnowledgeNode> _similar(KnowledgeNode selected) {
    final candidates = _nodes.where((node) => node.id != selected.id).toList();
    candidates.sort((a, b) => _distance(selected.embedding, a.embedding)
        .compareTo(_distance(selected.embedding, b.embedding)));
    return candidates;
  }

  List<MapEntry<KnowledgeNode, DirectedEdge>> _logical(
    KnowledgeNode selected,
  ) {
    final result = <MapEntry<KnowledgeNode, DirectedEdge>>[];
    for (final edge in _edges.where(
        (edge) => edge.fromId == selected.id || edge.toId == selected.id)) {
      final id = edge.fromId == selected.id ? edge.toId : edge.fromId;
      final node = _nodes.cast<KnowledgeNode?>().firstWhere(
            (candidate) => candidate?.id == id,
            orElse: () => null,
          );
      if (node != null) result.add(MapEntry(node, edge));
    }
    return result;
  }

  KnowledgeNode? _hierarchyParent(KnowledgeNode selected) {
    final parentId = selected.metadata['parentId'];
    if (parentId == null) return null;
    return _firstWhereOrNull(_nodes, (node) => node.id == parentId);
  }

  List<KnowledgeNode> _search(String query, String searchMode) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return _nodes;
    return _nodes.where((node) {
      return switch (searchMode) {
        '태그검색' =>
          node.tags.any((tag) => tag.toLowerCase().contains(normalized)),
        '제목검색' => node.title.toLowerCase().contains(normalized),
        '내용검색' => node.content.toLowerCase().contains(normalized),
        _ => node.title.toLowerCase().contains(normalized) ||
            node.content.toLowerCase().contains(normalized) ||
            node.tags.any((tag) => tag.toLowerCase().contains(normalized)),
      };
    }).toList();
  }

  String _similarityLabel(KnowledgeNode selected, KnowledgeNode node) {
    final distance = _distance(selected.embedding, node.embedding);
    if (!distance.isFinite) return '유사도 정보 없음';
    final percent = ((1 - distance).clamp(0.0, 1.0) * 100).round();
    return '유사도 $percent%';
  }

  String _modeLabel(KnowledgeNode node) => switch (node.mode) {
        'plot' => '플롯',
        'list' => '리스트',
        'file' => '파일',
        _ => '메모',
      };

  IconData _modeIcon(KnowledgeNode node) => switch (node.mode) {
        'plot' => Icons.auto_graph_rounded,
        'list' => Icons.table_chart_rounded,
        'file' => Icons.folder_rounded,
        _ => Icons.sticky_note_2_rounded,
      };

  String _languageLabel(KnowledgeNode node) =>
      node.metadata['language'] ??
      node.metadata['언어'] ??
      node.metadata['activeLearningLanguage'] ??
      detectMemoLanguage('${node.title} ${node.content}');

  String _dateLabel(DateTime value) {
    final date = value.toLocal();
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _levelLabel(KnowledgeNode node) =>
      '${node.metadata['level'] ?? '1'}단계 메모';

  List<List<KnowledgeNode>> _pages(List<KnowledgeNode> nodes) {
    final pages = <List<KnowledgeNode>>[];
    for (var index = 0; index < nodes.length; index += 3) {
      pages.add(nodes.skip(index).take(3).toList());
    }
    return pages;
  }

  void _executeSearch(String query, String mode) {
    setState(() {
      _drawerQuery = query;
      _drawerSearchMode = mode;
    });
    _scaffoldKey.currentState?.openEndDrawer();
  }

  double _distance(List<double>? a, List<double>? b) {
    if (a == null || b == null || a.length != b.length) return double.infinity;
    var dot = 0.0;
    var aa = 0.0;
    var bb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      aa += a[i] * a[i];
      bb += b[i] * b[i];
    }
    final denominator = math.sqrt(aa) * math.sqrt(bb);
    return denominator == 0 ? double.infinity : 1 - dot / denominator;
  }

  Future<void> _manualConnect() async {
    final list =
        _nodes.where((node) => _selectedIds.contains(node.id)).toList();
    if (list.length < 2) return;
    final now = DateTime.now();
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final result = await _askManualRelation(list[i], list[j]);
        if (result == null) return;
        await widget.store.upsertEdge(
          DirectedEdge(
            id: const Uuid().v4(),
            fromId: result['from'] == 'first' ? list[i].id : list[j].id,
            toId: result['from'] == 'first' ? list[j].id : list[i].id,
            relation: result['relation']!,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _selectionMode = false);
      _syncSelectionModeVisibility();
    }
  }

  void _selectActiveMemo(KnowledgeNode node) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..add(node.id);
    });
    _syncSelectionModeVisibility();
  }

  void _toggleMemoSelection(KnowledgeNode node) {
    setState(() {
      _selectionMode = true;
      if (!_selectedIds.add(node.id)) {
        _selectedIds.remove(node.id);
      }
    });
    _syncSelectionModeVisibility();
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedIds.clear();
    });
    _syncSelectionModeVisibility();
  }

  Future<void> _editActiveMemo() async {
    final node = _selected;
    if (node == null || !_selectedIds.contains(node.id)) return;
    final titleController = TextEditingController(text: node.title);
    final contentController = TextEditingController(text: node.content);
    Map<String, String>? result;
    try {
      result = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('메모 수정'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  maxLength: 10,
                  decoration: const InputDecoration(labelText: '제목'),
                ),
                TextField(
                  controller: contentController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: '메모 본문',
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
                Navigator.of(dialogContext).pop({
                  'title': title,
                  'content': content,
                });
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
    if (result == null) return;
    final title = result['title']!;
    final content = result['content']!;
    try {
      final analysis = await MemoAiService().analyze(title, content);
      final typedTags = RegExp(r'#([^\s#]+)')
          .allMatches(content)
          .map((match) =>
              match.group(1)!.replaceAll(RegExp(r'[.,!?;:)\]}]+$'), ''))
          .where((tag) => tag.isNotEmpty);
      final now = DateTime.now();
      await widget.store.upsertNode(
        node.copyWith(
          title: title,
          content: content,
          updatedAt: now,
          tags: <String>{...analysis.tags, ...typedTags}.toList(),
          embedding: analysis.embedding,
          metadata: {...node.metadata, 'language': analysis.language},
        ),
      );
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메모 수정 실패: ${error.message ?? error.code}')),
        );
      }
      return;
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메모 수정 실패: $error')),
        );
      }
      return;
    }
    if (mounted) {
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      _syncSelectionModeVisibility();
    }
  }

  Future<void> _deleteActiveMemo() async {
    final node = _selected;
    if (node == null || !_selectedIds.contains(node.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('메모 삭제'),
        content: Text('"${node.title}" 메모와 연결된 관계를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.deleteNode(node.id);
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메모 삭제 실패: ${error.message ?? error.code}')),
        );
      }
      return;
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메모 삭제 실패: $error')),
        );
      }
      return;
    }
    if (mounted) {
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
        _selected = null;
      });
      _syncSelectionModeVisibility();
    }
  }

  Future<Map<String, String>?> _askManualRelation(
    KnowledgeNode first,
    KnowledgeNode second,
  ) async {
    var direction = 'first';
    var relation = '상관관계';
    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('메모 관계 연결'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${first.title}  ↔  ${second.title}'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: direction,
                  decoration: const InputDecoration(labelText: '방향'),
                  items: [
                    DropdownMenuItem(
                      value: 'first',
                      child: Text('${first.title} → ${second.title}'),
                    ),
                    DropdownMenuItem(
                      value: 'second',
                      child: Text('${second.title} → ${first.title}'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => direction = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: relation,
                  decoration: const InputDecoration(labelText: '논리 관계'),
                  items: const [
                    DropdownMenuItem(value: '인과관계', child: Text('인과관계')),
                    DropdownMenuItem(value: '상관관계', child: Text('상관관계')),
                    DropdownMenuItem(value: '포함관계', child: Text('포함관계')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => relation = value);
                  },
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
              onPressed: () => Navigator.of(dialogContext).pop({
                'from': direction,
                'relation': relation,
              }),
              child: const Text('연결'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createFileFromSelection() async {
    final list =
        _nodes.where((node) => _selectedIds.contains(node.id)).toList();
    if (list.isEmpty) return;
    var category = '';
    final selectedCategory = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('파일 분류'),
        content: SizedBox(
          width: 400,
          child: TextField(
            autofocus: true,
            onChanged: (value) => category = value,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.of(dialogContext).pop(value.trim());
              }
            },
            decoration: const InputDecoration(
              labelText: '분류명',
              hintText: '예: 영어, 여행, 업무',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final value = category.trim();
              if (value.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('분류를 입력해 주세요.')),
                );
                return;
              }
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('파일 만들기'),
          ),
        ],
      ),
    );
    if (selectedCategory == null) return;
    if (!mounted) return;
    final now = DateTime.now();
    final fileId = const Uuid().v4();
    final title = list.map((node) => node.title).take(3).join(' · ');
    const escapeHtml = HtmlEscape();
    final html = '<!doctype html><html lang="ko"><head>'
        '<meta charset="utf-8"><meta name="viewport" '
        'content="width=device-width, initial-scale=1">'
        '<title>${escapeHtml.convert(title)}</title><style>'
        'body{margin:0;padding:32px;background:#f4f6fb;color:#202638;'
        'font-family:Arial,sans-serif;font-size:16px;line-height:1.75}'
        'main{max-width:820px;margin:0 auto;padding:32px;background:#fff;'
        'border-radius:20px;box-shadow:0 8px 28px #17255418}'
        'h1{margin:0 0 28px;color:#3447a8;font-size:30px;font-weight:800}'
        'section{margin:0 0 20px;padding:20px 22px;border-left:5px solid '
        '#6878dc;background:#f7f8ff;border-radius:8px}'
        'h1{margin:0 0 12px;color:#3447a8;font-size:26px;font-weight:800}'
        'h2{margin:0 0 10px;color:#3849a0;font-size:21px;font-weight:700}'
        'h3{margin:0 0 8px;color:#4d5bad;font-size:18px;font-weight:700}'
        'p{margin:0;color:#343b4d;font-size:16px;white-space:pre-wrap}'
        '</style></head><body><main><header>'
        '<strong>${escapeHtml.convert(title)}</strong>'
        '<span> · ${escapeHtml.convert(selectedCategory)}</span></header>'
        '${list.map((node) {
      final level = int.tryParse(node.metadata['level'] ?? '1') ?? 1;
      final headingTag = switch (level.clamp(1, 3)) {
        1 => 'h1',
        2 => 'h2',
        _ => 'h3',
      };
      final paragraphs = node.content
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) => '<p>${escapeHtml.convert(line)}</p>')
          .join();
      return '<section><$headingTag>${escapeHtml.convert(node.title)}</$headingTag>'
          '$paragraphs</section>';
    }).join()}'
        '</main></body></html>';

    await widget.store.upsertFile(
      KnowledgeNode(
        id: fileId,
        type: 'file',
        title: title,
        content: html,
        createdAt: now,
        updatedAt: now,
        metadata: {
          'mode': 'file',
          'format': 'html',
          'category': selectedCategory,
          'schemaVersion': '2',
        },
      ),
    );
    final savedFiles = await widget.store.listFiles();
    if (!savedFiles.any((file) => file.id == fileId)) {
      throw StateError('파일 저장은 완료됐지만 파일 목록에서 확인되지 않습니다.');
    }
    if (mounted) {
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      _syncSelectionModeVisibility();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택한 메모로 파일을 만들었습니다.')),
      );
    }
  }

  Future<void> _createExampleFile() async {
    final now = DateTime.now();
    final fileId = const Uuid().v4();
    final memoA = KnowledgeNode(
      id: const Uuid().v4(),
      type: 'memo',
      title: 'Japanese greetings',
      content: 'おはようございます is used in the morning.',
      createdAt: now,
      updatedAt: now,
      tags: const ['Japanese', 'greetings'],
    );
    final memoB = KnowledgeNode(
      id: const Uuid().v4(),
      type: 'memo',
      title: 'Polite expressions',
      content: 'ありがとうございます is a polite way to say thank you.',
      createdAt: now,
      updatedAt: now,
      tags: const ['Japanese', 'polite'],
    );
    final file = KnowledgeNode(
      id: fileId,
      type: 'file',
      title: 'Japanese starter memo file',
      content: '<!doctype html><html><body><h1>Japanese starter memo file</h1>'
          '<h2>Japanese greetings</h2><p>${memoA.content}</p>'
          '<h2>Polite expressions</h2><p>${memoB.content}</p>'
          '</body></html>',
      createdAt: now,
      updatedAt: now,
      metadata: const {
        'mode': 'file',
        'format': 'html',
        'category': '일본어',
        'example': 'true',
      },
    );
    await widget.store.upsertNode(memoA);
    await widget.store.upsertNode(memoB);
    await widget.store.upsertFile(file);
  }

  Future<void> _openFileLibrary() async {
    var files = await widget.store.listFiles();
    if (!mounted) return;
    final selectedFile = await showDialog<KnowledgeNode>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('메모 파일 가져오기'),
          content: SizedBox(
            width: 520,
            child: files.isEmpty
                ? const Text('저장된 메모 파일이 없습니다.')
                : ListView(
                    shrinkWrap: true,
                    children: files
                        .map(
                          (file) => ListTile(
                            leading: const Icon(Icons.folder_rounded),
                            title: Text(file.title),
                            subtitle: Text(
                              file.updatedAt.toLocal().toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.download_rounded),
                            onTap: () => Navigator.of(dialogContext).pop(file),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await _createExampleFile();
                files = await widget.store.listFiles();
                if (dialogContext.mounted) setDialogState(() {});
              },
              icon: const Icon(Icons.science_rounded),
              label: const Text('예시 파일'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selectedFile == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${selectedFile.title}을(를) 가져왔습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final activeMemoSelected =
        _selected != null && _selectedIds.contains(_selected!.id);
    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _buildSearchDrawer(),
      floatingActionButton: _selectionMode && _activeTab == 0
          ? SafeArea(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'memo-selection-relate',
                    tooltip: '논리관계 추가',
                    onPressed: _selectedIds.length >= 2 ? _manualConnect : null,
                    child: const Icon(Icons.hub_rounded),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: 'memo-selection-edit',
                    tooltip: '수정',
                    onPressed: activeMemoSelected ? _editActiveMemo : null,
                    child: const Icon(Icons.edit_rounded),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: 'memo-selection-delete',
                    tooltip: '삭제',
                    onPressed: activeMemoSelected ? _deleteActiveMemo : null,
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: 'memo-selection-file',
                    tooltip: '파일 만들기',
                    onPressed: _selectedIds.isNotEmpty
                        ? _createFileFromSelection
                        : null,
                    child: const Icon(Icons.create_new_folder_rounded),
                  ),
                ],
              ),
            )
          : null,
      appBar: AppBar(
        title: const Text('메모'),
        actions: _activeTab == 0
            ? [
                IconButton(
                  tooltip: '메모 파일 다운로드',
                  onPressed: _openFileLibrary,
                  icon: const Icon(Icons.cloud_download_rounded),
                ),
                IconButton(
                  tooltip: _splitMode ? '단일 화면' : '분할 화면',
                  onPressed: () => setState(() {
                    _splitMode = !_splitMode;
                    _secondarySelected ??= _firstWhereOrNull(
                      _nodes,
                      (node) => node.id != _selected?.id,
                    );
                  }),
                  icon: Icon(
                    _splitMode
                        ? Icons.view_agenda_rounded
                        : Icons.view_sidebar_rounded,
                  ),
                ),
                IconButton(
                  tooltip: _selectionMode ? '선택 취소' : '메모 선택',
                  onPressed: _toggleSelectionMode,
                  icon: Icon(
                    _selectionMode ? Icons.close : Icons.checklist_rounded,
                  ),
                ),
              ]
            : null,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '메모 모드', icon: Icon(Icons.sticky_note_2_outlined)),
            Tab(text: '리스트 모드', icon: Icon(Icons.table_chart_outlined)),
            Tab(text: '플롯 모드', icon: Icon(Icons.auto_graph_rounded)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMemoTab(isWide),
          DynamicListScreen(store: widget.store, embedded: true),
          _buildPlotTab(),
        ],
      ),
    );
  }

  Widget _buildMemoTab(bool isWide) {
    if (_nodes.isEmpty) {
      return const Center(child: Text('저장된 메모가 없습니다. + 버튼으로 메모를 추가해 주세요.'));
    }
    final firstPanel = _buildPanel(
      selected: _selected,
      query: _leftQuery,
      searchMode: _leftSearchMode,
      onQueryChanged: (value) => setState(() => _leftQuery = value),
      onSearchModeChanged: (value) => setState(() => _leftSearchMode = value),
      onSearch: () => _executeSearch(_leftQuery, _leftSearchMode),
      onSelected: (node) => setState(() {
        if (node.id == _secondarySelected?.id) {
          _secondarySelected = _selected;
        }
        _selected = node;
      }),
    );
    if (!_splitMode) return firstPanel;

    final secondPanel = _secondarySelected == null
        ? const Center(child: Text('분할 화면에 표시할 두 번째 메모가 없습니다.'))
        : _buildPanel(
            selected: _secondarySelected,
            query: _rightQuery,
            searchMode: _rightSearchMode,
            onQueryChanged: (value) => setState(() => _rightQuery = value),
            onSearchModeChanged: (value) =>
                setState(() => _rightSearchMode = value),
            onSearch: () => _executeSearch(_rightQuery, _rightSearchMode),
            onSelected: (node) => setState(() {
              if (node.id == _selected?.id) {
                _selected = _secondarySelected;
              }
              _secondarySelected = node;
            }),
          );
    return isWide
        ? Row(
            children: [
              Expanded(child: firstPanel),
              const VerticalDivider(width: 1),
              Expanded(child: secondPanel),
            ],
          )
        : Column(
            children: [
              Expanded(child: firstPanel),
              const Divider(height: 1),
              Expanded(child: secondPanel),
            ],
          );
  }

  Widget _buildPlotTab() {
    final size = MediaQuery.sizeOf(context);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(size.width * 0.01),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlotModeScreen(store: widget.store),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('플롯 생성'),
            ),
          ),
        ),
        Expanded(
          child: _plotNodes.isEmpty
              ? const Center(child: Text('저장된 플롯이 없습니다. 플롯을 생성해 주세요.'))
              : GridView.builder(
                  padding: EdgeInsets.all(size.width * 0.02),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    mainAxisExtent: 112,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _plotNodes.length,
                  itemBuilder: (context, index) {
                    final node = _plotNodes[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _showPlotDetails(node),
                        onLongPress: () => _showPlotActions(node),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_graph_rounded),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  node.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showPlotDetails(KnowledgeNode node) {
    final size = MediaQuery.sizeOf(context);
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: size.width - 32 < 760 ? size.width - 32 : 760,
            maxHeight: size.height - 48 < 700 ? size.height - 48 : 700,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(node.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      node.content,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('닫기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPlotActions(KnowledgeNode node) async {
    final action = await showModalBottomSheet<_PlotAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('수정'),
              onTap: () => Navigator.pop(context, _PlotAction.edit),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '삭제',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, _PlotAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == _PlotAction.edit) {
      await _editPlot(node);
    } else if (action == _PlotAction.delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('플롯 삭제'),
          content: Text('"${node.title}" 플롯을 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        await widget.store.deleteNode(node.id);
        await _load();
      }
    }
  }

  Future<void> _editPlot(KnowledgeNode node) async {
    final updated = await showDialog<KnowledgeNode>(
      context: context,
      builder: (_) => PlotEditDialog(node: node),
    );
    if (updated == null || !mounted) return;
    await widget.store.upsertNode(updated);
    await _load();
  }

  Widget _buildPanel({
    required KnowledgeNode? selected,
    required String query,
    required String searchMode,
    required ValueChanged<String> onQueryChanged,
    required ValueChanged<String> onSearchModeChanged,
    required VoidCallback onSearch,
    required ValueChanged<KnowledgeNode> onSelected,
  }) {
    final parent = selected == null ? null : _hierarchyParent(selected);
    final similar = selected == null
        ? const <KnowledgeNode>[]
        : parent == null
            ? _similar(selected)
            : [parent];
    final logical = selected == null
        ? const <MapEntry<KnowledgeNode, DirectedEdge>>[]
        : _logical(selected);
    final childEntries = selected == null
        ? const <MapEntry<KnowledgeNode, DirectedEdge>>[]
        : logical
            .where((entry) => entry.key.metadata['parentId'] == selected.id)
            .toList();
    final bottomEntries = childEntries.isNotEmpty
        ? childEntries
        : logical.where((entry) => entry.key.id != parent?.id).toList();
    final size = MediaQuery.sizeOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: size.width * 0.01,
        vertical: size.height * 0.01,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              size.width * 0.01,
              size.height * 0.01,
              size.width * 0.01,
              size.height * 0.005,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: onQueryChanged,
                    onSubmitted: (_) => onSearch(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: '메모 검색',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () => onQueryChanged(''),
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: searchMode,
                  items: const [
                    DropdownMenuItem(value: '전체검색', child: Text('전체검색')),
                    DropdownMenuItem(value: '태그검색', child: Text('태그검색')),
                    DropdownMenuItem(value: '제목검색', child: Text('제목검색')),
                    DropdownMenuItem(value: '내용검색', child: Text('내용검색')),
                  ],
                  onChanged: (value) {
                    if (value != null) onSearchModeChanged(value);
                  },
                ),
                IconButton(
                  tooltip: '검색 실행',
                  onPressed: onSearch,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final carouselCount =
                    (similar.isEmpty ? 0 : 1) + (bottomEntries.isEmpty ? 0 : 1);
                final carouselHeight = carouselCount == 0
                    ? 0.0
                    : math.min(
                        56.0,
                        constraints.maxHeight / (carouselCount + 1),
                      );
                return Column(
                  children: [
                    if (similar.isNotEmpty)
                      SizedBox(
                        height: carouselHeight,
                        child: _relationCarousel(
                          similar,
                          onSelected,
                          selected == null
                              ? null
                              : (node) => _similarityLabel(selected, node),
                          Icons.auto_awesome_rounded,
                        ),
                      ),
                    Expanded(child: _selectedCard(selected)),
                    if (bottomEntries.isNotEmpty)
                      SizedBox(
                        height: carouselHeight,
                        child: _relationCarousel(
                          bottomEntries.map((entry) => entry.key).toList(),
                          onSelected,
                          null,
                          Icons.hub_rounded,
                          relations: bottomEntries,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchDrawer() {
    final results = _search(_drawerQuery, _drawerSearchMode);
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('찾기',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? const Center(child: Text('검색 결과가 없습니다.'))
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, index) {
                        final node = results[index];
                        return ListTile(
                          leading: _selectionMode
                              ? Icon(
                                  _selectedIds.contains(node.id)
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  color: _selectedIds.contains(node.id)
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                )
                              : Icon(_modeIcon(node)),
                          title: Text(node.title),
                          subtitle: Text(node.content,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          onLongPress: () {
                            setState(() {
                              _selectionMode = true;
                              _selectedIds.add(node.id);
                            });
                            _syncSelectionModeVisibility();
                          },
                          onTap: () {
                            if (_selectionMode) {
                              setState(() {
                                _selectedIds.contains(node.id)
                                    ? _selectedIds.remove(node.id)
                                    : _selectedIds.add(node.id);
                              });
                            } else {
                              setState(() => _selected = node);
                              Navigator.of(context).pop();
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectedCard(KnowledgeNode? selected) {
    if (selected == null) {
      return const Center(child: Text('메모를 선택해 주세요.'));
    }
    final size = MediaQuery.sizeOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => Card(
        margin: EdgeInsets.symmetric(
          horizontal: size.width * 0.005,
          vertical: size.height * 0.005,
        ),
        child: InkWell(
          onLongPress: () {
            if (_selectionMode) {
              _toggleMemoSelection(selected);
            } else {
              _selectActiveMemo(selected);
            }
          },
          onTap: _selectionMode ? () => _toggleMemoSelection(selected) : null,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(constraints.maxWidth < 420 ? 12 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_modeIcon(selected), size: 22),
                    const SizedBox(width: 8),
                    Text(_modeLabel(selected),
                        style: Theme.of(context).textTheme.labelLarge),
                    const Spacer(),
                    Text(_levelLabel(selected),
                        style: Theme.of(context).textTheme.labelMedium),
                    if (_selectionMode) ...[
                      const SizedBox(width: 8),
                      Icon(
                        _selectedIds.contains(selected.id)
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        color: _selectedIds.contains(selected.id)
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  selected.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                SelectableText(selected.content),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text('생성 ${_dateLabel(selected.createdAt)}'),
                    Text('수정 ${_dateLabel(selected.updatedAt)}'),
                    Text(_languageLabel(selected)),
                    ...selected.tags.map((tag) => Text('#$tag')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _relationCarousel(
    List<KnowledgeNode> nodes,
    ValueChanged<KnowledgeNode> onSelected,
    String Function(KnowledgeNode)? detail,
    IconData accent, {
    List<MapEntry<KnowledgeNode, DirectedEdge>> relations =
        const <MapEntry<KnowledgeNode, DirectedEdge>>[],
  }) {
    if (nodes.isEmpty) {
      return const SizedBox.shrink();
    }
    final relationById = {
      for (final entry in relations) entry.key.id: entry.value.relation,
    };
    final pages = _pages(nodes);
    final screenSize = MediaQuery.sizeOf(context);
    return PageView.builder(
      itemCount: pages.length,
      itemBuilder: (_, pageIndex) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: pages[pageIndex]
              .map(
                (node) => Expanded(
                  child: Card(
                    margin: EdgeInsets.symmetric(
                      horizontal: screenSize.width * 0.005,
                      vertical: screenSize.height * 0.005,
                    ),
                    elevation: 2,
                    shadowColor: Theme.of(context)
                        .colorScheme
                        .shadow
                        .withValues(alpha: 0.18),
                    color: accent == Icons.hub_rounded
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Theme.of(context).colorScheme.primaryContainer,
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(
                      builder: (context, cardConstraints) {
                        final narrow = cardConstraints.maxWidth < 180;
                        final tight = cardConstraints.maxHeight < 82;
                        final titleSize = tight
                            ? 10.0
                            : narrow
                                ? 11.0
                                : 13.0;
                        final labelStyle =
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontSize: tight
                                      ? 9
                                      : narrow
                                          ? 10
                                          : 11,
                                  height: 1,
                                );
                        final detailValue =
                            relationById[node.id] ?? (detail?.call(node) ?? '');
                        final dateLabel = narrow
                            ? '${_dateLabel(node.createdAt)} '
                                '(${_dateLabel(node.updatedAt)})'
                            : '생성 ${_dateLabel(node.createdAt)} '
                                '(수정 ${_dateLabel(node.updatedAt)})';
                        return InkWell(
                          onLongPress: () => _toggleMemoSelection(node),
                          onTap: () {
                            if (_selectionMode) {
                              _toggleMemoSelection(node);
                            } else {
                              onSelected(node);
                            }
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: narrow ? 5 : 8,
                              vertical: tight ? 2 : 4,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(_modeIcon(node),
                                        size: narrow ? 14 : 16),
                                    SizedBox(width: narrow ? 3 : 5),
                                    Expanded(
                                      child: Text(
                                        node.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: titleSize,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(
                                      accent,
                                      size: narrow ? 13 : 15,
                                      color: accent == Icons.hub_rounded
                                          ? Theme.of(context)
                                              .colorScheme
                                              .secondary
                                          : Theme.of(context)
                                              .colorScheme
                                              .primary,
                                    ),
                                    if (_selectionMode) ...[
                                      const SizedBox(width: 3),
                                      Icon(
                                        _selectedIds.contains(node.id)
                                            ? Icons.check_box_rounded
                                            : Icons
                                                .check_box_outline_blank_rounded,
                                        size: narrow ? 16 : 18,
                                        color: _selectedIds.contains(node.id)
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : null,
                                      ),
                                    ],
                                  ],
                                ),
                                SizedBox(height: tight ? 1 : 3),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        detailValue,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: labelStyle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        _languageLabel(node),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.end,
                                        style: labelStyle,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _levelLabel(node),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: labelStyle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        dateLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.end,
                                        style: labelStyle,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
