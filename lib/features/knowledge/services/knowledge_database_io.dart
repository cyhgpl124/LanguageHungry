import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import './knowledge_store.dart';
import '../models/directed_edge.dart';
import '../models/knowledge_node.dart';

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
    database.execute('''
      CREATE TABLE IF NOT EXISTS files (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        tags_json TEXT NOT NULL,
        embedding_json TEXT,
        metadata_json TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '기존 파일',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    final fileColumns = database.select('PRAGMA table_info(files)');
    if (!fileColumns.any((column) => column['name'] == 'category')) {
      database.execute(
        "ALTER TABLE files ADD COLUMN category TEXT NOT NULL DEFAULT '기존 파일';",
      );
    }
    final legacyFiles =
        database.select("SELECT * FROM nodes WHERE type = 'file'");
    for (final row in legacyFiles) {
      final file = _nodeFromRow(row);
      final category = fileCategoryOf(file);
      final categorized = categorizedFile(file);
      _insertFile(database, categorized, category);
    }
    database.execute('''
      DELETE FROM directed_edges
      WHERE from_id IN (SELECT id FROM nodes WHERE type = 'file')
         OR to_id IN (SELECT id FROM nodes WHERE type = 'file');
    ''');
    database.execute("DELETE FROM nodes WHERE type = 'file';");
    for (final row in database.select('SELECT * FROM files')) {
      final file = _nodeFromRow(row);
      final category = fileCategoryOf(file);
      _insertFile(database, categorizedFile(file), category);
    }
    database.execute(
      'CREATE INDEX IF NOT EXISTS files_category ON files(category);',
    );
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
    if (node.type == 'file') return upsertFile(node);
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
  Future<KnowledgeNode> upsertFile(KnowledgeNode file) async {
    final categorized = categorizedFile(file);
    final category = fileCategoryOf(categorized);
    _insertFile(_db, categorized, category);
    _changes.add(null);
    return categorized;
  }

  void _insertFile(Database database, KnowledgeNode file, String category) {
    database.execute('''
      INSERT INTO files
        (id, type, title, content, tags_json, embedding_json, metadata_json, category, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        content = excluded.content,
        tags_json = excluded.tags_json,
        embedding_json = excluded.embedding_json,
        metadata_json = excluded.metadata_json,
        category = excluded.category,
        updated_at = excluded.updated_at
      WHERE excluded.updated_at > files.updated_at
         OR excluded.category != files.category
    ''', [
      file.id,
      file.type,
      file.title,
      file.content,
      jsonEncode(file.tags),
      file.embedding == null ? null : jsonEncode(file.embedding),
      jsonEncode(file.metadata),
      category,
      file.createdAt.millisecondsSinceEpoch,
      file.updatedAt.millisecondsSinceEpoch,
    ]);
  }

  @override
  Future<List<KnowledgeNode>> listFiles() async {
    final rows = _db.select('SELECT * FROM files ORDER BY updated_at DESC');
    return rows.map((row) {
      final file = _nodeFromRow(row);
      return categorizedFile(
        file.copyWith(
          metadata: {
            ...file.metadata,
            'category': row['category'] as String,
          },
        ),
      );
    }).toList();
  }

  @override
  Future<void> insertNode(KnowledgeNode node) => upsertNode(node);

  @override
  Future<void> deleteNode(String id) async {
    _db.execute('DELETE FROM nodes WHERE id = ?', [id]);
    _db.execute('DELETE FROM files WHERE id = ?', [id]);
    _changes.add(null);
  }

  @override
  Future<String> exportJson() async {
    final nodes = _db.select('SELECT * FROM nodes');
    final files = _db.select('SELECT * FROM files');
    final edges = _db.select('SELECT * FROM directed_edges');
    return jsonEncode({
      'version': 2,
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
      'files': files
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
                'category': row['category'],
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
    final fileIds = <String>{};
    for (final raw in (payload['nodes'] as List? ?? const [])) {
      final data = Map<String, dynamic>.from(raw as Map);
      final node = _nodeFromBackup(data);
      if (node.type == 'file') {
        fileIds.add(node.id);
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
      final file = _nodeFromBackup(data);
      fileIds.add(file.id);
      final metadataCategory = file.metadata['category'] ??
          file.metadata['classification'] ??
          file.metadata['분류'];
      final category = data['category'] as String? ?? metadataCategory;
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
      final edge = _edgeFromBackup(data);
      if (!fileIds.contains(edge.fromId) && !fileIds.contains(edge.toId)) {
        await upsertEdge(edge);
      }
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
