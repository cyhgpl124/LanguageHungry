import 'package:flutter/material.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:uuid/uuid.dart';

import '../data/knowledge_database.dart';
import '../data/memo_ai_service.dart';
import '../domain/entities/knowledge_node.dart';

class PlotModeScreen extends StatefulWidget {
  const PlotModeScreen({required this.store, super.key});

  final KnowledgeStore store;

  @override
  State<PlotModeScreen> createState() => _PlotModeScreenState();
}

class _PlotModeScreenState extends State<PlotModeScreen> {
  final _background = TextEditingController();
  final _request = TextEditingController();
  final _result = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _background.dispose();
    _request.dispose();
    _result.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      final model =
          FirebaseAI.googleAI().generativeModel(model: 'gemini-3.6-flash');
      final response = await model.generateContent([
        Content.text(
          'Create a clear structured plot from this background and request. '
          'Return plain text with headings.\nBackground:\n${_background.text}\n'
          'Request:\n${_request.text}',
        ),
      ]);
      _result.text = response.text ?? '';
    } catch (error) {
      _result.text = 'AI 생성 실패: $error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final result = _result.text.trim();
    if (result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장할 플롯 결과를 먼저 생성하거나 입력해 주세요.')),
      );
      return;
    }
    try {
      final now = DateTime.now();
      final lines = result
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final title = lines.isEmpty
          ? '플롯'
          : lines.first.replaceFirst(
              RegExp(r'^[#*\-\d.\s]+'),
              '',
            );
      final content = lines.length <= 1 ? result : lines.skip(1).join('\n');
      final analysis = await MemoAiService().analyze(title, content);
      await widget.store.insertNode(
        KnowledgeNode(
          id: const Uuid().v4(),
          type: 'knowledge',
          title: title.isEmpty ? '플롯' : title,
          content: content,
          createdAt: now,
          updatedAt: now,
          tags: analysis.tags,
          embedding: analysis.embedding,
          metadata: const {'mode': 'plot', 'display': '플롯'},
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('플롯을 저장했습니다.')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('플롯 저장 실패: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('플롯 모드'),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _background,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '배경 텍스트',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _request,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '사용자 요청',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: Text(_loading ? '생성 중...' : 'AI 플롯 생성'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _result,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: '검토·수정 후 저장할 결과',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _loading ? null : _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('플롯 저장'),
            ),
          ),
        ],
      ),
    );
  }
}
