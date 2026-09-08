import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/find_account_repository.dart';
import 'find_account_event.dart';
import 'find_account_state.dart';

class FindAccountBloc extends Bloc<FindAccountEvent, FindAccountState> {
  FindAccountBloc(this._repository) : super(const FindAccountInitial()) {
    on<FindIdSubmitted>(_onFindId);
    on<ResetPasswordSubmitted>(_onResetPassword);
  }

  final FindAccountRepository _repository;

  Future<void> _onFindId(
    FindIdSubmitted event,
    Emitter<FindAccountState> emit,
  ) async {
    emit(const FindAccountLoading());
    try {
      emit(FindIdSuccess(await _repository.findEmail(event.model)));
    } catch (error) {
      emit(FindAccountFailure(error.toString()));
    }
  }

  Future<void> _onResetPassword(
    ResetPasswordSubmitted event,
    Emitter<FindAccountState> emit,
  ) async {
    emit(const FindAccountLoading());
    try {
      await _repository.resetPassword(event.model);
      emit(const ResetPasswordSuccess());
    } catch (_) {
      emit(const FindAccountFailure('메일을 보내지 못했습니다. 이메일을 확인해 주세요.'));
    }
  }
}
