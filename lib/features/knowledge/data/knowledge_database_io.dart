import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'knowledge_store.dart';
import '../domain/entities/directed_edge.dart';
import '../domain/entities/knowledge_node.dart';

class SqliteKnowledgeStore implements KnowledgeStore {
  Database? _database;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<void> initialize() async {
    if (_database != null) return;
    final directory = await getApplicationSupportDirectory();
    final database =
        sqlite3.open(p.join(directory.path, 'langgry_knowledge.db'));
    database.execute('PRAGMA foreign_keys = ON;');
    database.execute('''
      CREATE TABLE IF NOT EXISTS nodes (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        tags_json TEXT NOT NULL,
        embedding_json TEXT,
        metadata_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS directed_edges (
        id TEXT PRIMARY KEY,
        from_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        to_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        relation TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE(from_id, to_id, relation)
      );
    ''');
    database.execute(
      'CREATE INDEX IF NOT EXISTS nodes_updated_at ON nodes(updated_at);',
    );
    database.execute(
      'CREATE INDEX IF NOT EXISTS nodes_type ON nodes(type);',
    );
    _database = database;
  }

  Database get _db =>
      _database ?? (throw StateError('Knowledge store is not initialized.'));

  @override
  Future<KnowledgeNode> upsertNode(KnowledgeNode node) async {
    final current = _db.select(
      'SELECT updated_at FROM nodes WHERE id = ?',
      [node.id],
    );
    if (current.isNotEmpty &&
        (current.first['updated_at'] as int) >=
            node.updatedAt.millisecondsSinceEpoch) {
      return node;
    }
    _db.execute('''
      INSERT INTO nodes
        (id, type, title, content, tags_json, embedding_json, metadata_json, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        type = excluded.type,
        title = excluded.title,
        content = excluded.content,
        tags_json = excluded.tags_json,
        embedding_json = excluded.embedding_json,
        metadata_json = excluded.metadata_json,
        updated_at = excluded.updated_at
      WHERE excluded.updated_at > nodes.updated_at
    ''', [
      node.id,
      node.type,
      node.title,
      node.content,
      jsonEncode(node.tags),
      node.embedding == null ? null : jsonEncode(node.embedding),
      jsonEncode(node.metadata),
      node.createdAt.millisecondsSinceEpoch,
      node.updatedAt.millisecondsSinceEpoch,
    ]);
    _changes.add(null);
    return node;
  }

  @override
  Future<DirectedEdge> upsertEdge(DirectedEdge edge) async {
    _db.execute('''
      INSERT INTO directed_edges
        (id, from_id, to_id, relation, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(from_id, to_id, relation) DO UPDATE SET
        id = excluded.id,
        updated_at = excluded.updated_at
      WHERE excluded.updated_at > directed_edges.updated_at
    ''', [
      edge.id,
      edge.fromId,
      edge.toId,
      edge.relation,
      edge.createdAt.millisecondsSinceEpoch,
      edge.updatedAt.millisecondsSinceEpoch,
    ]);
    _changes.add(null);
    return edge;
  }

  @override
  Future<List<DirectedEdge>> listEdges() async {
    final rows = _db.select('SELECT * FROM directed_edges');
    return rows.map(_edgeFromRow).toList();
  }

  @override
  Future<KnowledgeNode?> findNode(String id) async {
    final rows = _db.select('SELECT * FROM nodes WHERE id = ?', [id]);
    return rows.isEmpty ? null : _nodeFromRow(rows.first);
  }

