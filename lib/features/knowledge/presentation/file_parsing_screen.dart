import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:uuid/uuid.dart';

import '../data/knowledge_database.dart';
import '../domain/entities/directed_edge.dart';
import '../domain/entities/knowledge_node.dart';

class FileParsingScreen extends StatefulWidget {
  const FileParsingScreen({required this.store, super.key});

  final KnowledgeStore store;

  @override
  State<FileParsingScreen> createState() => _FileParsingScreenState();
}

class _FileParsingScreenState extends State<FileParsingScreen> {
  bool _busy = false;
  String? _fileName;
  int _createdCount = 0;

  Future<void> _pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['html', 'htm'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    final file = result!.files.single;
    setState(() {
      _busy = true;
      _fileName = file.name;
    });
    try {
      final document = html_parser.parse(String.fromCharCodes(bytes));
      final now = DateTime.now();
      final fileId = const Uuid().v4();
      await widget.store.insertNode(
        KnowledgeNode(
          id: fileId,
          type: 'file',
          title: _fileName!,
          content: document.body?.text.trim() ?? '',
          createdAt: now,
          updatedAt: now,
        ),
      );
      var count = 0;
      String? previousId;
      for (final dom.Element element
          in document.querySelectorAll('h1, h2, h3, p')) {
        final content = element.text.trim();
        if (content.isEmpty) continue;
        final nodeId = const Uuid().v4();
        await widget.store.insertNode(
          KnowledgeNode(
            id: nodeId,
            type: 'memo',
            title: element.localName!.startsWith('h')
                ? content
                : content.split(' ').first,
            content: element.localName!.startsWith('h')
                ? ''
                : content.split(' ').skip(1).join(' '),
            createdAt: now,
            updatedAt: now,
            metadata: {'sourceFileId': fileId, 'htmlTag': element.localName!},
          ),
        );
        await widget.store.upsertEdge(
          DirectedEdge(
            id: const Uuid().v4(),
            fromId: fileId,
            toId: nodeId,
            relation: 'contains',
            createdAt: now,
            updatedAt: now,
          ),
        );
        if (previousId != null) {
          await widget.store.upsertEdge(
            DirectedEdge(
              id: const Uuid().v4(),
              fromId: previousId,
              toId: nodeId,
              relation: 'next',
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
        previousId = nodeId;
        count++;
      }
      if (mounted) setState(() => _createdCount = count);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HTML 파일 가져오기')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_tree_rounded, size: 72),
              const SizedBox(height: 16),
              Text(_fileName ?? 'HTML의 제목과 본문을 개별 메모로 변환합니다.'),
              if (_createdCount > 0) ...[
                const SizedBox(height: 8),
                Text('$_createdCount개의 메모를 생성했습니다.'),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _pickAndParse,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(_busy ? '가져오는 중...' : 'HTML 선택'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
