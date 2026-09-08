import '../data/models/login_model.dart';

sealed class LoginEvent {
  const LoginEvent();
}

class LoginSubmitted extends LoginEvent {
  const LoginSubmitted(this.model);

  final LoginModel model;
}

class GoogleLoginSubmitted extends LoginEvent {
  const GoogleLoginSubmitted();
}
