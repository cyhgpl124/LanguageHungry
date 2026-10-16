import 'dart:async';
import 'dart:convert';

import './knowledge_store.dart';
import '../models/directed_edge.dart';
import '../models/knowledge_node.dart';

class MemoryKnowledgeStore implements KnowledgeStore {
  final _nodes = <String, KnowledgeNode>{};
  final _files = <String, Map<String, KnowledgeNode>>{};
  final _edges = <String, DirectedEdge>{};
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<KnowledgeNode> upsertNode(KnowledgeNode node) async {
    if (node.type == 'file') return upsertFile(node);
    final current = _nodes[node.id];
    if (current == null || node.updatedAt.isAfter(current.updatedAt)) {
      _nodes[node.id] = node;
      _changes.add(null);
    }
    return _nodes[node.id]!;
  }

  @override
  Future<DirectedEdge> upsertEdge(DirectedEdge edge) async {
    DirectedEdge? current;
    for (final candidate in _edges.values) {
      if (candidate.fromId == edge.fromId &&
          candidate.toId == edge.toId &&
          candidate.relation == edge.relation) {
        current = candidate;
        break;
      }
    }
    if (current == null || edge.updatedAt.isAfter(current.updatedAt)) {
      _edges[edge.id] = edge;
      _changes.add(null);
    }
    return edge;
  }

  @override
  Future<List<DirectedEdge>> listEdges() async => _edges.values.toList();

  @override
  Future<KnowledgeNode?> findNode(String id) async => _nodes[id];

  @override
  Future<List<KnowledgeNode>> listNodes({String? query, String? tag}) async {
    return _nodes.values.where((node) {
      final normalizedQuery = query?.trim().toLowerCase() ?? '';
      final matchesQuery = normalizedQuery.isEmpty ||
          node.title.toLowerCase().contains(normalizedQuery) ||
          node.content.toLowerCase().contains(normalizedQuery);
      final normalizedTag = tag?.trim() ?? '';
      final matchesTag =
          normalizedTag.isEmpty || node.tags.contains(normalizedTag);
      return matchesQuery && matchesTag;
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<KnowledgeNode> upsertFile(KnowledgeNode file) async {
    final categorized = categorizedFile(file);
    final category = fileCategoryOf(categorized);
    final categoryFiles = _files.putIfAbsent(category, () => {});
    final current = categoryFiles[categorized.id];
    if (current == null || categorized.updatedAt.isAfter(current.updatedAt)) {
      for (final files in _files.values) {
        files.remove(categorized.id);
      }
      categoryFiles[categorized.id] = categorized;
      _changes.add(null);
    }
    return categoryFiles[categorized.id] ?? categorized;
  }

  @override
  Future<List<KnowledgeNode>> listFiles() async =>
      _files.values.expand((files) => files.values).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> insertNode(KnowledgeNode node) => upsertNode(node);

  @override
  Future<void> deleteNode(String id) async {
    final removedNode = _nodes.remove(id) != null;
    var removedFile = false;
    for (final files in _files.values) {
      removedFile = files.remove(id) != null || removedFile;
    }
    if (!removedNode && !removedFile) return;
    _edges.removeWhere(
      (_, edge) => edge.fromId == id || edge.toId == id,
    );
    _changes.add(null);
  }

  @override
  Future<String> exportJson() async => jsonEncode({
        'version': 2,
        'nodes': _nodes.values
            .map((node) => {
                  'id': node.id,
                  'type': node.type,
                  'title': node.title,
                  'content': node.content,
                  'tags': node.tags,
                  'embedding': node.embedding,
                  'metadata': node.metadata,
                  'createdAt': node.createdAt.millisecondsSinceEpoch,
                  'updatedAt': node.updatedAt.millisecondsSinceEpoch,
                })
            .toList(),
        'files': _files.values
            .expand((files) => files.values)
            .map((file) => {
                  'id': file.id,
                  'type': file.type,
                  'title': file.title,
                  'content': file.content,
                  'tags': file.tags,
                  'embedding': file.embedding,
                  'metadata': file.metadata,
                  'createdAt': file.createdAt.millisecondsSinceEpoch,
                  'updatedAt': file.updatedAt.millisecondsSinceEpoch,
                })
            .toList(),
        'edges': _edges.values
            .map((edge) => {
                  'id': edge.id,
                  'fromId': edge.fromId,
                  'toId': edge.toId,
                  'relation': edge.relation,
                  'createdAt': edge.createdAt.millisecondsSinceEpoch,
                  'updatedAt': edge.updatedAt.millisecondsSinceEpoch,
                })
            .toList(),
      });

  @override
  Future<void> importJson(String value) async {
    final payload = jsonDecode(value) as Map<String, dynamic>;
    for (final raw in (payload['nodes'] as List? ?? const [])) {
      final data = Map<String, dynamic>.from(raw as Map);
      final node = KnowledgeNode(
        id: data['id'] as String,
        type: data['type'] as String,
        title: data['title'] as String,
        content: data['content'] as String,
        tags: (data['tags'] as List? ?? const []).cast<String>(),
        embedding: (data['embedding'] as List?)
            ?.map((value) => (value as num).toDouble())
            .toList(),
        metadata: (data['metadata'] as Map? ?? const {}).map(
          (key, value) => MapEntry(key as String, value as String),
        ),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int),
      );
      if (node.type == 'file') {
        final category = data['category'] as String? ??
            node.metadata['category'] ??
            node.metadata['classification'] ??
            node.metadata['분류'];
        await upsertFile(
          category == null
              ? categorizedFile(node)
              : node.copyWith(
                  metadata: {...node.metadata, 'category': category},
                ),
        );
      } else {
        await upsertNode(node);
      }
    }
    for (final raw in (payload['files'] as List? ?? const [])) {
      final data = Map<String, dynamic>.from(raw as Map);
      final file = KnowledgeNode(
        id: data['id'] as String,
        type: 'file',
        title: data['title'] as String,
        content: data['content'] as String,
        tags: (data['tags'] as List? ?? const []).cast<String>(),
        embedding: (data['embedding'] as List?)
            ?.map((value) => (value as num).toDouble())
            .toList(),
        metadata: (data['metadata'] as Map? ?? const {}).map(
          (key, value) => MapEntry(key as String, value as String),
        ),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int),
      );
      final category = data['category'] as String? ??
          file.metadata['category'] ??
          file.metadata['classification'] ??
          file.metadata['분류'];
      await upsertFile(
        category == null
            ? categorizedFile(file)
            : file.copyWith(
                metadata: {...file.metadata, 'category': category},
              ),
      );
    }
    for (final raw in (payload['edges'] as List? ?? const [])) {
      final data = Map<String, dynamic>.from(raw as Map);
      await upsertEdge(
        DirectedEdge(
          id: data['id'] as String,
          fromId: data['fromId'] as String,
          toId: data['toId'] as String,
          relation: data['relation'] as String,
          createdAt:
              DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
          updatedAt:
              DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int),
        ),
      );
    }
  }

  @override
  Future<void> close() => _changes.close();
}
