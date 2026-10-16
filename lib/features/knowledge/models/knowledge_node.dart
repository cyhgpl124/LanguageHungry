class KnowledgeNode {
  const KnowledgeNode({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const <String>[],
    this.embedding,
    this.metadata = const <String, String>{},
  });

  final String id;
  final String type;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tags;
  final List<double>? embedding;
  final Map<String, String> metadata;

  String get mode => metadata['mode'] ?? type;

  KnowledgeNode copyWith({
    String? title,
    String? content,
    DateTime? updatedAt,
    List<String>? tags,
    List<double>? embedding,
    Map<String, String>? metadata,
  }) {
    return KnowledgeNode(
      id: id,
      type: type,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      embedding: embedding ?? this.embedding,
      metadata: metadata ?? this.metadata,
    );
  }
}
