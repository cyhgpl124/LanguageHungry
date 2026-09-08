import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/auth_repository.dart';
import '../../presentation/widgets/auth_scaffold.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({required this.onVerified, super.key});

  final VoidCallback onVerified;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _loading = false;
  bool _resending = false;

  Future<void> _checkVerification() async {
    setState(() => _loading = true);
    try {
      final repository = context.read<AuthRepository>();
      await repository.reloadCurrentUser();
      final user = repository.currentUser;
      if (user == null) {
        throw StateError('로그인된 사용자가 없습니다.');
      }
      if (user.needsEmailVerification) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이메일 인증을 완료한 뒤 다시 확인해 주세요.')),
        );
      } else {
        if (!mounted) return;
        widget.onVerified();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await context.read<AuthRepository>().resendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('인증 메일을 다시 보냈습니다.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = context.read<AuthRepository>().currentUser?.email ?? '';
    return AuthScaffold(
      title: '이메일을 인증해 주세요',
      subtitle: '$email 주소로 인증 메일을 보냈습니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            size: 80,
          ),
          const SizedBox(height: 20),
          const Text(
            '메일함에서 인증 링크를 클릭한 뒤 아래 버튼을 눌러 주세요.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _checkVerification,
            child: _loading
                ? const CircularProgressIndicator()
                : const Text('인증 완료 확인'),
          ),
          TextButton(
            onPressed: _resending ? null : _resend,
            child:
                _resending ? const Text('전송 중...') : const Text('인증 메일 다시 보내기'),
          ),
        ],
      ),
    );
  }
}
