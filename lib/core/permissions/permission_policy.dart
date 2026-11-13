import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:langgry/core/firebase/firestore_database.dart';

enum PermissionTier {
  superAdmin('superAdmin', '최고 권한'),
  partner('partner', '파트너 권한'),
  free('free', '회원 권한 1 (Free)'),
  pro('pro', '회원 권한 2 (Pro)'),
  premium('premium', '회원 권한 3 (Premium)');

  const PermissionTier(this.key, this.label);

  final String key;
  final String label;

  static PermissionTier fromKey(Object? key) => values.firstWhere(
        (tier) => tier.key == key,
        orElse: () => PermissionTier.free,
      );
}

class PermissionFeature {
  const PermissionFeature(this.key, this.label);

  final String key;
  final String label;
}

class PermissionFeatures {
  PermissionFeatures._();

  static const home = PermissionFeature('home', '홈 화면');
  static const aiTools = PermissionFeature('aiTools', 'AI 기능');
  static const chat = PermissionFeature('chat', '채팅 및 친구 목록');
  static const chatSetup = PermissionFeature('chatSetup', '채팅방 생성 및 설정');
  static const chatRoom = PermissionFeature('chatRoom', '채팅방 대화');
  static const chatGallery = PermissionFeature('chatGallery', '채팅 갤러리');
  static const fileImport = PermissionFeature('fileImport', '파일 가져오기 및 분석');
  static const memos = PermissionFeature('memos', '메모 및 지식 공간');
  static const memoCanvas = PermissionFeature('memoCanvas', '모듈형 메모 캔버스');
  static const memoAssistant = PermissionFeature('memoAssistant', '메모 AI 어시스턴트');
  static const memoHistory = PermissionFeature('memoHistory', '메모 버전 및 AI 히스토리');
  static const dynamicLists = PermissionFeature('dynamicLists', '사용자 지정 리스트');
  static const plots = PermissionFeature('plots', '플롯');
  static const globalMemo = PermissionFeature('globalMemo', '빠른 메모 생성');
  static const market = PermissionFeature('market', '마켓');
  static const profile = PermissionFeature('profile', '마이페이지');
  static const profileEdit = PermissionFeature('profileEdit', '프로필 편집');
  static const languageSettings =
      PermissionFeature('languageSettings', '언어 설정');
  static const permissionSettings =
      PermissionFeature('permissionSettings', '권한 설정');
  static const webView = PermissionFeature('webView', '공통 웹뷰');
  static const aiMultiModeAssistant =
      PermissionFeature('aiMultiModeAssistant', 'AI 멀티 모드 어시스턴트');
  static const findAccount = PermissionFeature('findAccount', '계정 찾기');
  static const terms = PermissionFeature('terms', '이용약관 및 정책');
  static const onboarding = PermissionFeature('onboarding', '온보딩 및 초기 설정');
  static const htmlPreview = PermissionFeature('htmlPreview', 'HTML 미리보기 및 복원');

  static const all = <PermissionFeature>[
    home,
    aiTools,
    chat,
    chatSetup,
    chatRoom,
    chatGallery,
    fileImport,
    memos,
    memoCanvas,
    memoAssistant,
    memoHistory,
    dynamicLists,
    plots,
    globalMemo,
    market,
    profile,
    profileEdit,
    languageSettings,
    permissionSettings,
    webView,
    aiMultiModeAssistant,
    findAccount,
    terms,
    onboarding,
    htmlPreview,
  ];
}

class PermissionMatrix {
  PermissionMatrix(Map<String, Map<PermissionTier, bool>> grants)
      : _grants = grants;

  factory PermissionMatrix.allEnabled() => PermissionMatrix({
        for (final feature in PermissionFeatures.all)
          feature.key: {
            for (final tier in PermissionTier.values) tier: true,
          },
      });

  factory PermissionMatrix.fromMap(Object? value) {
    final defaults = PermissionMatrix.allEnabled();
    if (value is! Map) return defaults;

    final parsed = <String, Map<PermissionTier, bool>>{};
    for (final feature in PermissionFeatures.all) {
      final row = value[feature.key];
      parsed[feature.key] = {
        for (final tier in PermissionTier.values)
          tier: row is Map && row[tier.key] is bool
              ? row[tier.key] as bool
              : defaults.allows(feature.key, tier),
      };
    }
    return PermissionMatrix(parsed);
  }

