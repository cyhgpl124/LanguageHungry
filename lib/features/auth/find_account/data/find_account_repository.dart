import '../../data/auth_repository.dart';
import 'models/find_account_model.dart';

class FindAccountRepository {
  const FindAccountRepository(this._authRepository);

  final AuthRepository _authRepository;

  Future<String?> findEmail(FindAccountModel model) {
    return _authRepository.findEmail(
      name: model.name,
      phone: model.phone,
    );
  }

  Future<void> resetPassword(FindAccountModel model) {
    return _authRepository.sendPasswordResetEmail(model.email);
  }
}
