import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/login_repository.dart';
import 'login_event.dart';
import 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc(this._repository) : super(const LoginInitial()) {
    on<LoginSubmitted>(_onLogin);
    on<GoogleLoginSubmitted>(_onGoogleLogin);
  }

  final LoginRepository _repository;

  Future<void> _onLogin(
    LoginSubmitted event,
    Emitter<LoginState> emit,
  ) async {
    await _run(emit, () => _repository.login(event.model));
  }

  Future<void> _onGoogleLogin(
    GoogleLoginSubmitted event,
    Emitter<LoginState> emit,
  ) async {
    await _run(emit, _repository.loginWithGoogle);
  }

  Future<void> _run(
    Emitter<LoginState> emit,
    Future<dynamic> Function() action,
  ) async {
    emit(const LoginLoading());
    try {
      emit(LoginSuccess(await action()));
    } on FirebaseAuthException catch (error) {
      emit(LoginFailure(_messageFor(error)));
    } on FirebaseException catch (error) {
      emit(LoginFailure(_messageForFirebase(error)));
    } catch (error) {
      emit(LoginFailure(error.toString()));
    }
  }

  String _messageFor(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return '이메일 또는 비밀번호를 확인해 주세요.';
      case 'invalid-email':
        return '올바른 이메일 주소를 입력해 주세요.';
      case 'sign-in-cancelled':
      case 'popup-closed-by-user':
        return 'Google 로그인이 취소되었습니다. 다시 시도해 주세요.';
      default:
        return error.message ?? '로그인 중 문제가 발생했습니다.';
    }
  }

  String _messageForFirebase(FirebaseException error) {
    if (error.plugin == 'firebase_app_check') {
      return '보안 인증에 실패했습니다. 잠시 후 다시 시도해 주세요.';
    }
    if (error.plugin == 'cloud_firestore' && error.code == 'unavailable') {
      return '로그인은 완료되었지만 사용자 정보를 저장하려면 인터넷 연결이 필요합니다.';
    }
    return error.message ?? '로그인 중 문제가 발생했습니다.';
  }
}