  @override
  Future<List<KnowledgeNode>> listNodes({String? query, String? tag}) async {
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (query != null && query.trim().isNotEmpty) {
      clauses.add('(title LIKE ? OR content LIKE ?)');
      final value = '%${query.trim()}%';
      arguments
        ..add(value)
        ..add(value);
    }
    if (tag != null && tag.trim().isNotEmpty) {
      clauses.add('tags_json LIKE ?');
      arguments.add('%"${tag.trim()}"%');
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = _db.select(
      'SELECT * FROM nodes $where ORDER BY updated_at DESC',
      arguments,
    );
    return rows.map(_nodeFromRow).toList();
  }

  @override
  Future<void> insertNode(KnowledgeNode node) => upsertNode(node);

  @override
  Future<String> exportJson() async {
    final nodes = _db.select('SELECT * FROM nodes');
    final edges = _db.select('SELECT * FROM directed_edges');
    return jsonEncode({
      'version': 1,
      'nodes': nodes
          .map((row) => {
                'id': row['id'],
                'type': row['type'],
                'title': row['title'],
                'content': row['content'],
                'tags': jsonDecode(row['tags_json']),
                'embedding': row['embedding_json'] == null
                    ? null
                    : jsonDecode(row['embedding_json'] as String),
                'metadata': jsonDecode(row['metadata_json']),
                'createdAt': row['created_at'],
                'updatedAt': row['updated_at'],
              })
          .toList(),
      'edges': edges
          .map((row) => {
                'id': row['id'],
                'fromId': row['from_id'],
                'toId': row['to_id'],
                'relation': row['relation'],
                'createdAt': row['created_at'],
                'updatedAt': row['updated_at'],
              })
          .toList(),
    });
  }

  @override
  Future<void> importJson(String value) async {
    final payload = jsonDecode(value) as Map<String, dynamic>;
    for (final raw in (payload['nodes'] as List? ?? const [])) {
      final data = Map<String, dynamic>.from(raw as Map);
      await upsertNode(_nodeFromBackup(data));
    }
    for (final raw in (payload['edges'] as List? ?? const [])) {
      final data = Map<String, dynamic>.from(raw as Map);
      await upsertEdge(_edgeFromBackup(data));
    }
  }

  KnowledgeNode _nodeFromRow(Row row) {
    return KnowledgeNode(
      id: row['id'] as String,
      type: row['type'] as String,
      title: row['title'] as String,
      content: row['content'] as String,
      tags: (jsonDecode(row['tags_json'] as String) as List).cast<String>(),
      embedding: row['embedding_json'] == null
          ? null
          : (jsonDecode(row['embedding_json'] as String) as List)
              .map((value) => (value as num).toDouble())
              .toList(),
      metadata: (jsonDecode(row['metadata_json'] as String) as Map)
          .map((key, value) => MapEntry(key as String, value as String)),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  KnowledgeNode _nodeFromBackup(Map<String, dynamic> data) => KnowledgeNode(
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

  DirectedEdge _edgeFromBackup(Map<String, dynamic> data) => DirectedEdge(
        id: data['id'] as String,
        fromId: data['fromId'] as String,
        toId: data['toId'] as String,
        relation: data['relation'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int),
      );

  DirectedEdge _edgeFromRow(Row row) => DirectedEdge(
        id: row['id'] as String,
        fromId: row['from_id'] as String,
        toId: row['to_id'] as String,
        relation: row['relation'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );

  Future<List<KnowledgeNode>> vectorSearch(
    List<double> queryEmbedding, {
    int limit = 10,
  }) async {
    final candidates = await listNodes();
    candidates.sort(
      (a, b) => _cosineDistance(queryEmbedding, a.embedding ?? const [])
          .compareTo(_cosineDistance(queryEmbedding, b.embedding ?? const [])),
    );
    return candidates.take(limit).toList();
  }

  double _cosineDistance(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return double.infinity;
    var dot = 0.0;
    var aLength = 0.0;
    var bLength = 0.0;
    for (var index = 0; index < a.length; index++) {
      dot += a[index] * b[index];
      aLength += a[index] * a[index];
      bLength += b[index] * b[index];
    }
    final denominator = math.sqrt(aLength) * math.sqrt(bLength);
    return denominator == 0 ? double.infinity : 1 - dot / denominator;
  }

  @override
  Future<void> close() async {
    await _changes.close();
    _database?.dispose();
    _database = null;
  }
}
