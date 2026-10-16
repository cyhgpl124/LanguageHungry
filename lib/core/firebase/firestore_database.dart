import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

const firestoreDatabaseId = 'langgry';

FirebaseFirestore langgryFirestore({FirebaseApp? app}) {
  return FirebaseFirestore.instanceFor(
    app: app ?? Firebase.app(),
    databaseId: firestoreDatabaseId,
  );
}
