import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/knowledge_database.dart';
import '../domain/entities/directed_edge.dart';
import '../domain/entities/knowledge_node.dart';

class MemoWorkspaceScreen extends StatefulWidget {
  const MemoWorkspaceScreen({required this.store, super.key});

  final KnowledgeStore store;

  @override
  State<MemoWorkspaceScreen> createState() => _MemoWorkspaceScreenState();
}

class _MemoWorkspaceScreenState extends State<MemoWorkspaceScreen> {
  List<KnowledgeNode> _nodes = const [];
  List<DirectedEdge> _edges = const [];
  KnowledgeNode? _selected;
  KnowledgeNode? _secondarySelected;
  bool _selectionMode = false;
  bool _splitMode = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _drawerQuery = '';
  String _drawerSearchMode = '전체검색';
  String _leftSearchMode = '전체검색';
  String _rightSearchMode = '전체검색';
  String _leftQuery = '';
  String _rightQuery = '';
  final _selectedIds = <String>{};
  StreamSubscription<void>? _changesSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _changesSubscription = widget.store.changes.listen((_) => _load());
  }

  @override
  void dispose() {
    _changesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final nodes = await widget.store.listNodes();
    final edges = await widget.store.listEdges();
    if (!mounted) return;
    setState(() {
      _nodes = nodes
          .where((node) => node.mode == 'memo' || node.mode == 'plot')
          .toList();
      _edges = edges;
      _selected ??= _nodes.isEmpty ? null : _nodes.first;
    });
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
      '언어 미지정';

  String _dateLabel(KnowledgeNode node) {
    final date = node.createdAt.toLocal();
    return '${date.month.toString().padLeft(2, '0')}.'
        '${date.day.toString().padLeft(2, '0')}';
  }

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

  Future<void> _connectSelected() async {
    final selected = _nodes.where((node) => _selectedIds.contains(node.id));
    final list = selected.toList();
    final now = DateTime.now();
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        await widget.store.upsertEdge(
          DirectedEdge(
            id: const Uuid().v4(),
            fromId: list[i].id,
            toId: list[j].id,
            relation: 'related',
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }
    setState(() => _selectionMode = false);
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
    if (mounted) setState(() => _selectionMode = false);
  }

  Future<Map<String, String>?> _askManualRelation(
    KnowledgeNode first,
    KnowledgeNode second,
  ) async {
    final controller = TextEditingController(text: 'related');
    var direction = 'first';
    try {
      return await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('메모 관계 연결'),
            content: Column(
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
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(labelText: '관계명'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () {
                  final relation = controller.text.trim();
                  if (relation.isEmpty) return;
                  Navigator.of(dialogContext).pop({
                    'from': direction,
                    'relation': relation,
                  });
                },
                child: const Text('연결'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _createFileFromSelection() async {
    final list =
        _nodes.where((node) => _selectedIds.contains(node.id)).toList();
    if (list.length < 2) return;
    final now = DateTime.now();
    final fileId = const Uuid().v4();
    final title = list.map((node) => node.title).take(3).join(' · ');
    var html = '<!doctype html><html><head><meta charset="utf-8">'
        '<title>$title</title></head><body><h1>$title</h1>'
        '${list.map((node) => '<section><h2>${node.title}</h2><p>${node.content}</p></section>').join()}'
        '</body></html>';
    try {
      final model =
          FirebaseAI.googleAI().generativeModel(model: 'gemini-3.6-flash');
      final response = await model.generateContent([
        Content.text(
          'Create one clean semantic HTML document from these memos. '
          'Return HTML only, with headings and paragraphs:\n'
          '${list.map((node) => '${node.title}: ${node.content}').join('\n')}',
        ),
      ]);
      if (response.text != null && response.text!.contains('<html')) {
        html = response.text!
            .replaceFirst(RegExp(r'^```html\s*'), '')
            .replaceFirst(RegExp(r'\s*```$'), '');
      }
    } catch (_) {
      // The deterministic HTML remains available when AI is unavailable.
    }

    await widget.store.insertNode(
      KnowledgeNode(
        id: fileId,
        type: 'file',
        title: title,
        content: html,
        createdAt: now,
        updatedAt: now,
        metadata: const {'mode': 'file', 'format': 'html'},
      ),
    );
    for (final node in list) {
      await widget.store.upsertEdge(
        DirectedEdge(
          id: const Uuid().v4(),
          fromId: fileId,
          toId: node.id,
          relation: 'contains',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    if (mounted) {
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
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
      metadata: const {'mode': 'file', 'format': 'html', 'example': 'true'},
    );
    await widget.store.upsertNode(memoA);
    await widget.store.upsertNode(memoB);
    await widget.store.upsertNode(file);
    for (final memo in [memoA, memoB]) {
      await widget.store.upsertEdge(
        DirectedEdge(
          id: const Uuid().v4(),
          fromId: fileId,
          toId: memo.id,
          relation: 'contains',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  Future<void> _openFileLibrary() async {
    var files = (await widget.store.listNodes())
        .where((node) => node.type == 'file')
        .toList();
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
                files = (await widget.store.listNodes())
                    .where((node) => node.type == 'file')
                    .toList();
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
    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _buildSearchDrawer(),
      bottomNavigationBar: _selectionMode
          ? SafeArea(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 116,
                      child: FilledButton.icon(
                        onPressed: _selectedIds.length >= 2
                            ? _createFileFromSelection
                            : null,
                        icon: const Icon(Icons.create_new_folder_rounded),
                        label: const Text('파일', maxLines: 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 116,
                      child: FilledButton.tonalIcon(
                        onPressed:
                            _selectedIds.length >= 2 ? _manualConnect : null,
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('연결', maxLines: 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 116,
                      child: FilledButton.tonalIcon(
                        onPressed:
                            _selectedIds.length >= 2 ? _connectSelected : null,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: const Text('자동', maxLines: 1),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      appBar: AppBar(
        title: const Text('메모'),
        actions: [
          IconButton(
            tooltip: '메모 파일 다운로드',
            onPressed: _openFileLibrary,
            icon: const Icon(Icons.cloud_download_rounded),
          ),
          IconButton(
            tooltip: _splitMode ? '단일 화면' : '분할 화면',
            onPressed: () => setState(() => _splitMode = !_splitMode),
            icon: Icon(
              _splitMode
                  ? Icons.view_agenda_rounded
                  : Icons.view_sidebar_rounded,
            ),
          ),
          if (_selectionMode)
            IconButton(
              tooltip: '선택 취소',
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedIds.clear();
              }),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: _splitMode && isWide
          ? Row(
              children: [
                Expanded(
                  child: _buildPanel(
                    selected: _selected,
                    query: _leftQuery,
                    searchMode: _leftSearchMode,
                    onQueryChanged: (value) =>
                        setState(() => _leftQuery = value),
                    onSearchModeChanged: (value) =>
                        setState(() => _leftSearchMode = value),
                    onSearch: () => _executeSearch(_leftQuery, _leftSearchMode),
                    onSelected: (node) => setState(() => _selected = node),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _buildPanel(
                    selected: _secondarySelected,
                    query: _rightQuery,
                    searchMode: _rightSearchMode,
                    onQueryChanged: (value) =>
                        setState(() => _rightQuery = value),
                    onSearchModeChanged: (value) =>
                        setState(() => _rightSearchMode = value),
                    onSearch: () =>
                        _executeSearch(_rightQuery, _rightSearchMode),
                    onSelected: (node) =>
                        setState(() => _secondarySelected = node),
                  ),
                ),
              ],
            )
          : _buildPanel(
              selected: _selected,
              query: _leftQuery,
              searchMode: _leftSearchMode,
              onQueryChanged: (value) => setState(() => _leftQuery = value),
              onSearchModeChanged: (value) =>
                  setState(() => _leftSearchMode = value),
              onSearch: () => _executeSearch(_leftQuery, _leftSearchMode),
              onSelected: (node) => setState(() => _selected = node),
            ),
    );
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
    final similar =
        selected == null ? const <KnowledgeNode>[] : _similar(selected);
    final logical = selected == null
        ? const <MapEntry<KnowledgeNode, DirectedEdge>>[]
        : _logical(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
          child: Column(
            children: [
              Expanded(
                  child: _relationCarousel(
                similar,
                onSelected,
                selected == null
                    ? null
                    : (node) => _similarityLabel(selected, node),
                Icons.auto_awesome_rounded,
              )),
              Expanded(flex: 2, child: _selectedCard(selected)),
              Expanded(
                  child: _relationCarousel(
                logical.map((entry) => entry.key).toList(),
                onSelected,
                null,
                Icons.hub_rounded,
                relations: logical,
              )),
            ],
          ),
        ),
      ],
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
                              ? Checkbox(
                                  value: _selectedIds.contains(node.id),
                                  onChanged: (_) => setState(() {
                                    _selectedIds.contains(node.id)
                                        ? _selectedIds.remove(node.id)
                                        : _selectedIds.add(node.id);
                                  }),
                                )
                              : Icon(_modeIcon(node)),
                          title: Text(node.title),
                          subtitle: Text(node.content,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          onLongPress: () => setState(() {
                            _selectionMode = true;
                            _selectedIds.add(node.id);
                          }),
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
    return LayoutBuilder(
      builder: (context, constraints) => Card(
        margin: const EdgeInsets.all(12),
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
                  Text(_dateLabel(selected),
                      style: Theme.of(context).textTheme.bodySmall),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(selected.content)),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: constraints.maxWidth < 420 ? 100 : 150,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _languageLabel(selected),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                        const SizedBox(height: 8),
                        ...selected.tags.map(
                          (tag) => Text(
                            '#$tag',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
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
    return PageView.builder(
      controller: PageController(viewportFraction: 1),
      itemCount: pages.length,
      itemBuilder: (_, pageIndex) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: pages[pageIndex]
              .map(
                (node) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: node == pages[pageIndex].first ? 0 : 0.5,
                      right: node == pages[pageIndex].last ? 0 : 0.5,
                    ),
                    child: Card(
                      margin: EdgeInsets.zero,
                      elevation: 2,
                      shadowColor: Theme.of(context)
                          .colorScheme
                          .shadow
                          .withValues(alpha: 0.18),
                      color: accent == Icons.hub_rounded
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Theme.of(context).colorScheme.primaryContainer,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onLongPress: () => setState(() {
                          _selectionMode = true;
                          _selectedIds.add(node.id);
                        }),
                        onTap: () {
                          if (_selectionMode) {
                            setState(() {
                              _selectedIds.contains(node.id)
                                  ? _selectedIds.remove(node.id)
                                  : _selectedIds.add(node.id);
                            });
                          } else {
                            onSelected(node);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 6,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(_modeIcon(node), size: 18),
                                  const SizedBox(width: 2),
                                  Icon(
                                    accent,
                                    size: 16,
                                    color: accent == Icons.hub_rounded
                                        ? Theme.of(context)
                                            .colorScheme
                                            .secondary
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                  const Spacer(),
                                  if (_selectionMode)
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        visualDensity: VisualDensity.compact,
                                        value: _selectedIds.contains(node.id),
                                        onChanged: (_) => setState(() {
                                          _selectedIds.contains(node.id)
                                              ? _selectedIds.remove(node.id)
                                              : _selectedIds.add(node.id);
                                        }),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final title = Text(
                                    node.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  );
                                  final detailValue = relationById[node.id] ??
                                      (detail?.call(node) ?? '');
                                  final date = Text(
                                    _dateLabel(node),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  );
                                  final language = Text(
                                    _languageLabel(node),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  );
                                  return Row(
                                    children: [
                                      Expanded(child: title),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: accent == Icons.hub_rounded
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .secondary
                                                      .withValues(alpha: 0.14)
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.14),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              detailValue,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.end,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      SizedBox(
                                        width: constraints.maxWidth < 220
                                            ? 66
                                            : 92,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [date, language],
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
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
