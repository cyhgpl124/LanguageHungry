import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_ai/firebase_ai.dart';

class MemoAnalysis {
  const MemoAnalysis({
    required this.tags,
    required this.embedding,
    required this.language,
    required this.topics,
  });

  final List<String> tags;
  final List<double> embedding;
  final String language;
  final List<MemoTopic> topics;
}

class MemoTopic {
  const MemoTopic({
    required this.title,
    required this.summary,
    required this.content,
  });

  final String title;
  final String summary;
  final String content;
}

class MemoAnalysisOptions {
  const MemoAnalysisOptions({
    this.suggestTags = true,
    this.splitTopics = true,
    this.detectLanguage = true,
  });

  final bool suggestTags;
  final bool splitTopics;
  final bool detectLanguage;

  bool get usesAi => suggestTags || splitTopics || detectLanguage;

  MemoAnalysisOptions copyWith({
    bool? suggestTags,
    bool? splitTopics,
    bool? detectLanguage,
  }) =>
      MemoAnalysisOptions(
        suggestTags: suggestTags ?? this.suggestTags,
        splitTopics: splitTopics ?? this.splitTopics,
        detectLanguage: detectLanguage ?? this.detectLanguage,
      );
}

class MemoAiService {
  MemoAiService({GenerativeModel? model}) : _modelOverride = model;

  final GenerativeModel? _modelOverride;
  late final GenerativeModel _model = _modelOverride ??
      FirebaseAI.googleAI().generativeModel(
        model: 'gemini-3.6-flash',
      );

  Future<MemoAnalysis> analyze(
    String title,
    String content, {
    MemoAnalysisOptions options = const MemoAnalysisOptions(),
  }) async {
    final fallback = _fallback(title, content);
    if (!options.usesAi) {
      return _applyOptions(fallback, title, content, options);
    }
    try {
      final response = await _model.generateContent([
        Content.text('''
Analyze this memo and perform only these requested tasks:
${options.detectLanguage ? '- detect its language' : ''}
${options.suggestTags ? '- extract concise tags' : ''}
${options.splitTopics ? '- split its distinct topics' : ''}
Return JSON only:
{"language":"Korean","tags":["short tag"],"topics":[{"title":"short topic","summary":"brief summary","content":"topic details"}]}
Use one topic per distinct subject, and preserve the source language in topic
content. Keep topic titles concise. Leave unrequested fields empty.
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
      final topics = (data['topics'] as List? ?? const [])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .map((topic) {
            final content = (topic['content'] as String? ?? '').trim();
            final summary = (topic['summary'] as String? ?? '').trim();
            final topicTitle = (topic['title'] as String? ?? '').trim();
            return MemoTopic(
              title: topicTitle.isEmpty
                  ? (content.isEmpty ? summary : content.split('\n').first)
                  : topicTitle,
              summary: summary.isEmpty ? content : summary,
              content: content.isEmpty ? summary : content,
            );
          })
          .where(
              (topic) => topic.content.isNotEmpty || topic.summary.isNotEmpty)
          .toList();
      return _applyOptions(
        MemoAnalysis(
          tags: tags.isEmpty ? fallback.tags : tags,
          embedding: _embedding('$title $content'),
          language: _normalizeLanguage(data['language'] as String?) ??
              fallback.language,
          topics: topics.isEmpty ? fallback.topics : topics,
        ),
        title,
        content,
        options,
      );
    } catch (_) {
      return _applyOptions(fallback, title, content, options);
    }
  }

  MemoAnalysis _applyOptions(
    MemoAnalysis analysis,
    String title,
    String content,
    MemoAnalysisOptions options,
  ) {
    final trimmedContent = content.trim();
    return MemoAnalysis(
      tags: options.suggestTags ? analysis.tags : const [],
      embedding: analysis.embedding,
      language: options.detectLanguage
          ? analysis.language
          : detectMemoLanguage('$title $content'),
      topics: options.splitTopics || trimmedContent.isEmpty
          ? analysis.topics
          : [
              MemoTopic(
                title: title,
                summary: trimmedContent,
                content: trimmedContent,
              ),
            ],
    );
  }

  MemoAnalysis _fallback(String title, String content) {
    final words = '$title $content'
        .toLowerCase()
        .split(RegExp(r'[^a-zA-Z0-9가-힣]+'))
        .where((word) => word.length > 1)
        .toSet()
        .take(5)
        .toList();
    final paragraphs = content
        .split(RegExp(r'\r?\n\s*\r?\n'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty)
        .toList();
    final topics = paragraphs.isEmpty
        ? content.trim().isEmpty
            ? <MemoTopic>[]
            : [
                MemoTopic(
                  title: title,
                  summary: content.trim(),
                  content: content.trim(),
                ),
              ]
        : paragraphs.asMap().entries.map((entry) {
            final firstLine = entry.value
                .split(RegExp(r'\r?\n'))
                .first
                .replaceFirst(RegExp(r'^[#*\-\d.\s]+'), '')
                .trim();
            final topicTitle =
                firstLine.isEmpty ? '주제 ${entry.key + 1}' : firstLine;
            return MemoTopic(
              title: topicTitle,
              summary: entry.value,
              content: entry.value,
            );
          }).toList();
    return MemoAnalysis(
      tags: words.isEmpty ? ['memo'] : words,
      embedding: _embedding('$title $content'),
      language: detectMemoLanguage('$title $content'),
      topics: topics,
    );
  }

  List<double> embeddingFor(String text) => _embedding(text);

  String? _normalizeLanguage(String? value) {
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      'ko' || 'korean' || '한국어' || '한국말' => '한국어',
      'en' || 'english' || '영어' => '영어',
      'ja' || 'japanese' || '일본어' => '일본어',
      'zh' || 'chinese' || '중국어' => '중국어',
      'es' || 'spanish' || '스페인어' => '스페인어',
      'fr' || 'french' || '프랑스어' => '프랑스어',
      'de' || 'german' || '독일어' => '독일어',
      final String language when language.isNotEmpty => language,
      _ => null,
    };
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

String detectMemoLanguage(String text) {
  if (RegExp(r'[\u3040-\u30ff]').hasMatch(text)) return '일본어';
  if (RegExp(r'[\uac00-\ud7af]').hasMatch(text)) return '한국어';
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) return '중국어';
  if (RegExp(r'[a-zA-Z]').hasMatch(text)) return '영어';
  return '언어 미지정';
}
