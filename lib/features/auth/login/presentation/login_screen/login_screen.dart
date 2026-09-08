import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/auth_repository.dart';
import '../../../data/models/auth_user.dart';
import '../../bloc/login_bloc.dart';
import '../../bloc/login_event.dart';
import '../../bloc/login_state.dart';
import '../../data/login_repository.dart';
import '../../data/models/login_model.dart';
import '../../../presentation/widgets/auth_scaffold.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.onSignUp,
    required this.onFindAccount,
    required this.onLoginSuccess,
    super.key,
  });

  final VoidCallback onSignUp;
  final VoidCallback onFindAccount;
  final ValueChanged<AuthUser> onLoginSuccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LoginBloc(
        LoginRepository(context.read<AuthRepository>()),
      ),
      child: BlocListener<LoginBloc, LoginState>(
        listener: (context, state) {
          if (state is LoginSuccess) {
            widget.onLoginSuccess(state.user);
          } else if (state is LoginFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: AuthScaffold(
          title: '다시 만나요',
          subtitle: '나만의 언어 습관을 이어가세요.',
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: '이메일',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (value) => value != null && value.contains('@')
                      ? null
                      : '이메일을 입력해 주세요.',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                  validator: (value) => value != null && value.length >= 6
                      ? null
                      : '비밀번호를 입력해 주세요.',
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: widget.onFindAccount,
                    child: const Text('아이디·비밀번호 찾기'),
                  ),
                ),
                const SizedBox(height: 8),
                BlocBuilder<LoginBloc, LoginState>(
                  builder: (context, state) => FilledButton(
                    onPressed: state is LoginLoading
                        ? null
                        : () {
                            if (_formKey.currentState!.validate()) {
                              context.read<LoginBloc>().add(
                                    LoginSubmitted(
                                      LoginModel(
                                        email: _email.text,
                                        password: _password.text,
                                      ),
                                    ),
                                  );
                            }
                          },
                    child: state is LoginLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('로그인'),
                  ),
                ),
                const SizedBox(height: 14),
                Builder(
                  builder: (context) => OutlinedButton.icon(
                    onPressed: () => context
                        .read<LoginBloc>()
                        .add(const GoogleLoginSubmitted()),
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                    label: const Text('Google로 계속하기'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('처음 오셨나요?'),
                    TextButton(
                      onPressed: widget.onSignUp,
                      child: const Text('회원가입'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
