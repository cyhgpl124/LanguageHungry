import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/data/auth_repository.dart';
import '../../home/data/models/home_data.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late Future<HomeData> _data;
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  Uint8List? _newImage;
  String? _imageUrl;
  int? _imageVersion;
  String _email = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _data = context.read<AuthRepository>().loadHomeData();
    _data.then((data) {
      if (!mounted) return;
      _usernameController.text = data.username ?? '';
      _nicknameController.text = data.nickname ?? '';
      _phoneController.text = data.phone ?? '';
      _bioController.text = data.bio ?? '';
      setState(() {
        _imageUrl = data.profileImageUrl;
        _imageVersion = data.profileImageVersion;
        _email = data.email;
      });
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (image == null || !mounted) return;
    setState(() => _newImage = null);
    final bytes = await image.readAsBytes();
    if (mounted) setState(() => _newImage = bytes);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repository = context.read<AuthRepository>();
      await repository.updateProfile(
        username: _usernameController.text,
        nickname: _nicknameController.text,
        phone: _phoneController.text,
        bio: _bioController.text,
      );
      if (_newImage != null) {
        await repository.updateProfileImage(_newImage!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('회원정보를 저장했습니다.')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장하지 못했습니다: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      appBar: AppBar(
        title: const Text('회원정보 수정'),
        backgroundColor: const Color(0xffeff2ff),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('저장하기'),
          ),
        ],
      ),
      body: FutureBuilder<HomeData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('프로필을 불러오지 못했습니다: ${snapshot.error}'),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  constraints.maxWidth > 680 ? 680.0 : constraints.maxWidth;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _AvatarEditor(
                            imageBytes: _newImage,
                            imageUrl: _cacheBustedUrl(_imageUrl, _imageVersion),
                            onTap: _pickImage,
                          ),
                          const SizedBox(height: 16),
                          _EditCard(
                            children: [
                              _field(
                                controller: _nicknameController,
                                label: '닉네임',
                                hint: '닉네임을 입력하세요',
                                required: true,
                              ),
                              _field(
                                controller: _bioController,
                                label: '한마디',
                                hint: '매일 조금씩 성장하는 중',
                                maxLines: 2,
                              ),
                              _field(
                                controller: _usernameController,
                                label: '아이디',
                                hint: '아이디를 입력하세요',
                                required: true,
                              ),
                              _field(
                                controller: _phoneController,
                                label: '전화번호',
                                hint: '선택 입력',
                                keyboardType: TextInputType.phone,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Card(
                            color: const Color(0xfffffdfa),
                            child: ListTile(
                              leading: const Icon(Icons.lock_reset_rounded),
                              title: const Text('비밀번호 변경'),
                              subtitle: const Text(
                                '가입한 이메일로 비밀번호 변경 링크를 보냅니다.',
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: _saving ? null : _sendPasswordReset,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _saving ? null : _save,
                            child: Text(_saving ? '저장 중...' : '저장하기'),
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.center,
                            child: TextButton(
                              onPressed: _saving ? null : _deleteAccount,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                '회원탈퇴',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String? _cacheBustedUrl(String? url, int? version) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'v': '${version ?? 0}',
      },
    ).toString();
  }

  Future<void> _sendPasswordReset() async {
    if (_email.trim().isEmpty) return;
    try {
      await context.read<AuthRepository>().sendPasswordResetEmail(_email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_email 주소로 비밀번호 변경 링크를 보냈습니다.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('비밀번호 변경 메일을 보내지 못했습니다: $error')),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('회원탈퇴'),
        content: const Text(
          '계정을 삭제하면 프로필과 저장된 정보가 삭제됩니다.\n정말 탈퇴하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: const Text('탈퇴하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await context.read<AuthRepository>().deleteAccount();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '회원탈퇴에 실패했습니다. 다시 로그인한 뒤 시도해 주세요: $error',
          ),
        ),
      );
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                ? '$label을(를) 입력하세요.'
                : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: const Color(0xfff4f5f8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.imageBytes,
    required this.imageUrl,
    required this.onTap,
  });

  final Uint8List? imageBytes;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    ImageProvider? provider;
    if (imageBytes != null) {
      provider = MemoryImage(imageBytes!);
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      provider = NetworkImage(imageUrl!);
    }
    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundImage: provider,
          child: provider == null
              ? const Icon(Icons.person_rounded, size: 48)
              : null,
        ),
        TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('프로필 사진 변경'),
        ),
      ],
    );
  }
}

class _EditCard extends StatelessWidget {
  const _EditCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xfffffdfa),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: children),
      ),
    );
  }
}
