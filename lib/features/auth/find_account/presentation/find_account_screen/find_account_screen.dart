import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/auth_repository.dart';
import '../../bloc/find_account_bloc.dart';
import '../../bloc/find_account_event.dart';
import '../../bloc/find_account_state.dart';
import '../../data/find_account_repository.dart';
import '../../data/models/find_account_model.dart';
import '../../../presentation/widgets/auth_scaffold.dart';

class FindAccountScreen extends StatefulWidget {
  const FindAccountScreen({super.key});

  @override
  State<FindAccountScreen> createState() => _FindAccountScreenState();
}

class _FindAccountScreenState extends State<FindAccountScreen> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  int _tab = 0;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => FindAccountBloc(
        FindAccountRepository(context.read<AuthRepository>()),
      ),
      child: BlocListener<FindAccountBloc, FindAccountState>(
        listener: (context, state) {
          final message = switch (state) {
            FindIdSuccess(:final email) =>
              email == null ? '일치하는 계정을 찾지 못했습니다.' : '가입 이메일은 $email 입니다.',
            ResetPasswordSuccess() => '비밀번호 재설정 메일을 확인해 주세요.',
            FindAccountFailure(:final message) => message,
            _ => null,
          };
          if (message != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
        },
        child: AuthScaffold(
          title: '계정 찾기',
          subtitle: '가입 정보로 계정을 안전하게 확인할 수 있어요.',
          child: Column(
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('아이디 찾기')),
                  ButtonSegment(value: 1, label: Text('비밀번호 찾기')),
                ],
                selected: {_tab},
                onSelectionChanged: (value) =>
                    setState(() => _tab = value.first),
              ),
              const SizedBox(height: 26),
              if (_tab == 0) ...[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: '이름'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '휴대폰 번호'),
                ),
                const SizedBox(height: 18),
                BlocBuilder<FindAccountBloc, FindAccountState>(
                  builder: (context, state) => FilledButton(
                    onPressed: state is FindAccountLoading
                        ? null
                        : () => context.read<FindAccountBloc>().add(
                              FindIdSubmitted(
                                FindAccountModel(
                                  name: _name.text,
                                  phone: _phone.text,
                                ),
                              ),
                            ),
                    child: state is FindAccountLoading
                        ? const CircularProgressIndicator()
                        : const Text('아이디 확인하기'),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: '가입 이메일'),
                ),
                const SizedBox(height: 18),
                BlocBuilder<FindAccountBloc, FindAccountState>(
                  builder: (context, state) => FilledButton(
                    onPressed: state is FindAccountLoading
                        ? null
                        : () {
                            if (!_email.text.contains('@')) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('가입 이메일을 입력해 주세요.'),
                                ),
                              );
                              return;
                            }
                            context.read<FindAccountBloc>().add(
                                  ResetPasswordSubmitted(
                                    FindAccountModel(email: _email.text),
                                  ),
                                );
                          },
                    child: state is FindAccountLoading
                        ? const CircularProgressIndicator()
                        : const Text('재설정 메일 보내기'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
