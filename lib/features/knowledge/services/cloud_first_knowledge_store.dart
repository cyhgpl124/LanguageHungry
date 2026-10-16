import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/firebase/firestore_database.dart';
import '../models/directed_edge.dart';
import '../models/knowledge_node.dart';
import './knowledge_cloud_codec.dart';
import './knowledge_store.dart';

class CloudFirstKnowledgeStore implements KnowledgeStore {
  CloudFirstKnowledgeStore({
    required this.localStore,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? langgryFirestore();

  final KnowledgeStore localStore;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  CollectionReference<Map<String, dynamic>> _collection(String name) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('로그인된 사용자가 없습니다.');
    return _firestore.collection('users/$uid/knowledge/$name/items');
  }

  @override
  Future<void> initialize() => localStore.initialize();

  @override
  Future<KnowledgeNode> upsertNode(KnowledgeNode node) async {
    if (node.type == 'file') return upsertFile(node);
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('로그인된 사용자가 없습니다. 다시 로그인해 주세요.');
    }
    await _collection('nodes').doc(node.id).set(
          nodeToMap(node),
          SetOptions(merge: true),
        );
    await _firestore.waitForPendingWrites();
    _changes.add(null);
    return node;
  }

  @override
  Future<DirectedEdge> upsertEdge(DirectedEdge edge) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('로그인된 사용자가 없습니다. 다시 로그인해 주세요.');
    }

    await _collection('edges').doc(edge.id).set(
          edgeToMap(edge),
          SetOptions(merge: true),
        );
    await _firestore.waitForPendingWrites();
    _changes.add(null);
    return edge;
  }

  @override
  Future<List<DirectedEdge>> listEdges() async {
    final snapshot = await _collection('edges').get();
    return snapshot.docs.map((doc) => edgeFromMap(doc.data())).toList();
  }

  @override
  Future<KnowledgeNode?> findNode(String id) async {
    final document = await _collection('nodes').doc(id).get();
    return document.exists && document.data() != null
        ? nodeFromMap(document.data()!)
        : null;
  }

  @override
  Future<List<KnowledgeNode>> listNodes({String? query, String? tag}) async {
    final snapshot = await _collection('nodes').get();
    final nodes = snapshot.docs.map((doc) => nodeFromMap(doc.data())).toList();
    final normalizedQuery = query?.trim().toLowerCase() ?? '';
    final normalizedTag = tag?.trim() ?? '';
    return nodes.where((node) {
      final matchesQuery = normalizedQuery.isEmpty ||
          node.title.toLowerCase().contains(normalizedQuery) ||
          node.content.toLowerCase().contains(normalizedQuery);
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
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('로그인된 사용자가 없습니다. 다시 로그인해 주세요.');
    }
    final categoryId = base64Url.encode(utf8.encode(category));
    final categoryDocument = _firestore
        .collection('users/${user.uid}/knowledge/files/categories')
        .doc(categoryId);
    final existingCategories = await _firestore
        .collection('users/${user.uid}/knowledge/files/categories')
        .get(const GetOptions(source: Source.server));
    await categoryDocument.set({
      'name': category,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));
    await categoryDocument.collection('items').doc(categorized.id).set(
      {...nodeToMap(categorized), 'category': category},
      SetOptions(merge: true),
    );
    for (final existingCategory in existingCategories.docs) {
      if (existingCategory.id != categoryId) {
        await existingCategory.reference
            .collection('items')
            .doc(categorized.id)
            .delete();
      }
    }
    await _firestore.doc('users/${user.uid}/knowledge/files').set({
      'categories': FieldValue.arrayUnion([category]),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));
    await _firestore.waitForPendingWrites();
    _changes.add(null);
    return categorized;
  }

  @override
  Future<List<KnowledgeNode>> listFiles() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('로그인된 사용자가 없습니다. 다시 로그인해 주세요.');
    }
    final filesById = <String, KnowledgeNode>{};
    for (final file in await localStore.listFiles()) {
      filesById[file.id] = categorizedFile(file);
    }
    final localNodes = await localStore.listNodes();
    for (final node in localNodes.where((node) => node.type == 'file')) {
      filesById[node.id] = categorizedFile(node);
    }
    final categoryCollection =
        _firestore.collection('users/$uid/knowledge/files/categories');
    final categorySnapshot =
        await categoryCollection.get(const GetOptions(source: Source.server));
    for (final categoryDoc in categorySnapshot.docs) {
      final category = categoryDoc.data()['name'] as String? ?? categoryDoc.id;
      final items = await categoryDoc.reference
          .collection('items')
          .get(const GetOptions(source: Source.server));
      for (final doc in items.docs) {
        final file = _fileFromMap(doc.id, doc.data(), category);
        if (file != null) filesById[file.id] = file;
      }
      final categoryFile = _fileFromMap(categoryDoc.id, categoryDoc.data());
      if (categoryFile != null) {
        filesById[categoryFile.id] = categoryFile;
      }
    }

    final legacyFiles = await _collection('files').get(
      const GetOptions(source: Source.server),
    );
    for (final doc in legacyFiles.docs) {
      final file = _fileFromMap(doc.id, doc.data());
      if (file == null) continue;
      final categorized = categorizedFile(file);
      await upsertFile(categorized);
      await doc.reference.delete();
      filesById[categorized.id] = categorized;
    }

    final legacyNodes = await _collection('nodes')
        .where('type', isEqualTo: 'file')
        .get(const GetOptions(source: Source.server));
    for (final doc in legacyNodes.docs) {
      final file = _fileFromMap(doc.id, doc.data());
      if (file == null) continue;
      final categorized = categorizedFile(file);
      await upsertFile(categorized);
      await doc.reference.delete();
      filesById[categorized.id] = categorized;
    }

    final rootDocument = _firestore.doc('users/$uid/knowledge/files');
    final rootSnapshot =
        await rootDocument.get(const GetOptions(source: Source.server));
    final rootData = rootSnapshot.data();
    if (rootSnapshot.exists && rootData != null) {
      final file = _fileFromMap(rootSnapshot.id, rootData);
      if (file != null) {
        final categorized = categorizedFile(file);
        await upsertFile(categorized);
        filesById[categorized.id] = categorized;
        await rootDocument.set({
          'categories': FieldValue.arrayUnion(
            [fileCategoryOf(categorized)],
          ),
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }
    if (legacyFiles.docs.isNotEmpty || legacyNodes.docs.isNotEmpty) {
      await _firestore.waitForPendingWrites();
      _changes.add(null);
    }
    return filesById.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  DateTime _fileDate(Object? value) => switch (value) {
        Timestamp timestamp => timestamp.toDate(),
        int milliseconds => DateTime.fromMillisecondsSinceEpoch(milliseconds),
        String date when DateTime.tryParse(date) != null =>
          DateTime.parse(date),
        _ => DateTime.fromMillisecondsSinceEpoch(0),
      };

  KnowledgeNode? _fileFromMap(
    String documentId,
    Map<String, dynamic> data, [
    String? fallbackCategory,
  ]) {
    final rawContent = data['content'] ??
        data['html'] ??
        data['htmlContent'] ??
        data['fileContent'];
    if (rawContent is! String) return null;
    final rawMetadata = data['metadata'];
    final metadata = rawMetadata is Map
        ? rawMetadata.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
        : <String, String>{};
    final category = data['category'] as String? ??
        data['classification'] as String? ??
        metadata['category'] ??
        metadata['classification'] ??
        metadata['분류'] ??
        fallbackCategory ??
        defaultFileCategory;
    return categorizedFile(KnowledgeNode(
      id: data['id'] as String? ?? documentId,
      type: 'file',
      title: data['title'] as String? ??
          data['name'] as String? ??
          data['fileName'] as String? ??
          documentId,
      content: rawContent,
      tags: (data['tags'] as List? ?? const []).whereType<String>().toList(),
      metadata: {...metadata, 'category': category},
      createdAt: _fileDate(data['createdAt'] ?? data['created_at']),
      updatedAt: _fileDate(data['updatedAt'] ?? data['updated_at']),
    ));
  }

  @override
  Future<void> insertNode(KnowledgeNode node) => upsertNode(node);

  @override
  Future<void> deleteNode(String id) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('로그인된 사용자가 없습니다. 다시 로그인해 주세요.');
    }
    final edges = await _collection('edges').get();
    final relatedEdges = edges.docs.where((document) {
      final edge = edgeFromMap(document.data());
      return edge.fromId == id || edge.toId == id;
    });
    for (final edge in relatedEdges) {
      await edge.reference.delete();
    }
    final categories = await _firestore
        .collection('users/${user.uid}/knowledge/files/categories')
        .get(const GetOptions(source: Source.server));
    for (final category in categories.docs) {
      await category.reference.collection('items').doc(id).delete();
    }
    await _collection('files').doc(id).delete();
    await _collection('nodes').doc(id).delete();
    await localStore.deleteNode(id);
    await _firestore.waitForPendingWrites();
    _changes.add(null);
  }

  @override
  Future<String> exportJson() async {
    final files = await listFiles();
    final nodes = await _collection('nodes').get();
    final edges = await _collection('edges').get();
    return jsonEncode({
      'version': 2,
      'nodes': nodes.docs
          .where((doc) => doc.data()['type'] != 'file')
          .map((doc) => doc.data())
          .toList(),
      'files': files.map(nodeToMap).toList(),
      'edges': edges.docs.map((doc) => doc.data()).toList(),
    });
  }

  @override
  Future<void> importJson(String json) async {
    final payload = decodeMap(json);
    for (final raw in (payload['nodes'] as List? ?? const [])) {
      final data = Map<String, dynamic>.from(raw as Map);
      final node = nodeFromMap(data);
      if (node.type == 'file') {
        await upsertFile(_categorizedBackupFile(data, node));
      } else {
        await upsertNode(node);
      }
    }
    for (final raw in (payload['files'] as List? ?? const [])) {
      final data = Map<String, dynamic>.from(raw as Map);
      await upsertFile(_categorizedBackupFile(data, nodeFromMap(data)));
    }
    for (final raw in (payload['edges'] as List? ?? const [])) {
      await upsertEdge(edgeFromMap(Map<String, dynamic>.from(raw as Map)));
    }
  }

  KnowledgeNode _categorizedBackupFile(
    Map<String, dynamic> data,
    KnowledgeNode file,
  ) {
    final category = data['category'] as String? ??
        file.metadata['category'] ??
        file.metadata['classification'] ??
        file.metadata['분류'];
    return category == null
        ? categorizedFile(file)
        : file.copyWith(metadata: {...file.metadata, 'category': category});
  }

  @override
  Future<void> close() async {
    await _changes.close();
    await localStore.close();
  }

  Future<void> syncToLocalAndDeleteCloud() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final files = await listFiles();
    final nodeSnapshot = await _collection('nodes').get();
    final edgeSnapshot = await _collection('edges').get();
    final categoryCollection =
        _firestore.collection('users/$uid/knowledge/files/categories');
    final categories = await categoryCollection.get();
    final categoryItems = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final category in categories.docs) {
      final items = await category.reference.collection('items').get();
      categoryItems.addAll(items.docs);
    }
    final fileIds = files.map((file) => file.id).toSet();
    for (final doc in nodeSnapshot.docs) {
      final node = nodeFromMap({...doc.data(), 'id': doc.id});
      if (node.type == 'file') {
        fileIds.add(node.id);
        await localStore.upsertFile(node);
      } else {
        await localStore.upsertNode(node);
      }
    }
    for (final file in files) {
      await localStore.upsertFile(file);
    }
    for (final document in categoryItems) {
      await document.reference.delete();
    }
    for (final category in categories.docs) {
      await category.reference.delete();
    }
    for (final doc in edgeSnapshot.docs) {
      final edge = edgeFromMap(doc.data());
      if (fileIds.contains(edge.fromId) || fileIds.contains(edge.toId)) {
        continue;
      }
      try {
        await localStore.upsertEdge(edge);
      } on FirebaseException {
        rethrow;
      }
    }
    for (final doc in nodeSnapshot.docs) {
      await doc.reference.delete();
    }
    for (final doc in edgeSnapshot.docs) {
      await doc.reference.delete();
    }
    await _firestore.doc('users/$uid/knowledge/files').delete();
  }
}
