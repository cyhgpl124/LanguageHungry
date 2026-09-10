import '../domain/entities/directed_edge.dart';
import '../domain/entities/knowledge_node.dart';

abstract interface class KnowledgeStore {
  Stream<void> get changes;
  Future<void> initialize();
  Future<KnowledgeNode> upsertNode(KnowledgeNode node);
  Future<DirectedEdge> upsertEdge(DirectedEdge edge);
  Future<List<DirectedEdge>> listEdges();
  Future<KnowledgeNode?> findNode(String id);
  Future<List<KnowledgeNode>> listNodes({String? query, String? tag});
  Future<void> insertNode(KnowledgeNode node);
  Future<String> exportJson();
  Future<void> importJson(String json);
  Future<void> close();
}
