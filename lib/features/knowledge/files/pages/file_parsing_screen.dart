import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:uuid/uuid.dart';

import 'package:langgry/features/knowledge/models/knowledge_node.dart';
import 'package:langgry/features/knowledge/services/knowledge_database.dart';
import 'package:langgry/features/knowledge/files/pages/html_preview_page.dart';

enum _DuplicateFileAction { overwrite, rename, cancel }

enum _FileAction { edit, delete }

class FileParsingScreen extends StatefulWidget {
  const FileParsingScreen({required this.store, super.key});

  final KnowledgeStore store;

  @override
  State<FileParsingScreen> createState() => _FileParsingScreenState();
}

class _FileParsingScreenState extends State<FileParsingScreen> {
  bool _busy = false;
  bool _loadingFiles = true;
  String? _fileName;
  int _createdCount = 0;
  List<KnowledgeNode> _files = const [];
  String? _loadError;
  String _searchQuery = '';
  String _selectedCategory = '전체';
  int _fileLoadVersion = 0;
  int _displayLimit = 20;
  final ScrollController _fileScrollController = ScrollController();
  StreamSubscription<void>? _changesSubscription;

  @override
  void initState() {
    super.initState();
    _fileScrollController.addListener(_loadMoreWhenNeeded);
    _loadFiles();
    _changesSubscription = widget.store.changes.listen((_) => _loadFiles());
  }

  @override
  void dispose() {
    _changesSubscription?.cancel();
    _fileScrollController.dispose();
    super.dispose();
  }

  void _loadMoreWhenNeeded() {
    if (!_fileScrollController.hasClients ||
        _fileScrollController.position.extentAfter > 200 ||
        _displayLimit >= _files.length) {
      return;
    }
    setState(() {
      _displayLimit = (_displayLimit + 20).clamp(0, _files.length).toInt();
    });
  }

  Future<void> _loadFiles() async {
    final requestVersion = ++_fileLoadVersion;
    try {
      final nodes = await widget.store.listFiles();
      if (requestVersion != _fileLoadVersion || !mounted) return;
      setState(() {
        _files = nodes.map(categorizedFile).toList();
        _displayLimit = _files.length < 20
            ? _files.length
            : _displayLimit.clamp(20, _files.length).toInt();
        _loadError = null;
        _loadingFiles = false;
      });
    } on FirebaseException catch (error) {
      if (requestVersion != _fileLoadVersion || !mounted) return;
      setState(() {
        _loadError = error.message ?? error.code;
        _loadingFiles = false;
      });
    } on StateError catch (error) {
      if (requestVersion != _fileLoadVersion || !mounted) return;
      setState(() {
        _loadError = error.message;
        _loadingFiles = false;
      });
    }
  }

