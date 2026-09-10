import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../../core/localization/language_display.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../auth/bloc/auth_event.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/models/home_data.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.onLanguageSettings,
    required this.onLanguageChanged,
    required this.onStartChat,
    super.key,
  });

  final VoidCallback onLanguageSettings;
  final void Function(String nativeLanguage, String learningLanguage)
      onLanguageChanged;
  final VoidCallback onStartChat;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<HomeData> _homeData;

  @override
  void initState() {
    super.initState();
    _homeData = context.read<AuthRepository>().loadHomeData();
  }

  void _refresh() {
    setState(() => _homeData = context.read<AuthRepository>().loadHomeData());
  }

  Future<void> _changeProfileImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (image == null || !mounted) return;

    try {
      await context.read<AuthRepository>().updateProfileImage(
            await image.readAsBytes(),
          );
      if (mounted) {
        setState(() {
          _homeData = context.read<AuthRepository>().loadHomeData();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로필 사진을 변경했습니다.')),
        );
      }
    } catch (error) {
      if (mounted) {
        final message = error is FirebaseException
            ? '프로필 사진 업로드 실패 (${error.code}): '
                '${error.message ?? 'Storage 규칙과 App Check를 확인해 주세요.'}'
            : '프로필 사진 업로드 실패: $error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'LANGGRY',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: strings.refresh,
          ),
          IconButton(
            onPressed: () =>
                context.read<AuthBloc>().add(const AuthSignedOut()),
            icon: const Icon(Icons.logout_rounded),
            tooltip: strings.logout,
          ),
        ],
      ),
      body: FutureBuilder<HomeData>(
        future: _homeData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(onRetry: _refresh);
          }
          return _HomeContent(
            data: snapshot.data!,
            onLanguageSettings: widget.onLanguageSettings,
            onLanguageChanged: widget.onLanguageChanged,
            onStartChat: widget.onStartChat,
            onProfileImageChanged: _changeProfileImage,
          );
        },
      ),
    );
  }
}

class _HomeContent extends StatefulWidget {
  const _HomeContent({
    required this.data,
    required this.onLanguageSettings,
    required this.onLanguageChanged,
    required this.onStartChat,
    required this.onProfileImageChanged,
  });

  final HomeData data;
  final VoidCallback onLanguageSettings;
  final void Function(String nativeLanguage, String learningLanguage)
      onLanguageChanged;
  final VoidCallback onStartChat;
  final Future<void> Function() onProfileImageChanged;

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  late String _activeNative;
  late String _activeLearning;

