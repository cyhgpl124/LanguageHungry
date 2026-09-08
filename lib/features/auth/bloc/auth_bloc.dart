import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/auth_repository.dart';
import '../data/models/auth_user.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._repository) : super(const AuthInitial()) {
    on<AuthStarted>(_onStarted);
    on<AuthSessionChanged>(_onSessionChanged);
    on<AuthProfileUpdated>(_onProfileUpdated);
    on<AuthEmailSignedIn>(_onEmailSignedIn);
    on<AuthGoogleSignedIn>(_onGoogleSignedIn);
    on<AuthRegistered>(_onRegistered);
    on<AuthSignedOut>(_onSignedOut);
  }

  final AuthRepository _repository;
  StreamSubscription<AuthUser?>? _subscription;

  Future<void> _onStarted(
    AuthStarted event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    _subscription ??= _repository.authStateChanges.listen(
      (user) => add(AuthSessionChanged(user)),
    );
    add(AuthSessionChanged(_repository.currentUser));
  }

  Future<void> _onSessionChanged(
    AuthSessionChanged event,
    Emitter<AuthState> emit,
  ) async {
    try {
      final user = event.user;
      emit(user == null
          ? const AuthUnauthenticated()
          : AuthAuthenticated(await _repository.loadCurrentUser() ?? user));
    } on FirebaseException catch (error) {
      emit(AuthFailure(_messageForFirestore(error)));
    } catch (error) {
      emit(AuthFailure(error.toString()));
    }
  }

  Future<void> _onProfileUpdated(
    AuthProfileUpdated event,
    Emitter<AuthState> emit,
  ) async {
    try {
      final user = await _repository.loadCurrentUser();
      emit(
          user == null ? const AuthUnauthenticated() : AuthAuthenticated(user));
    } on FirebaseException catch (error) {
      emit(AuthFailure(_messageForFirestore(error)));
    } catch (error) {
      emit(AuthFailure(error.toString()));
    }
  }

  Future<void> _onEmailSignedIn(
    AuthEmailSignedIn event,
    Emitter<AuthState> emit,
  ) async {
    await _runAuthAction(emit, () {
      return _repository.signIn(email: event.email, password: event.password);
    });
  }

  Future<void> _onGoogleSignedIn(
    AuthGoogleSignedIn event,
    Emitter<AuthState> emit,
  ) async {
    await _runAuthAction(emit, _repository.signInWithGoogle);
  }

  Future<void> _onRegistered(
    AuthRegistered event,
    Emitter<AuthState> emit,
  ) async {
    await _runAuthAction(emit, () {
      return _repository.signUp(
        email: event.email,
        password: event.password,
        username: event.name,
        nickname: event.name,
      );
    });
  }

  Future<void> _runAuthAction(
    Emitter<AuthState> emit,
    Future<AuthUser> Function() action,
  ) async {
    emit(const AuthLoading());
    try {
      emit(AuthAuthenticated(await action()));
    } on FirebaseAuthException catch (error) {
      emit(AuthFailure(_messageFor(error)));
    } on FirebaseException catch (error) {
      emit(AuthFailure(_messageForFirestore(error)));
    } catch (error) {
      emit(AuthFailure(error.toString()));
    }
  }

  String _messageFor(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return '이메일 또는 비밀번호를 확인해 주세요.';
      case 'email-already-in-use':
        return '이미 가입된 이메일입니다.';
      case 'weak-password':
        return '비밀번호는 6자 이상으로 입력해 주세요.';
      case 'invalid-email':
        return '올바른 이메일 주소를 입력해 주세요.';
      case 'sign-in-cancelled':
        return 'Google 로그인이 취소되었습니다.';
      default:
        return error.message ?? '인증 중 문제가 발생했습니다.';
    }
  }

  String _messageForFirestore(FirebaseException error) {
    if (error.plugin == 'cloud_firestore' && error.code == 'unavailable') {
      return '사용자 정보를 불러오려면 인터넷 연결이 필요합니다. '
          '네트워크를 확인한 뒤 다시 시도해 주세요.';
    }
    return error.message ?? '사용자 정보를 불러오는 중 문제가 발생했습니다.';
  }

  Future<void> _onSignedOut(
    AuthSignedOut event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    await _repository.signOut();
    emit(const AuthUnauthenticated());
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
