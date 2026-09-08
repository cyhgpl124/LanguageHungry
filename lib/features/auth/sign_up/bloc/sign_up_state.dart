import '../../data/models/auth_user.dart';

sealed class SignUpState {
  const SignUpState();
}

class SignUpInitial extends SignUpState {
  const SignUpInitial();
}

class SignUpLoading extends SignUpState {
  const SignUpLoading();
}

class SignUpSuccess extends SignUpState {
  const SignUpSuccess(this.user);

  final AuthUser user;
}

class SignUpFailure extends SignUpState {
  const SignUpFailure(this.message);

  final String message;
}
