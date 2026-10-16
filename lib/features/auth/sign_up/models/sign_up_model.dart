import 'dart:typed_data';

class SignUpModel {
  const SignUpModel({
    required this.email,
    required this.password,
    required this.username,
    required this.nickname,
    this.referralId,
    this.profileImage,
  });

  final String email;
  final String password;
  final String username;
  final String nickname;
  final String? referralId;
  final Uint8List? profileImage;
}
