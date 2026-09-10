import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_ai/firebase_ai.dart';

class MemoAnalysis {
  const MemoAnalysis({required this.tags, required this.embedding});

  final List<String> tags;
  final List<double> embedding;
}

class MemoAiService {
  MemoAiService({GenerativeModel? model})
      : _model = model ??
            FirebaseAI.googleAI().generativeModel(
              model: 'gemini-3.6-flash',
            );

  final GenerativeModel _model;

  Future<MemoAnalysis> analyze(String title, String content) async {
    final fallback = _fallback(title, content);
    try {
      final response = await _model.generateContent([
        Content.text('''
Analyze this knowledge memo. Return JSON only:
{"tags":["short tag"],"keywords":["keyword"]}
Title: $title
Content: $content
'''),
      ]);
      final raw = response.text;
      if (raw == null) return fallback;
      final jsonText = raw
          .replaceFirst(RegExp(r'^```json\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
      final data = jsonDecode(jsonText) as Map<String, dynamic>;
      final tags = (data['tags'] as List? ?? const [])
          .whereType<String>()
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .take(8)
          .toList();
      return MemoAnalysis(
        tags: tags.isEmpty ? fallback.tags : tags,
        embedding: _embedding('$title $content'),
      );
    } catch (_) {
      return fallback;
    }
  }

  MemoAnalysis _fallback(String title, String content) {
    final words = '$title $content'
        .toLowerCase()
        .split(RegExp(r'[^a-zA-Z0-9가-힣]+'))
        .where((word) => word.length > 1)
        .toSet()
        .take(5)
        .toList();
    return MemoAnalysis(
      tags: words.isEmpty ? ['memo'] : words,
      embedding: _embedding('$title $content'),
    );
  }

  List<double> _embedding(String text) {
    final vector = List<double>.filled(32, 0);
    for (var index = 0; index < text.length; index++) {
      final code = text.codeUnitAt(index);
      vector[(code + index) % vector.length] += 1;
    }
    final norm = math.sqrt(vector.fold(0, (sum, value) => sum + value * value));
    return norm == 0 ? vector : vector.map((value) => value / norm).toList();
  }
}
