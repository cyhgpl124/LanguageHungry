import 'dart:async';
import 'dart:convert';

import 'knowledge_store.dart';
import '../domain/entities/directed_edge.dart';
import '../domain/entities/knowledge_node.dart';

class MemoryKnowledgeStore implements KnowledgeStore {
  final _nodes = <String, KnowledgeNode>{};
  final _edges = <String, DirectedEdge>{};
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<KnowledgeNode> upsertNode(KnowledgeNode node) async {
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
  Future<void> insertNode(KnowledgeNode node) => upsertNode(node);

  @override
  Future<String> exportJson() async => jsonEncode({
        'version': 1,
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
      await upsertNode(
        KnowledgeNode(
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
