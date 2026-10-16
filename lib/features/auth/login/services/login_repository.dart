import '../../session/services/auth_repository.dart';
import '../../session/models/auth_user.dart';
import '../models/login_model.dart';

class LoginRepository {
  const LoginRepository(this._authRepository);

  final AuthRepository _authRepository;

  Future<AuthUser> login(LoginModel model) {
    return _authRepository.signIn(
      email: model.email,
      password: model.password,
    );
  }

  Future<AuthUser> loginWithGoogle() => _authRepository.signInWithGoogle();
}
