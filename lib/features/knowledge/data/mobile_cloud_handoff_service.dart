import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'knowledge_cloud_codec.dart';
import 'knowledge_store.dart';

class MobileCloudHandoffService {
  MobileCloudHandoffService({
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

  Future<void> activate() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final nodes =
        await _firestore.collection('users/$uid/knowledge/nodes/items').get();
    final edges =
        await _firestore.collection('users/$uid/knowledge/edges/items').get();

    for (final document in nodes.docs) {
      await localStore.upsertNode(nodeFromMap(document.data()));
    }
    for (final document in edges.docs) {
      await localStore.upsertEdge(edgeFromMap(document.data()));
    }
    for (final document in nodes.docs) {
      await document.reference.delete();
    }
    for (final document in edges.docs) {
      await document.reference.delete();
    }
  }
}
