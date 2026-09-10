import 'knowledge_store.dart';
import 'memory_knowledge_store.dart';
import '../domain/entities/directed_edge.dart';
import '../domain/entities/knowledge_node.dart';

class SqliteKnowledgeStore implements KnowledgeStore {
  final _delegate = MemoryKnowledgeStore();

  @override
  Stream<void> get changes => _delegate.changes;

  @override
  Future<void> initialize() => _delegate.initialize();

  @override
  Future<KnowledgeNode> upsertNode(KnowledgeNode node) =>
      _delegate.upsertNode(node);

  @override
  Future<DirectedEdge> upsertEdge(DirectedEdge edge) =>
      _delegate.upsertEdge(edge);

  @override
  Future<List<DirectedEdge>> listEdges() => _delegate.listEdges();

  @override
  Future<KnowledgeNode?> findNode(String id) => _delegate.findNode(id);

  @override
  Future<List<KnowledgeNode>> listNodes({String? query, String? tag}) =>
      _delegate.listNodes(query: query, tag: tag);

  @override
  Future<void> insertNode(KnowledgeNode node) => _delegate.insertNode(node);

  @override
  Future<String> exportJson() => _delegate.exportJson();

  @override
  Future<void> importJson(String json) => _delegate.importJson(json);

  @override
  Future<void> close() => _delegate.close();
}
