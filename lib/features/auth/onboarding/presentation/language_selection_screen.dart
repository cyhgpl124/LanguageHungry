import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/auth_repository.dart';
import '../../presentation/widgets/auth_scaffold.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({required this.onCompleted, super.key});

  final VoidCallback onCompleted;

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  static const _languages = [
    '한국어',
    '영어',
    '일본어',
    '중국어',
    '스페인어',
    '프랑스어',
    '독일어',
  ];

  final _nativeLanguages = <String>{};
  final _learningLanguages = <String>{};
  bool _saving = false;

  Future<void> _submit() async {
    if (_nativeLanguages.isEmpty || _learningLanguages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('두 언어를 모두 선택해 주세요.')),
      );
      return;
    }
    if (_nativeLanguages.intersection(_learningLanguages).isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서로 다른 언어를 선택해 주세요.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await context.read<AuthRepository>().saveLanguagePreferences(
            nativeLanguages: _nativeLanguages.toList(),
            learningLanguages: _learningLanguages.toList(),
          );
      widget.onCompleted();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: '언어를 선택해 주세요',
      subtitle: '나에게 맞는 학습 목표를 설정해 보세요.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('모국어 (여러 개 선택 가능)'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _languages.map((language) {
              return FilterChip(
                label: Text(language),
                selected: _nativeLanguages.contains(language),
                onSelected: (selected) => setState(() {
                  selected
                      ? _nativeLanguages.add(language)
                      : _nativeLanguages.remove(language);
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text('배우고자 하는 언어 (여러 개 선택 가능)'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _languages.map((language) {
              return FilterChip(
                label: Text(language),
                selected: _learningLanguages.contains(language),
                onSelected: (selected) => setState(() {
                  selected
                      ? _learningLanguages.add(language)
                      : _learningLanguages.remove(language);
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const CircularProgressIndicator()
                : const Text('시작하기'),
          ),
        ],
      ),
    );
  }
}
