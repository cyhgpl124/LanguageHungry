import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../domain/entities/directed_edge.dart';
import '../domain/entities/knowledge_node.dart';
import 'knowledge_cloud_codec.dart';
import 'knowledge_store.dart';

class CloudFirstKnowledgeStore implements KnowledgeStore {
  CloudFirstKnowledgeStore({
    required this.localStore,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ??
            FirebaseFirestore.instanceFor(
              app: Firebase.app(),
              databaseId: 'langgry',
            );

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
  Future<void> insertNode(KnowledgeNode node) => upsertNode(node);

  @override
  Future<String> exportJson() async {
    final nodes = await _collection('nodes').get();
    final edges = await _collection('edges').get();
    return jsonEncode({
      'version': 1,
      'nodes': nodes.docs.map((doc) => doc.data()).toList(),
      'edges': edges.docs.map((doc) => doc.data()).toList(),
    });
  }

  @override
  Future<void> importJson(String json) async {
    final payload = decodeMap(json);
    for (final raw in (payload['nodes'] as List? ?? const [])) {
      await upsertNode(nodeFromMap(Map<String, dynamic>.from(raw as Map)));
    }
    for (final raw in (payload['edges'] as List? ?? const [])) {
      await upsertEdge(edgeFromMap(Map<String, dynamic>.from(raw as Map)));
    }
  }

  @override
  Future<void> close() async {
    await _changes.close();
    await localStore.close();
  }

  Future<void> syncToLocalAndDeleteCloud() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final nodeSnapshot = await _collection('nodes').get();
    final edgeSnapshot = await _collection('edges').get();
    for (final doc in nodeSnapshot.docs) {
      await localStore.upsertNode(nodeFromMap(doc.data()));
    }
    for (final doc in edgeSnapshot.docs) {
      final edge = edgeFromMap(doc.data());
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
  }
}
