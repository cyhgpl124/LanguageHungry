import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'knowledge_store.dart';

class EncryptedBackupService {
  EncryptedBackupService({
    required this.store,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final KnowledgeStore store;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final _cipher = AesGcm.with256bits();
  final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 120000,
    bits: 256,
  );

  Future<String> upload({required String passphrase}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인된 사용자가 없습니다.');
    final plaintext = utf8.encode(await store.exportJson());
    final encrypted = await _encrypt(plaintext, passphrase);
    final reference = _storage.ref(
      'users/${user.uid}/backups/${DateTime.now().toUtc().toIso8601String()}.lgb',
    );
    await reference.putData(
      encrypted,
      SettableMetadata(
        contentType: 'application/octet-stream',
        customMetadata: {'format': 'langgry-e2ee-v1'},
      ),
    );
    return reference.fullPath;
  }

  Future<void> restore({
    required String backupPath,
    required String passphrase,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인된 사용자가 없습니다.');
    if (!backupPath.startsWith('users/${user.uid}/backups/')) {
      throw ArgumentError('현재 사용자의 백업 경로만 복원할 수 있습니다.');
    }
    final bytes = await _storage.ref(backupPath).getData(50 * 1024 * 1024);
    if (bytes == null) throw StateError('백업 파일을 읽을 수 없습니다.');
    final plaintext = await _decrypt(bytes, passphrase);
    await store.importJson(utf8.decode(plaintext));
  }

  Future<Uint8List> _encrypt(List<int> plaintext, String passphrase) async {
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );
    return Uint8List.fromList([
      ...utf8.encode('LGB1'),
      ...salt,
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<List<int>> _decrypt(List<int> payload, String passphrase) async {
    final header = utf8.decode(payload.sublist(0, 4));
    if (header != 'LGB1' || payload.length < 4 + 16 + 12 + 16) {
      throw const FormatException('지원하지 않는 백업 형식입니다.');
    }
    final salt = payload.sublist(4, 20);
    final nonce = payload.sublist(20, 32);
    final cipherText = payload.sublist(32, payload.length - 16);
    final mac = Mac(payload.sublist(payload.length - 16));
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    try {
      return await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: key,
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('비밀번호가 틀렸거나 백업이 손상되었습니다.');
    }
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
