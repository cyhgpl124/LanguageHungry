import '../data/models/sign_up_model.dart';

sealed class SignUpEvent {
  const SignUpEvent();
}

class SignUpSubmitted extends SignUpEvent {
  const SignUpSubmitted(this.model);

  final SignUpModel model;
}
