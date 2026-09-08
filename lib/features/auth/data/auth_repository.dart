import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'models/auth_user.dart';

abstract interface class AuthRepository {
  Stream<AuthUser?> get authStateChanges;
  AuthUser? get currentUser;
  Future<AuthUser?> loadCurrentUser();
  Future<void> reloadCurrentUser();
  Future<void> resendEmailVerification();
  Future<AuthUser> signIn({required String email, required String password});
  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String username,
    required String nickname,
    String? referralId,
    Uint8List? profileImage,
  });
  Future<AuthUser> signInWithGoogle();
  Future<AuthUser> saveAdditionalInfo({
    required String username,
    required String nickname,
    required String phone,
    String? referralId,
    Uint8List? profileImage,
  });
  Future<AuthUser> saveLanguagePreferences({
    required List<String> nativeLanguages,
    required List<String> learningLanguages,
  });
  Future<void> sendPasswordResetEmail(String email);
  Future<String?> findEmail({required String name, required String phone});
  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ??
            FirebaseFirestore.instanceFor(
              app: Firebase.app(),
              databaseId: 'langgry',
            );

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  static Future<void>? _googleSignInInitialization;

  Future<void> _ensureGoogleSignInInitialized() {
    return _googleSignInInitialization ??= GoogleSignIn.instance.initialize();
  }

  AuthUser? _mapUser(User? user) {
    if (user == null || user.email == null) return null;
    return AuthUser(
      id: user.uid,
      email: user.email!,
      displayName: user.displayName,
      needsEmailVerification: !user.emailVerified,
    );
  }

  Future<AuthUser> _withProfile(AuthUser user) async {
    DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _firestore.collection('users').doc(user.id).get();
    } on FirebaseException catch (error) {
      if (error.code == 'unavailable') {
        return AuthUser(
          id: user.id,
          email: user.email,
          displayName: user.displayName,
          needsAdditionalInfo: true,
        );
      }
      rethrow;
    }
    final data = snapshot.data();
    final profileComplete = data?['profileCompleted'] == true;
    final nativeLanguages = data?['nativeLanguages'] is List
        ? List<String>.from(data?['nativeLanguages'] as List)
        : data?['nativeLanguage'] is String
            ? [data?['nativeLanguage'] as String]
            : <String>[];
    final learningLanguages = data?['learningLanguages'] is List
        ? List<String>.from(data?['learningLanguages'] as List)
        : data?['learningLanguage'] is String
            ? [data?['learningLanguage'] as String]
            : <String>[];
    final languagesComplete =
        nativeLanguages.isNotEmpty && learningLanguages.isNotEmpty;
    return AuthUser(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      needsAdditionalInfo: !profileComplete,
      needsLanguageSetup: profileComplete && !languagesComplete,
      needsEmailVerification: !_auth.currentUser!.emailVerified,
    );
  }

  @override
  Future<AuthUser?> loadCurrentUser() async {
    final user = _mapUser(_auth.currentUser);
    return user == null ? null : _withProfile(user);
  }

  @override
  AuthUser? get currentUser => _mapUser(_auth.currentUser);

  @override
  Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  @override
  Future<void> resendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인된 사용자가 없습니다.');
    await user.sendEmailVerification();
  }

  @override
  Stream<AuthUser?> get authStateChanges =>
      _auth.authStateChanges().map(_mapUser);

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return _withProfile(_mapUser(result.user)!);
  }

  @override
  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String username,
    required String nickname,
    String? referralId,
    Uint8List? profileImage,
  }) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await result.user!.updateDisplayName(nickname.trim());
    await result.user!.sendEmailVerification();
    String? profileImageUrl;
    if (profileImage != null) {
      final reference = _storage.ref('users/${result.user!.uid}/profile.jpg');
      await reference.putData(
        profileImage,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      profileImageUrl = await reference.getDownloadURL();
    }
    await _firestore.collection('users').doc(result.user!.uid).set({
      'email': email.trim(),
      'username': username.trim(),
      'nickname': nickname.trim(),
      'referralId': referralId?.trim(),
      if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      'profileCompleted': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return _withProfile(_mapUser(_auth.currentUser)!);
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    UserCredential result;
    if (kIsWeb) {
      result = await _auth.signInWithPopup(GoogleAuthProvider());
    } else {
      await _ensureGoogleSignInInitialized();
      final account = await GoogleSignIn.instance.authenticate();
      final auth = account.authentication;
      result = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(
          idToken: auth.idToken,
        ),
      );
    }
    final user = _mapUser(result.user)!;
    return _withProfile(user);
  }

  @override
  Future<AuthUser> saveAdditionalInfo({
    required String username,
    required String nickname,
    required String phone,
    String? referralId,
    Uint8List? profileImage,
  }) async {
    final user = _mapUser(_auth.currentUser);
    if (user == null) {
      throw StateError('로그인된 사용자가 없습니다.');
    }
    String? profileImageUrl;
    if (profileImage != null) {
      final reference = _storage.ref('users/${user.id}/profile.jpg');
      await reference.putData(
        profileImage,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      profileImageUrl = await reference.getDownloadURL();
    }
    await _firestore.collection('users').doc(user.id).set({
      'email': user.email,
      'username': username.trim(),
      'nickname': nickname.trim(),
      'phone': phone.trim(),
      'referralId': referralId?.trim(),
      if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      'profileCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return _withProfile(user);
  }

  @override
  Future<AuthUser> saveLanguagePreferences({
    required List<String> nativeLanguages,
    required List<String> learningLanguages,
  }) async {
    final user = _mapUser(_auth.currentUser);
    if (user == null) {
      throw StateError('로그인된 사용자가 없습니다.');
    }
    await _firestore.collection('users').doc(user.id).set({
      'nativeLanguages': nativeLanguages,
      'learningLanguages': learningLanguages,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return _withProfile(user);
  }

  @override
  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  @override
  Future<String?> findEmail({
    required String name,
    required String phone,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .where('name', isEqualTo: name.trim())
        .where('phone', isEqualTo: phone.trim())
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.data()['email'] as String?;
  }

  @override
  Future<void> signOut() async {
    if (!kIsWeb) {
      await _ensureGoogleSignInInitialized();
      await GoogleSignIn.instance.signOut();
    }
    await _auth.signOut();
  }
}
