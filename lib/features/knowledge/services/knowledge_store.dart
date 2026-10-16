import '../models/directed_edge.dart';
import '../models/knowledge_node.dart';

abstract interface class KnowledgeStore {
  Stream<void> get changes;
  Future<void> initialize();
  Future<KnowledgeNode> upsertNode(KnowledgeNode node);
  Future<DirectedEdge> upsertEdge(DirectedEdge edge);
  Future<List<DirectedEdge>> listEdges();
  Future<KnowledgeNode?> findNode(String id);
  Future<List<KnowledgeNode>> listNodes({String? query, String? tag});
  Future<KnowledgeNode> upsertFile(KnowledgeNode file);
  Future<List<KnowledgeNode>> listFiles();
  Future<void> insertNode(KnowledgeNode node);
  Future<void> deleteNode(String id);
  Future<String> exportJson();
  Future<void> importJson(String json);
  Future<void> close();
}

const defaultFileCategory = '기존 파일';

String fileCategoryOf(KnowledgeNode file) =>
    file.metadata['category']?.trim().isNotEmpty == true
        ? file.metadata['category']!.trim()
        : file.metadata['classification']?.trim().isNotEmpty == true
            ? file.metadata['classification']!.trim()
            : file.metadata['분류']?.trim().isNotEmpty == true
                ? file.metadata['분류']!.trim()
                : defaultFileCategory;

KnowledgeNode categorizedFile(KnowledgeNode file) {
  if (file.type != 'file') {
    throw ArgumentError.value(file.type, 'file.type', 'Expected file');
  }
  final category = fileCategoryOf(file);
  return file.copyWith(metadata: {...file.metadata, 'category': category});
}
