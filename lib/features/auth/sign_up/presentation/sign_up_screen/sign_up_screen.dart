import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/auth_repository.dart';
import '../../bloc/sign_up_bloc.dart';
import '../../bloc/sign_up_event.dart';
import '../../bloc/sign_up_state.dart';
import '../../data/models/sign_up_model.dart';
import '../../data/sign_up_repository.dart';
import '../../../presentation/widgets/auth_scaffold.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({required this.onTerms, super.key});

  final VoidCallback onTerms;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _nickname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _referralId = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _profileImage;
  bool _agree = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  @override
  void dispose() {
    _username.dispose();
    _nickname.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    _referralId.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (mounted) setState(() => _profileImage = bytes);
  }

  InputDecoration _decoration(String label, {String? hint, Widget? suffix}) =>
      InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SignUpBloc(
        SignUpRepository(context.read<AuthRepository>()),
      ),
      child: BlocListener<SignUpBloc, SignUpState>(
        listener: (context, state) {
          if (state is SignUpFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: AuthScaffold(
          title: '랭그리 회원가입',
          subtitle: '랭그리와 함께 언어 학습을 시작하세요.',
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: InkWell(
                    onTap: _pickImage,
                    customBorder: const CircleBorder(),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 78,
                          backgroundColor: const Color(0xff22272a),
                          backgroundImage: _profileImage == null
                              ? null
                              : MemoryImage(_profileImage!),
                          child: _profileImage == null
                              ? const Icon(Icons.person_rounded,
                                  size: 86, color: Colors.white54)
                              : null,
                        ),
                        const Positioned(
                          right: 2,
                          bottom: 2,
                          child: CircleAvatar(
                            radius: 22,
                            child: Icon(Icons.camera_alt_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(child: Text('프로필 사진을 눌러 업로드하세요')),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _username,
                          decoration:
                              _decoration('아이디', hint: '영문, 숫자, 밑줄(_)만 사용'),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.length < 3) return '아이디는 3자 이상 입력해 주세요.';
                            if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(text)) {
                              return '영문, 숫자, 밑줄(_)만 사용해 주세요.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nickname,
                          decoration: _decoration('닉네임'),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? '닉네임을 입력해 주세요.'
                                  : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _decoration('이메일'),
                          validator: (value) =>
                              value != null && value.contains('@')
                                  ? null
                                  : '이메일을 입력해 주세요.',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscurePassword,
                          decoration: _decoration(
                            '비밀번호',
                            hint: '6자 이상',
                            suffix: IconButton(
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                            ),
                          ),
                          validator: (value) =>
                              value != null && value.length >= 6
                                  ? null
                                  : '6자 이상 입력해 주세요.',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmation,
                          obscureText: _obscureConfirmation,
                          decoration: _decoration(
                            '비밀번호 확인',
                            suffix: IconButton(
                              onPressed: () => setState(
                                () => _obscureConfirmation =
                                    !_obscureConfirmation,
                              ),
                              icon: Icon(_obscureConfirmation
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                            ),
                          ),
                          validator: (value) => value == _password.text
                              ? null
                              : '비밀번호가 일치하지 않습니다.',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _referralId,
                          decoration: _decoration(
                            '추천인 ID (선택)',
                            hint: '추천인의 아이디를 입력해 주세요',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                CheckboxListTile(
                  value: _agree,
                  onChanged: (value) => setState(() => _agree = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Wrap(
                    children: [
                      const Text('필수 약관에 동의합니다. '),
                      GestureDetector(
                        onTap: widget.onTerms,
                        child: const Text(
                          '약관 보기',
                          style: TextStyle(
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                BlocBuilder<SignUpBloc, SignUpState>(
                  builder: (context, state) => FilledButton.icon(
                    onPressed: state is SignUpLoading
                        ? null
                        : () {
                            if (!_agree) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('필수 약관에 동의해 주세요.'),
                                ),
                              );
                              return;
                            }
                            if (!_formKey.currentState!.validate()) return;
                            context.read<SignUpBloc>().add(
                                  SignUpSubmitted(
                                    SignUpModel(
                                      email: _email.text,
                                      password: _password.text,
                                      username: _username.text,
                                      nickname: _nickname.text,
                                      referralId: _referralId.text,
                                      profileImage: _profileImage,
                                    ),
                                  ),
                                );
                          },
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: state is SignUpLoading
                        ? const CircularProgressIndicator()
                        : const Text('가입하기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