  @override
  void initState() {
    super.initState();
    _activeNative = widget.data.activeNativeLanguage ??
        (widget.data.nativeLanguages.isEmpty
            ? ''
            : widget.data.nativeLanguages.first);
    _activeLearning = widget.data.activeLearningLanguage ??
        (widget.data.learningLanguages.isEmpty
            ? ''
            : widget.data.learningLanguages.first);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final data = widget.data;
    final native = _activeNative.isEmpty
        ? strings.nativeLanguage
        : LanguageDisplay.fromStorageName(_activeNative).label;
    final learning = _activeLearning.isEmpty
        ? strings.learningLanguage
        : LanguageDisplay.fromStorageName(_activeLearning).label;

    return RefreshIndicator(
      onRefresh: () async {
        await context.read<AuthRepository>().loadHomeData();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _ProfileCard(
            data: data,
            native: native,
            learning: learning,
            activeNative: _activeNative,
            activeLearning: _activeLearning,
            onLanguageSettings: widget.onLanguageSettings,
            onNativeLanguageChanged: (language) {
              setState(() => _activeNative = language);
              widget.onLanguageChanged(_activeNative, _activeLearning);
            },
            onLearningLanguageChanged: (language) {
              setState(() => _activeLearning = language);
              widget.onLanguageChanged(_activeNative, _activeLearning);
            },
            onStartChat: widget.onStartChat,
            onProfileImageChanged: widget.onProfileImageChanged,
          ),
          const SizedBox(height: 16),
          _StatsCard(data: data),
          const SizedBox(height: 24),
          Text(
            strings.reviewRecommendation,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            data.reviewCount == 0
                ? strings.noReviews
                : strings.reviewRecommendation,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          _ReviewCard(reviewCount: data.reviewCount),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.data,
    required this.native,
    required this.learning,
    required this.activeNative,
    required this.activeLearning,
    required this.onLanguageSettings,
    required this.onNativeLanguageChanged,
    required this.onLearningLanguageChanged,
    required this.onStartChat,
    required this.onProfileImageChanged,
  });

  final HomeData data;
  final String native;
  final String learning;
  final String activeNative;
  final String activeLearning;
  final VoidCallback onLanguageSettings;
  final ValueChanged<String> onNativeLanguageChanged;
  final ValueChanged<String> onLearningLanguageChanged;
  final VoidCallback onStartChat;
  final Future<void> Function() onProfileImageChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xfffffdfa),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Center(
              child: Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ...data.nativeLanguages.map(
                    (language) {
                      final display = LanguageDisplay.fromStorageName(language);
                      return ChoiceChip(
                        label: Text(display.label),
                        selected: language == activeNative,
                        onSelected: (_) => onNativeLanguageChanged(language),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onProfileImageChanged,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 156,
                    height: 156,
                    decoration: const BoxDecoration(
                      color: AppTheme.ink,
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: data.profileImageUrl == null
                        ? const Icon(
                            Icons.person_rounded,
                            size: 82,
                            color: Colors.white54,
                          )
                        : Image.network(
                            _cacheBustedImageUrl(data),
                            key: ValueKey(
                              '${data.profileImageUrl}:${data.profileImageVersion}',
                            ),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                              Icons.person_rounded,
                              size: 82,
                              color: Colors.white54,
                            ),
                          ),
                  ),
                  const CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.blue,
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              data.displayName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(
              '@${data.username ?? data.email.split('@').first}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Text('$native  →  $learning'),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ...data.learningLanguages.map(
                  (language) {
                    final display = LanguageDisplay.fromStorageName(language);
                    return ChoiceChip(
                      avatar: Text(display.flag),
                      label: Text(display.nativeName),
                      selected: language == activeLearning,
                      onSelected: (_) => onLearningLanguageChanged(language),
                    );
                  },
                ),
                FilledButton.icon(
                  onPressed: onStartChat,
                  icon: const Icon(Icons.chat_rounded),
                  label: Text(AppStrings.of(context).startChat),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onLanguageSettings,
              icon: const Icon(Icons.translate_rounded),
              label: Text(AppStrings.of(context).changeLanguages),
            ),
          ],
        ),
      ),
    );
  }

  String _cacheBustedImageUrl(HomeData data) {
    final url = data.profileImageUrl!;
    final version = data.profileImageVersion;
    if (version == null) return url;
    return '$url&v=$version';
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  AppStrings.of(context).attendanceAndStudy,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                Chip(
                  label: Text(AppStrings.of(context).streak(data.streakDays)),
                  backgroundColor: AppTheme.blue,
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                AppStrings.of(context).studyMinutes(data.totalStudyMinutes),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('오늘 출석을 기록했어요.')),
              ),
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(AppStrings.of(context).attendanceCheck),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.reviewCount});

  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.mint,
              child: Icon(
                reviewCount == 0
                    ? Icons.check_rounded
                    : Icons.auto_awesome_rounded,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                reviewCount == 0
                    ? AppStrings.of(context).noReviews
                    : AppStrings.of(context).reviewCount(reviewCount),
              ),
            ),
            if (reviewCount > 0)
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.chevron_right_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56),
            const SizedBox(height: 12),
            Text(AppStrings.of(context).homeLoadError),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: Text(AppStrings.of(context).retry),
            ),
          ],
        ),
      ),
    );
  }
}
