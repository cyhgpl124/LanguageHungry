import '../../data/auth_repository.dart';
import '../../data/models/auth_user.dart';
import 'models/sign_up_model.dart';

class SignUpRepository {
  const SignUpRepository(this._authRepository);

  final AuthRepository _authRepository;

  Future<AuthUser> signUp(SignUpModel model) {
    return _authRepository.signUp(
      email: model.email,
      password: model.password,
      username: model.username,
      nickname: model.nickname,
      referralId: model.referralId,
      profileImage: model.profileImage,
    );
  }
}
