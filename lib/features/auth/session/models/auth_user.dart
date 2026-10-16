class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.needsAdditionalInfo = false,
    this.needsLanguageSetup = false,
    this.needsEmailVerification = false,
  });

  final String id;
  final String email;
  final String? displayName;
  final bool needsAdditionalInfo;
  final bool needsLanguageSetup;
  final bool needsEmailVerification;
}