  final Map<String, Map<PermissionTier, bool>> _grants;

  bool allows(String featureKey, PermissionTier tier) {
    if (tier == PermissionTier.superAdmin) return true;
    return _grants[featureKey]?[tier] ?? true;
  }

  PermissionMatrix withGrant(
    String featureKey,
    PermissionTier tier,
    bool allowed,
  ) {
    return PermissionMatrix({
      for (final feature in PermissionFeatures.all)
        feature.key: {
          for (final role in PermissionTier.values)
            role: feature.key == featureKey && role == tier
                ? allowed
                : allows(feature.key, role),
        },
    });
  }

  Map<String, Map<String, bool>> toMap() => {
        for (final feature in PermissionFeatures.all)
          feature.key: {
            for (final tier in PermissionTier.values)
              tier.key: allows(feature.key, tier),
          },
      };
}

abstract interface class PermissionPolicyRepository {
  Future<PermissionTier> currentTier();
  Future<PermissionMatrix> loadMatrix();
  Future<void> saveMatrix(PermissionMatrix matrix);
  bool get isSuperuser;
  bool get isUsingDefaultMatrix;
  void invalidateCache();
}

class FirebasePermissionPolicyRepository implements PermissionPolicyRepository {
  FirebasePermissionPolicyRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? langgryFirestore();

  static const superuserEmail = 'cyhgpl@gmail.com';
  static const _permissionsDocument = 'appConfig/permissions';
  static const _cacheDuration = Duration(seconds: 30);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  Future<PermissionTier>? _tierFuture;
  Future<PermissionMatrix>? _matrixFuture;
  DateTime? _tierCacheExpiresAt;
  DateTime? _matrixCacheExpiresAt;
  bool _isUsingDefaultMatrix = false;

  @override
  bool get isSuperuser =>
      _auth.currentUser?.email?.toLowerCase() == superuserEmail;

  @override
  bool get isUsingDefaultMatrix => _isUsingDefaultMatrix;

  @override
  void invalidateCache() {
    _tierFuture = null;
    _matrixFuture = null;
    _tierCacheExpiresAt = null;
    _matrixCacheExpiresAt = null;
    _isUsingDefaultMatrix = false;
  }

  @override
  Future<PermissionTier> currentTier() {
    if (isSuperuser) return Future.value(PermissionTier.superAdmin);
    if (_tierFuture != null &&
        _tierCacheExpiresAt?.isAfter(DateTime.now()) == true) {
      return _tierFuture!;
    }
    _tierCacheExpiresAt = DateTime.now().add(_cacheDuration);
    return _tierFuture = _loadTier();
  }

  Future<PermissionTier> _loadTier() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인된 사용자가 없습니다.');
    final profile = await _firestore.collection('users').doc(user.uid).get();
    return PermissionTier.fromKey(profile.data()?['permissionTier']);
  }

  @override
  Future<PermissionMatrix> loadMatrix() {
    if (_matrixFuture != null &&
        _matrixCacheExpiresAt?.isAfter(DateTime.now()) == true) {
      return _matrixFuture!;
    }
    _matrixCacheExpiresAt = DateTime.now().add(_cacheDuration);
    return _matrixFuture = _loadMatrix();
  }

  Future<PermissionMatrix> _loadMatrix() async {
    try {
      final snapshot = await _firestore.doc(_permissionsDocument).get();
      _isUsingDefaultMatrix = false;
      return PermissionMatrix.fromMap(snapshot.data()?['matrix']);
    } on FirebaseException catch (error) {
      if (!isSuperuser || error.code != 'permission-denied') rethrow;
      _isUsingDefaultMatrix = true;
      return PermissionMatrix.allEnabled();
    }
  }

  @override
  Future<void> saveMatrix(PermissionMatrix matrix) async {
    if (!isSuperuser) {
      throw StateError('최고 권한자만 권한을 변경할 수 있습니다.');
    }
    await _firestore.doc(_permissionsDocument).set({
      'matrix': matrix.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _auth.currentUser!.uid,
    });
    _matrixFuture = Future.value(matrix);
    _matrixCacheExpiresAt = DateTime.now().add(_cacheDuration);
    _isUsingDefaultMatrix = false;
  }
}
