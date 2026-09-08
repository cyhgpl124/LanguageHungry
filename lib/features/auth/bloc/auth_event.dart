import '../data/models/auth_user.dart';

sealed class AuthEvent {
  const AuthEvent();
}

class AuthStarted extends AuthEvent {
  const AuthStarted();
}

class AuthSessionChanged extends AuthEvent {
  const AuthSessionChanged(this.user);

  final AuthUser? user;
}

class AuthProfileUpdated extends AuthEvent {
  const AuthProfileUpdated();
}

class AuthEmailSignedIn extends AuthEvent {
  const AuthEmailSignedIn(this.email, this.password);

  final String email;
  final String password;
}

class AuthGoogleSignedIn extends AuthEvent {
  const AuthGoogleSignedIn();
}

class AuthRegistered extends AuthEvent {
  const AuthRegistered({
    required this.email,
    required this.password,
    required this.name,
    required this.phone,
  });

  final String email;
  final String password;
  final String name;
  final String phone;
}

class AuthSignedOut extends AuthEvent {
  const AuthSignedOut();
}
