import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/sign_up_repository.dart';
import 'sign_up_event.dart';
import 'sign_up_state.dart';

class SignUpBloc extends Bloc<SignUpEvent, SignUpState> {
  SignUpBloc(this._repository) : super(const SignUpInitial()) {
    on<SignUpSubmitted>(_onSubmitted);
  }

  final SignUpRepository _repository;

  Future<void> _onSubmitted(
    SignUpSubmitted event,
    Emitter<SignUpState> emit,
  ) async {
    emit(const SignUpLoading());
    try {
      emit(SignUpSuccess(await _repository.signUp(event.model)));
    } on FirebaseAuthException catch (error) {
      final message = error.code == 'email-already-in-use'
          ? '이미 가입된 이메일입니다.'
          : error.code == 'weak-password'
              ? '비밀번호는 6자 이상으로 입력해 주세요.'
              : error.message ?? '회원가입 중 문제가 발생했습니다.';
      emit(SignUpFailure(message));
    } catch (error) {
      emit(SignUpFailure(error.toString()));
    }
  }
}
