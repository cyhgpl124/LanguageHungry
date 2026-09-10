import 'dart:convert';

import '../domain/entities/directed_edge.dart';
import '../domain/entities/knowledge_node.dart';

Map<String, dynamic> nodeToMap(KnowledgeNode node) => {
      'id': node.id,
      'type': node.type,
      'title': node.title,
      'content': node.content,
      'tags': node.tags,
      'embedding': node.embedding,
      'metadata': node.metadata,
      'createdAt': node.createdAt.millisecondsSinceEpoch,
      'updatedAt': node.updatedAt.millisecondsSinceEpoch,
    };

KnowledgeNode nodeFromMap(Map<String, dynamic> data) => KnowledgeNode(
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
      createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int),
    );

Map<String, dynamic> edgeToMap(DirectedEdge edge) => {
      'id': edge.id,
      'fromId': edge.fromId,
      'toId': edge.toId,
      'relation': edge.relation,
      'createdAt': edge.createdAt.millisecondsSinceEpoch,
      'updatedAt': edge.updatedAt.millisecondsSinceEpoch,
    };

DirectedEdge edgeFromMap(Map<String, dynamic> data) => DirectedEdge(
      id: data['id'] as String,
      fromId: data['fromId'] as String,
      toId: data['toId'] as String,
      relation: data['relation'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int),
    );

Map<String, dynamic> decodeMap(String value) =>
    jsonDecode(value) as Map<String, dynamic>;
