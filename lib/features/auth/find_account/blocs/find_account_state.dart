sealed class FindAccountState {
  const FindAccountState();
}

class FindAccountInitial extends FindAccountState {
  const FindAccountInitial();
}

class FindAccountLoading extends FindAccountState {
  const FindAccountLoading();
}

class FindIdSuccess extends FindAccountState {
  const FindIdSuccess(this.email);

  final String? email;
}

class ResetPasswordSuccess extends FindAccountState {
  const ResetPasswordSuccess();
}

class FindAccountFailure extends FindAccountState {
  const FindAccountFailure(this.message);

  final String message;
}
