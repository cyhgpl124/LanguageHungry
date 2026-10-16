import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/firebase/firestore_database.dart';
import './knowledge_cloud_codec.dart';
import './knowledge_store.dart';

class MobileCloudHandoffService {
  MobileCloudHandoffService({
    required this.localStore,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? langgryFirestore();

  final KnowledgeStore localStore;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<void> activate() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final nodes =
        await _firestore.collection('users/$uid/knowledge/nodes/items').get();
    final legacyFiles =
        await _firestore.collection('users/$uid/knowledge/files/items').get();
    final categories = await _firestore
        .collection('users/$uid/knowledge/files/categories')
        .get();
    final edges =
        await _firestore.collection('users/$uid/knowledge/edges/items').get();

    final fileIds = <String>{};
    final importedFileDocuments = <DocumentReference<Map<String, dynamic>>>[];
    for (final document in nodes.docs) {
      final node = nodeFromMap({...document.data(), 'id': document.id});
      if (node.type == 'file') {
        fileIds.add(node.id);
        await localStore.upsertFile(categorizedFile(node));
        importedFileDocuments.add(document.reference);
      } else {
        await localStore.upsertNode(node);
      }
    }
    for (final document in legacyFiles.docs) {
      final file = nodeFromMap({...document.data(), 'id': document.id});
      fileIds.add(file.id);
      await localStore.upsertFile(categorizedFile(file));
      importedFileDocuments.add(document.reference);
    }
    final categorizedFileDocuments =
        <DocumentReference<Map<String, dynamic>>>[];
    for (final category in categories.docs) {
      final categoryName = category.data()['name'] as String? ?? category.id;
      final files = await category.reference.collection('items').get();
      for (final document in files.docs) {
        final data = {
          ...document.data(),
          'id': document.id,
          'category': categoryName,
          'metadata': {
            ...((document.data()['metadata'] as Map?)?.map(
                  (key, value) => MapEntry(key.toString(), value.toString()),
                ) ??
                const <String, String>{}),
            'category': categoryName,
          },
        };
        final file = nodeFromMap(data);
        fileIds.add(file.id);
        await localStore.upsertFile(categorizedFile(file));
        categorizedFileDocuments.add(document.reference);
      }
    }
    for (final document in edges.docs) {
      final edge = edgeFromMap(document.data());
      if (!fileIds.contains(edge.fromId) && !fileIds.contains(edge.toId)) {
        await localStore.upsertEdge(edge);
      }
    }
    for (final document in importedFileDocuments) {
      await document.delete();
    }
    for (final document in nodes.docs.where(
      (document) => !fileIds.contains(document.id),
    )) {
      await document.reference.delete();
    }
    for (final document in edges.docs) {
      await document.reference.delete();
    }
    for (final document in categorizedFileDocuments) {
      await document.delete();
    }
    for (final category in categories.docs) {
      await category.reference.delete();
    }
  }
}