  Future<void> _pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['html', 'htm'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    final file = result!.files.single;
    var title = file.name;
    KnowledgeNode? overwriteTarget;
    while (true) {
      final duplicate = _files.cast<KnowledgeNode?>().firstWhere(
            (saved) =>
                saved != null &&
                saved.title.trim().toLowerCase() == title.trim().toLowerCase(),
            orElse: () => null,
          );
      if (duplicate == null) break;
      final action = await _askDuplicateAction(title);
      if (!mounted || action == null || action == _DuplicateFileAction.cancel) {
        return;
      }
      if (action == _DuplicateFileAction.overwrite) {
        overwriteTarget = duplicate;
        break;
      }
      final renamed = await _askFileTitle(title);
      if (!mounted || renamed == null) return;
      title = renamed;
    }
    final category = await _askCategory();
    if (category == null || !mounted) return;
    setState(() {
      _busy = true;
      _fileName = title;
    });
    try {
      final sourceHtml = utf8.decode(bytes);
      final now = DateTime.now();
      await widget.store.upsertFile(
        KnowledgeNode(
          id: overwriteTarget?.id ?? const Uuid().v4(),
          type: 'file',
          title: title,
          content: sourceHtml,
          createdAt: overwriteTarget?.createdAt ?? now,
          updatedAt: now,
          tags: overwriteTarget?.tags ?? const [],
          embedding: overwriteTarget?.embedding,
          metadata: {
            ...?overwriteTarget?.metadata,
            'mode': 'file',
            'format': 'html',
            'category': category,
            'schemaVersion': '2',
          },
        ),
      );
      await _loadFiles();
      if (mounted) setState(() => _createdCount = 0);
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('UTF-8로 인코딩된 HTML 파일만 가져올 수 있습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_DuplicateFileAction?> _askDuplicateAction(String title) {
    return showDialog<_DuplicateFileAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('같은 제목의 파일이 있습니다'),
        content: Text('“$title” 파일을 어떻게 처리할까요?'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_DuplicateFileAction.cancel),
            child: const Text('업로드 취소'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_DuplicateFileAction.rename),
            child: const Text('이름 바꿔서 업로드'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_DuplicateFileAction.overwrite),
            child: const Text('덮어쓰기'),
          ),
        ],
      ),
    );
  }

  Future<String?> _askFileTitle(String initialTitle) async {
    final controller = TextEditingController(text: initialTitle);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('파일 제목 변경'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '제목',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              final title = value.trim();
              if (title.isNotEmpty) Navigator.of(dialogContext).pop(title);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final title = controller.text.trim();
                if (title.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('제목을 입력해 주세요.')),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(title);
              },
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _askCategory() async {
    var category = _selectedCategory == '전체' ? '' : _selectedCategory;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('파일 분류'),
        content: SizedBox(
          width: 400,
          child: TextField(
            autofocus: true,
            onChanged: (value) => category = value,
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
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFileActions(KnowledgeNode file) async {
    final action = await showModalBottomSheet<_FileAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('제목·분류 수정'),
              onTap: () => Navigator.of(sheetContext).pop(_FileAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('삭제'),
              onTap: () => Navigator.of(sheetContext).pop(_FileAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == _FileAction.edit) {
      await _editFile(file);
    } else if (action == _FileAction.delete) {
      await _confirmDeleteFile(file);
    }
  }

  Future<void> _editFile(KnowledgeNode file) async {
    final titleController = TextEditingController(text: file.title);
    final categoryController =
        TextEditingController(text: fileCategoryOf(file));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('파일 정보 수정'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(
                    labelText: '분류',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty ||
                    categoryController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('제목과 분류를 입력해 주세요.')),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('저장'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final updated = file.copyWith(
        title: titleController.text.trim(),
        updatedAt: DateTime.now(),
        metadata: {
          ...file.metadata,
          'category': categoryController.text.trim(),
        },
      );
      await widget.store.upsertFile(updated);
      await _loadFiles();
    } on FirebaseException catch (error) {
      _showFileOperationError(error.message ?? error.code);
    } on StateError catch (error) {
      _showFileOperationError(error.message);
    } finally {
      titleController.dispose();
      categoryController.dispose();
    }
  }

  Future<void> _confirmDeleteFile(KnowledgeNode file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('파일 삭제'),
        content: Text('“${file.title}” 파일을 삭제할까요?'),
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
    if (confirmed != true || !mounted) return;
    try {
      await widget.store.deleteNode(file.id);
      await _loadFiles();
    } on FirebaseException catch (error) {
      _showFileOperationError(error.message ?? error.code);
    } on StateError catch (error) {
      _showFileOperationError(error.message);
    }
  }

  void _showFileOperationError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('파일 작업에 실패했습니다: $message')),
    );
  }

  List<String> _majorTopics(KnowledgeNode file) {
    final document = html_parser.parse(file.content);
    final headings = document.querySelectorAll('h1, h2, h3');
    final contentHeadings = headings
        .where((heading) =>
            heading.text.trim().toLowerCase() !=
            file.title.trim().toLowerCase())
        .toList();
    if (contentHeadings.isEmpty) return [file.title];
    final majorLevel = contentHeadings
        .map((heading) => int.parse(heading.localName!.substring(1)))
        .reduce((a, b) => a < b ? a : b);
    return contentHeadings
        .where((heading) =>
            int.parse(heading.localName!.substring(1)) == majorLevel)
        .map((heading) => heading.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
  }

  Future<void> _showFile(KnowledgeNode file) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HtmlPreviewPage(
          title: file.title,
          html: file.content,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _files.map(fileCategoryOf).toSet().toList()..sort();
    final visibleFiles = _files.where((file) {
      final matchesCategory = _selectedCategory == '전체' ||
          fileCategoryOf(file) == _selectedCategory;
      final query = _searchQuery.trim().toLowerCase();
      final text = html_parser.parse(file.content).body?.text ?? '';
      final matchesQuery = query.isEmpty ||
          file.title.toLowerCase().contains(query) ||
          fileCategoryOf(file).toLowerCase().contains(query) ||
          text.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();
    final categoryTabs = ['전체', ...categories];
    if (!categoryTabs.contains(_selectedCategory)) {
      _selectedCategory = '전체';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('파일')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '저장된 메모 파일',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: '파일 목록 새로고침',
                  onPressed: _loadFiles,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                Flexible(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _pickAndParse,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: Text(
                      _busy ? '가져오는 중...' : 'HTML 가져오기',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (value) => setState(() {
                _searchQuery = value;
                _displayLimit = 20;
              }),
              decoration: InputDecoration(
                hintText: '파일 제목, 내용, 분류 검색',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '검색 지우기',
                        onPressed: () => setState(() {
                          _searchQuery = '';
                          _displayLimit = 20;
                        }),
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: categoryTabs.map((category) {
                final selected = category == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Material(
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    child: InkWell(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                      onTap: () => setState(() {
                        _selectedCategory = category;
                        _displayLimit = 20;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(category),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          if (_createdCount > 0 || _fileName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _createdCount > 0
                    ? '$_fileName · $_createdCount개의 메모를 생성했습니다.'
                    : '$_fileName · 파일만 저장했습니다. 메모는 생성하지 않았습니다.',
              ),
            ),
          Expanded(
            child: _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('파일 목록을 불러오지 못했습니다.\n$_loadError'),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _loadFiles,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('다시 시도'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _loadingFiles && _files.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : visibleFiles.isEmpty
                        ? const Center(
                            child: Text(
                                '조건에 맞는 파일이 없습니다. 파일을 만들거나 HTML을 가져와 보세요.'))
                        : ListView.separated(
                            controller: _fileScrollController,
                            padding: const EdgeInsets.all(12),
                            itemCount: visibleFiles.length < _displayLimit
                                ? visibleFiles.length
                                : _displayLimit,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final file = visibleFiles[index];
                              final majorTopics = _majorTopics(file);
                              return Card(
                                child: ListTile(
                                  leading:
                                      const Icon(Icons.description_rounded),
                                  title: Text(file.title),
                                  subtitle: Text(
                                    '${fileCategoryOf(file)} · 대주제: ${majorTopics.join(' · ')}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing:
                                      const Icon(Icons.chevron_right_rounded),
                                  onTap: () => _showFile(file),
                                  onLongPress: () => _showFileActions(file),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
