import 'dart:convert';
import 'dart:math' as math;

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:langgry/features/knowledge/services/knowledge_database.dart';
import 'package:langgry/features/knowledge/models/knowledge_node.dart';
import 'package:langgry/features/knowledge/list/blocs/knowledge_bloc.dart';

class DynamicListScreen extends StatelessWidget {
  const DynamicListScreen({
    required this.store,
    this.embedded = false,
    super.key,
  });

  final KnowledgeStore store;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => KnowledgeListCubit(store)..load(),
      child: _DynamicListView(embedded: embedded),
    );
  }
}

class _DynamicListView extends StatefulWidget {
  const _DynamicListView({required this.embedded});

  final bool embedded;

  @override
  State<_DynamicListView> createState() => _DynamicListViewState();
}

class _DynamicListViewState extends State<_DynamicListView> {
  final _queryController = TextEditingController();
  final _customDelimiterController = TextEditingController();
  String _delimiter = '쉼표 (,)';

  @override
  void dispose() {
    _queryController.dispose();
    _customDelimiterController.dispose();
    super.dispose();
  }

  void _search() {
    context.read<KnowledgeListCubit>().load(
          query: _queryController.text,
        );
  }

  String get _delimiterValue => switch (_delimiter) {
        '세미콜론 (;)' => ';',
        '콜론 (:)' => ':',
        '공백' => ' ',
        '사용자 지정' => _customDelimiterController.text.isEmpty
            ? ','
            : _customDelimiterController.text.substring(0, 1),
        _ => ',',
      };

  List<List<String>> _parseRows(String text, String delimiter) {
    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(
            (line) => line.split(delimiter).map((cell) => cell.trim()).toList())
        .toList();
  }

