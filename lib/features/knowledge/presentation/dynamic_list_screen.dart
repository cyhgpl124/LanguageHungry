import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../data/knowledge_database.dart';
import '../domain/entities/knowledge_node.dart';
import 'knowledge_bloc.dart';

class DynamicListScreen extends StatelessWidget {
  const DynamicListScreen({required this.store, super.key});

  final KnowledgeStore store;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => KnowledgeListCubit(store)..load(),
      child: const _DynamicListView(),
    );
  }
}

class _DynamicListView extends StatefulWidget {
  const _DynamicListView();

  @override
  State<_DynamicListView> createState() => _DynamicListViewState();
}

class _DynamicListViewState extends State<_DynamicListView> {
  final _queryController = TextEditingController();
  final _tagController = TextEditingController();
  final _batchController = TextEditingController();
  final _customDelimiterController = TextEditingController();
  String _delimiter = '쉼표 (,)';
  final List<String> _columns = const ['제목', '내용'];

  @override
  void dispose() {
    _queryController.dispose();
    _tagController.dispose();
    _batchController.dispose();
    _customDelimiterController.dispose();
    super.dispose();
  }

  void _search() {
    context.read<KnowledgeListCubit>().load(
          query: _queryController.text,
          tag: _tagController.text,
        );
  }

  String get _delimiterValue => switch (_delimiter) {
        '탭' => '\t',
        '세미콜론 (;)' => ';',
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
            'mode': 'list',
            'display': '리스트',
            ...values,
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

  Future<void> _addBatchText() async {
    final rows = _parseRows(_batchController.text, _delimiterValue);
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일괄 입력할 데이터를 작성해 주세요.')),
      );
      return;
    }
    await _saveRows(rows);
    _batchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('리스트 모드'),
        actions: [
          IconButton(
            onPressed: _importFile,
            tooltip: 'CSV/Excel 업로드',
            icon: const Icon(Icons.upload_file_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _queryController,
                    decoration: const InputDecoration(
                      labelText: '전체 검색',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _tagController,
                    decoration: const InputDecoration(
                      labelText: '태그 필터',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _search,
                  child: const Text('검색'),
                ),
              ],
            ),
          ),
          ExpansionTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: const Text('텍스트 일괄 입력'),
            subtitle: const Text('한 줄에 한 행씩 입력하고 구분자를 선택하세요.'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('구분자'),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: _delimiter,
                          items: const [
                            DropdownMenuItem(
                                value: '쉼표 (,)', child: Text('쉼표 (,)')),
                            DropdownMenuItem(value: '탭', child: Text('탭')),
                            DropdownMenuItem(
                                value: '세미콜론 (;)', child: Text('세미콜론 (;)')),
                            DropdownMenuItem(value: '공백', child: Text('공백')),
                            DropdownMenuItem(
                                value: '사용자 지정', child: Text('사용자 지정')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _delimiter = value);
                            }
                          },
                        ),
                        if (_delimiter == '사용자 지정')
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: _customDelimiterController,
                              maxLength: 1,
                              decoration: const InputDecoration(
                                labelText: '기호',
                                counterText: '',
                              ),
                            ),
                          ),
                      ],
                    ),
                    TextField(
                      controller: _batchController,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        hintText: '제목,내용,태그\n아침 인사,おはようございます,일본어',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _addBatchText,
                        icon: const Icon(Icons.add),
                        label: const Text('리스트에 추가'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: BlocBuilder<KnowledgeListCubit, KnowledgeListState>(
              builder: (context, state) {
                if (state.loading && state.nodes.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows =
                    state.nodes.where((node) => node.mode == 'list').toList();
                if (rows.isEmpty) {
                  return const Center(
                    child: Text(
                        '리스트 데이터가 없습니다.\nCSV/Excel 업로드 또는 텍스트 입력을 사용하세요.',
                        textAlign: TextAlign.center),
                  );
                }
                final columns = <String>{..._columns, '태그', '종류'};
                for (final node in rows) {
                  columns
                      .addAll(node.metadata.keys.where((key) => key != 'mode'));
                }
                final displayColumns = columns.toList();
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStatePropertyAll(Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest),
                      columns: displayColumns
                          .map((column) => DataColumn(label: Text(column)))
                          .toList(),
                      rows: rows.map((node) {
                        return DataRow(
                          cells: displayColumns.map((column) {
                            final value = column == '제목'
                                ? node.title
                                : column == '내용'
                                    ? node.content
                                    : column == '태그'
                                        ? node.tags
                                            .map((tag) => '#$tag')
                                            .join(' ')
                                        : column == '종류'
                                            ? node.metadata['display'] ??
                                                (node.mode == 'list'
                                                    ? '리스트'
                                                    : node.mode)
                                            : node.metadata[column] ?? '';
                            return DataCell(
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 260),
                                child: Text(value,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            );
                          }).toList(),
                        );
                      }).toList(),
                    ),
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
