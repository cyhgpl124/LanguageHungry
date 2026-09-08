import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/auth_repository.dart';
import '../../presentation/widgets/auth_scaffold.dart';

class AdditionalInfoScreen extends StatefulWidget {
  const AdditionalInfoScreen({
    required this.onCompleted,
    required this.onTerms,
    super.key,
  });

  final VoidCallback onCompleted;
  final VoidCallback onTerms;

  @override
  State<AdditionalInfoScreen> createState() => _AdditionalInfoScreenState();
}

class _AdditionalInfoScreenState extends State<AdditionalInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _nickname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirmation = TextEditingController();
  final _referralId = TextEditingController();
  final _imagePicker = ImagePicker();
  Uint8List? _profileImage;
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _agree = false;

  @override
  void initState() {
    super.initState();
    _email.text = context.read<AuthRepository>().currentUser?.email ?? '';
  }

  @override
  void dispose() {
    _username.dispose();
    _nickname.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirmation.dispose();
    _referralId.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (mounted) setState(() => _profileImage = bytes);
  }

  Future<void> _submit() async {
    if (!_agree) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('필수 약관에 동의해 주세요.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<AuthRepository>().saveAdditionalInfo(
            username: _username.text,
            nickname: _nickname.text,
            phone: '',
            referralId: _referralId.text,
            profileImage: _profileImage,
          );
      widget.onCompleted();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('가입 정보를 저장하지 못했습니다: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String label, {String? hint, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: '랭그리 회원가입',
      subtitle: '랭그리와 함께 언어 학습을 시작하세요.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Semantics(
                button: true,
                label: '프로필 사진 선택',
                child: InkWell(
                  onTap: _saving ? null : _pickProfileImage,
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
                            ? const Icon(
                                Icons.person_rounded,
                                size: 86,
                                color: Colors.white54,
                              )
                            : null,
                      ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 3,
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                '프로필 사진을 눌러 업로드하세요',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _username,
                      decoration: _decoration(
                        '아이디',
                        hint: '3자 이상',
                      ),
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
                      readOnly: true,
                      decoration: _decoration(
                        '이메일 (선택)',
                        suffix: const Icon(Icons.lock_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      decoration: _decoration(
                        '비밀번호',
                        hint: 'Google 로그인은 입력하지 않아도 됩니다',
                        suffix: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordConfirmation,
                      obscureText: _obscureConfirmation,
                      decoration: _decoration(
                        '비밀번호 확인',
                        suffix: IconButton(
                          onPressed: () => setState(
                            () => _obscureConfirmation = !_obscureConfirmation,
                          ),
                          icon: Icon(
                            _obscureConfirmation
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (_password.text.isEmpty && (value ?? '').isEmpty) {
                          return null;
                        }
                        return value == _password.text
                            ? null
                            : '비밀번호가 일치하지 않습니다.';
                      },
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
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _agree,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _agree = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Wrap(
                children: [
                  const Text('필수 약관에 동의합니다. '),
                  GestureDetector(
                    onTap: _saving ? null : widget.onTerms,
                    child: const Text(
                      '약관 보기',
                      style: TextStyle(decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('가입하기'),
            ),
          ],
        ),
      ),
    );
  }
}