  Future<void> _saveRows(List<List<String>> rows) async {
    if (rows.isEmpty) return;
    final cubit = context.read<KnowledgeListCubit>();
    final hasHeader = rows.length > 1;
    final headers = hasHeader
        ? rows.first
        : List.generate(rows.first.length, (index) => '열 ${index + 1}');
    final dataRows = hasHeader ? rows.skip(1) : rows;
    var imported = 0;
    for (final row in dataRows) {
      if (row.every((value) => value.isEmpty)) continue;
      final title = row.isNotEmpty && row.first.isNotEmpty
          ? row.first
          : '리스트 데이터 ${imported + 1}';
      final values = <String, String>{};
      for (var index = 0;
          index < row.length && index < headers.length;
          index++) {
        values[headers[index].isEmpty ? '열 ${index + 1}' : headers[index]] =
            row[index];
      }
      final now = DateTime.now();
      await cubit.store.insertNode(
        KnowledgeNode(
          id: const Uuid().v4(),
          type: 'knowledge',
          title: title,
          content: row.skip(1).join(' | '),
          createdAt: now,
          updatedAt: now,
          metadata: {
            ...values,
            'mode': 'list',
            'display': '리스트',
            'listProperty': headers.join(_delimiterValue),
            'listValue': row.join(_delimiterValue),
            'listDelimiter': _delimiterValue,
          },
        ),
      );
      imported++;
    }
    _search();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$imported개의 행을 추가했습니다.')),
      );
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv', 'txt'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null) return;
    try {
      if ((file!.extension ?? '').toLowerCase() == 'csv' ||
          (file.extension ?? '').toLowerCase() == 'txt') {
        await _saveRows(_parseRows(utf8.decode(bytes), _delimiterValue));
      } else {
        final workbook = Excel.decodeBytes(bytes);
        final rows = workbook.tables.values
            .expand((sheet) => sheet.rows)
            .map((row) => row
                .map((cell) => cell?.value?.toString().trim() ?? '')
                .toList())
            .toList();
        await _saveRows(rows);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('파일 가져오기 실패: $error')),
        );
      }
    }
  }

  Future<void> _showAddListDialog() async {
    await _showListEditor();
  }

  Future<void> _showListEditor({KnowledgeNode? editing}) async {
    final result = await showDialog<_ListEntryInput>(
      context: context,
      builder: (_) => _AddListDialog(
        initialTitle: editing?.title ?? '',
        initialProperty: editing?.metadata['listProperty'] ?? '',
        initialContent:
            editing?.metadata['listValue'] ?? editing?.content ?? '',
        initialDelimiter: _delimiter,
        initialCustomDelimiter: _customDelimiterController.text,
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _delimiter = result.delimiter;
      _customDelimiterController.text = result.customDelimiter;
    });
    final now = DateTime.now();
    await context.read<KnowledgeListCubit>().store.upsertNode(
          KnowledgeNode(
            id: editing?.id ?? const Uuid().v4(),
            type: 'knowledge',
            title: result.title,
            content: result.content,
            createdAt: editing?.createdAt ?? now,
            updatedAt: now,
            tags: editing?.tags ?? const [],
            embedding: editing?.embedding,
            metadata: {
              ...?editing?.metadata,
              'mode': 'list',
              'display': '리스트',
              'listProperty': result.property,
              'listValue': result.content,
              'listDelimiter': result.delimiterValue,
            },
          ),
        );
    _search();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(editing == null ? '리스트를 저장했습니다.' : '리스트를 수정했습니다.'),
        ),
      );
    }
  }

  void _showListDetails(KnowledgeNode node) {
    final property = node.metadata['listProperty'];
    final value = property == null
        ? node.content
        : node.metadata['listValue'] ?? node.content;
    final delimiter = node.metadata['listDelimiter'] ?? ',';
    final headers = property == null || property.trim().isEmpty
        ? ['내용']
        : property
            .split(delimiter)
            .map((header) => header.trim())
            .where((header) => header.isNotEmpty)
            .toList();
    final dataRows = value
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(
            (line) => line.split(delimiter).map((cell) => cell.trim()).toList())
        .toList();
    final columnCount = dataRows.fold<int>(
      headers.length,
      (count, row) => row.length > count ? row.length : count,
    );
    final displayHeaders = List.generate(
      columnCount,
      (index) => index < headers.length && headers[index].isNotEmpty
          ? headers[index]
          : '열 ${index + 1}',
    );
    final viewport = MediaQuery.sizeOf(context);
    final maxDialogWidth = math.max(0.0, viewport.width - 32);
    final maxDialogHeight = math.max(0.0, viewport.height - 48);
    final maxContentWidth = math.max(0.0, math.min(900, maxDialogWidth) - 32);
    final maxContentHeight =
        math.max(0.0, math.min(760, maxDialogHeight) - 160);
    final dialogWidth =
        math.min(maxContentWidth, 120 + (columnCount * 160.0)).toDouble();
    final tableHeight =
        math.min(maxContentHeight, 56 + (dataRows.length * 56.0)).toDouble();
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(900, maxDialogWidth),
            maxHeight: math.min(760, maxDialogHeight),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(node.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                SizedBox(
                  width: dialogWidth,
                  height: tableHeight,
                  child: dataRows.isEmpty
                      ? const Center(child: Text('표시할 내용이 없습니다.'))
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SingleChildScrollView(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStatePropertyAll(
                                    Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                  columns: displayHeaders
                                      .map(
                                        (header) => DataColumn(
                                          label: Text(
                                            header,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  rows: dataRows
                                      .map(
                                        (row) => DataRow(
                                          cells: List.generate(
                                            columnCount,
                                            (index) => DataCell(
                                              ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                  maxWidth: 260,
                                                ),
                                                child: Text(
                                                  index < row.length
                                                      ? row[index]
                                                      : '',
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ),
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

  Future<void> _showListActions(KnowledgeNode node) async {
    final action = await showModalBottomSheet<_ListAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('수정'),
              onTap: () => Navigator.pop(context, _ListAction.edit),
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
              onTap: () => Navigator.pop(context, _ListAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == _ListAction.edit) {
      await _showListEditor(editing: node);
    } else if (action == _ListAction.delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('리스트 삭제'),
          content: Text('"${node.title}" 리스트를 삭제할까요?'),
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
        await context.read<KnowledgeListCubit>().store.deleteNode(node.id);
        _search();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('리스트 모드')),
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final searchField = TextField(
                    controller: _queryController,
                    decoration: const InputDecoration(
                      labelText: '전체 검색',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _search(),
                  );
                  final actions = Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: _search,
                        tooltip: '검색',
                        icon: const Icon(Icons.keyboard_return_rounded),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: '리스트 추가',
                          child: FilledButton.tonalIcon(
                            onPressed: _showAddListDialog,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('추가'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: '엑셀/CSV 업로드',
                          child: FilledButton.tonalIcon(
                            onPressed: _importFile,
                            icon: const Icon(Icons.upload_file_rounded),
                            label: const Text('업로드'),
                          ),
                        ),
                      ),
                    ],
                  );

                  if (constraints.maxWidth < 520) {
                    return Column(
                      children: [
                        searchField,
                        const SizedBox(height: 10),
                        actions,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(flex: 3, child: searchField),
                      const SizedBox(width: 12),
                      Expanded(flex: 4, child: actions),
                    ],
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: Divider(height: 1)),
          BlocBuilder<KnowledgeListCubit, KnowledgeListState>(
            builder: (context, state) {
              if (state.loading && state.nodes.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final rows =
                  state.nodes.where((node) => node.mode == 'list').toList();
              if (rows.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      '리스트 데이터가 없습니다.\n리스트 추가 또는 CSV/Excel 업로드를 사용하세요.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid.builder(
                  itemCount: rows.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisExtent: 112,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final node = rows[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _showListDetails(node),
                        onLongPress: () => _showListActions(node),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              node.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ListEntryInput {
  const _ListEntryInput({
    required this.title,
    required this.property,
    required this.content,
    required this.delimiter,
    required this.customDelimiter,
  });

  final String title;
  final String property;
  final String content;
  final String delimiter;
  final String customDelimiter;

  String get delimiterValue => switch (delimiter) {
        '세미콜론 (;)' => ';',
        '콜론 (:)' => ':',
        '공백' => ' ',
        '사용자 지정' => customDelimiter.isEmpty ? ',' : customDelimiter[0],
        _ => ',',
      };
}

enum _ListAction { edit, delete }

class _AddListDialog extends StatefulWidget {
  const _AddListDialog({
    required this.initialTitle,
    required this.initialProperty,
    required this.initialContent,
    required this.initialDelimiter,
    required this.initialCustomDelimiter,
  });

  final String initialTitle;
  final String initialProperty;
  final String initialContent;
  final String initialDelimiter;
  final String initialCustomDelimiter;

  @override
  State<_AddListDialog> createState() => _AddListDialogState();
}

class _AddListDialogState extends State<_AddListDialog> {
  late final _titleController =
      TextEditingController(text: widget.initialTitle);
  late final _propertyController =
      TextEditingController(text: widget.initialProperty);
  late final _contentController =
      TextEditingController(text: widget.initialContent);
  late final _customDelimiterController =
      TextEditingController(text: widget.initialCustomDelimiter);
  late String _delimiter = widget.initialDelimiter;

  @override
  void dispose() {
    _titleController.dispose();
    _propertyController.dispose();
    _contentController.dispose();
    _customDelimiterController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    final property = _propertyController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || property.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목, 열의 속성, 내용을 모두 입력해 주세요.')),
      );
      return;
    }
    Navigator.pop(
      context,
      _ListEntryInput(
        title: title,
        property: property,
        content: content,
        delimiter: _delimiter,
        customDelimiter: _customDelimiterController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('리스트 추가'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '제목',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _propertyController,
                decoration: const InputDecoration(
                  labelText: '열의 속성',
                  hintText: '예: 단어, 날짜, 상태',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '내용',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _delimiter,
                decoration: const InputDecoration(
                  labelText: '구분자',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: '쉼표 (,)', child: Text('쉼표 (,)')),
                  DropdownMenuItem(value: '세미콜론 (;)', child: Text('세미콜론 (;)')),
                  DropdownMenuItem(value: '콜론 (:)', child: Text('콜론 (:)')),
                  DropdownMenuItem(value: '공백', child: Text('공백')),
                  DropdownMenuItem(value: '사용자 지정', child: Text('사용자 지정')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _delimiter = value);
                },
              ),
              if (_delimiter == '사용자 지정')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Text('기호'),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _customDelimiterController,
                          maxLength: 1,
                          decoration: const InputDecoration(
                            labelText: '사용자 지정',
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
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
