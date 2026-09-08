import '../data/models/find_account_model.dart';

sealed class FindAccountEvent {
  const FindAccountEvent();
}

class FindIdSubmitted extends FindAccountEvent {
  const FindIdSubmitted(this.model);

  final FindAccountModel model;
}

class ResetPasswordSubmitted extends FindAccountEvent {
  const ResetPasswordSubmitted(this.model);

  final FindAccountModel model;
}
