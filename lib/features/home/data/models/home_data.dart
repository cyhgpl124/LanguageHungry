class HomeData {
  const HomeData({
    required this.email,
    this.username,
    this.nickname,
    this.phone,
    this.bio,
    this.profileImageUrl,
    this.profileImageVersion,
    this.nativeLanguages = const [],
    this.learningLanguages = const [],
    this.activeNativeLanguage,
    this.activeLearningLanguage,
    this.streakDays = 0,
    this.totalStudyMinutes = 0,
    this.reviewCount = 0,
  });

  final String email;
  final String? username;
  final String? nickname;
  final String? phone;
  final String? bio;
  final String? profileImageUrl;
  final int? profileImageVersion;
  final List<String> nativeLanguages;
  final List<String> learningLanguages;
  final String? activeNativeLanguage;
  final String? activeLearningLanguage;
  final int streakDays;
  final int totalStudyMinutes;
  final int reviewCount;

  String get displayName =>
      nickname?.trim().isNotEmpty == true ? nickname! : email.split('@').first;
}
