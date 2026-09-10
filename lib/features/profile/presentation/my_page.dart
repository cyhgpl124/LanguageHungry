import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/localization/app_strings.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/data/auth_repository.dart';
import '../../home/data/models/home_data.dart';

class MyPage extends StatefulWidget {
  const MyPage({
    required this.onLanguageSettings,
    required this.onEditProfile,
    super.key,
  });

  final VoidCallback onLanguageSettings;
  final Future<void> Function() onEditProfile;

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  late Future<HomeData> _data;

  @override
  void initState() {
    super.initState();
    _data = context.read<AuthRepository>().loadHomeData();
  }

  void _reload() {
    setState(() {
      _data = context.read<AuthRepository>().loadHomeData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      appBar: AppBar(
        title: const Text('마이페이지'),
        backgroundColor: const Color(0xffeff2ff),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: strings.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: () =>
                context.read<AuthBloc>().add(const AuthSignedOut()),
            tooltip: strings.logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: FutureBuilder<HomeData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: FilledButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(strings.retry),
              ),
            );
          }
          return _MyPageContent(
            data: snapshot.data!,
            onLanguageSettings: widget.onLanguageSettings,
            onEditProfile: () async {
              await widget.onEditProfile();
              if (mounted) _reload();
            },
          );
        },
      ),
    );
  }
}

class _MyPageContent extends StatelessWidget {
  const _MyPageContent({
    required this.data,
    required this.onLanguageSettings,
    required this.onEditProfile,
  });

  final HomeData data;
  final VoidCallback onLanguageSettings;
  final Future<void> Function() onEditProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final cards = [
          _StatCard(
            icon: Icons.local_fire_department_rounded,
            color: Colors.orange,
            label: '연속 학습',
            value: '${data.streakDays}일',
          ),
          _StatCard(
            icon: Icons.schedule_rounded,
            color: Colors.indigo,
            label: '총 학습 시간',
            value: '${data.totalStudyMinutes}분',
          ),
          _StatCard(
            icon: Icons.reviews_rounded,
            color: Colors.teal,
            label: '복습 완료',
            value: '${data.reviewCount}개',
          ),
        ];
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Center(
            child: SizedBox(
              width: constraints.hasBoundedWidth
                  ? (constraints.maxWidth > 980 ? 980 : constraints.maxWidth)
                  : 980,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProfileCard(data: data, onEditProfile: onEditProfile),
                  const SizedBox(height: 12),
                  _LanguageCard(
                    data: data,
                    onPressed: onLanguageSettings,
                  ),
                  const SizedBox(height: 12),
                  wide
                      ? Row(
                          children: cards
                              .map(
                                (card) => Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    child: card,
                                  ),
                                ),
                              )
                              .toList(),
                        )
                      : Column(
                          children: cards
                              .map((card) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: card,
                                  ))
                              .toList(),
                        ),
                  const SizedBox(height: 4),
                  _TokenCard(data: data),
                  const SizedBox(height: 10),
                  _SectionCard(
                    title: '랭코인 잔액',
                    icon: Icons.monetization_on_rounded,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '12,500 코인',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 76,
                          child: FilledButton.tonal(
                            onPressed: () => _showComingSoon(context),
                            child: const Text('충전'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _SectionCard(
                    title: '뱃지 업적',
                    icon: Icons.emoji_events_rounded,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _Badge(icon: Icons.star_rounded, label: '첫 학습'),
                        _Badge(
                            icon: Icons.local_fire_department_rounded,
                            label: '7일 연속'),
                        _Badge(icon: Icons.menu_book_rounded, label: '첫 복습'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    title: '구독 모델',
                    icon: Icons.workspace_premium_rounded,
                    trailing: const _StatusChip(label: 'Active'),
                    child: Row(
                      children: [
                        const Expanded(
                          child: _PlanTile(
                            title: 'Beginner',
                            subtitle: '기본 학습 기능',
                            selected: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PlanTile(
                            title: 'Pro',
                            subtitle: 'AI 학습 확장',
                            selected: false,
                            onTap: () => _showComingSoon(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    title: '설정',
                    icon: Icons.settings_rounded,
                    child: Column(
                      children: [
                        _ActionTile(
                          icon: Icons.language_rounded,
                          title: '언어 설정',
                          onTap: onLanguageSettings,
                        ),
                        const Divider(height: 1),
                        _ActionTile(
                          icon: Icons.notifications_none_rounded,
                          title: '알림 설정',
                          onTap: () => _showComingSoon(context),
                        ),
                        const Divider(height: 1),
                        _ActionTile(
                          icon: Icons.help_outline_rounded,
                          title: '도움말 및 문의',
                          onTap: () => _showComingSoon(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: OutlinedButton.icon(
                      onPressed: () => onEditProfile(),
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('회원정보 수정'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('이 기능을 준비하고 있어요.')),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.data,
    required this.onEditProfile,
  });

  final HomeData data;
  final Future<void> Function() onEditProfile;

  @override
  Widget build(BuildContext context) {
    final imageUrl = _cacheBustedUrl(
      data.profileImageUrl,
      data.profileImageVersion,
    );
    return Card(
      color: const Color(0xfffffdfa),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 34,
              child: imageUrl == null
                  ? const Icon(Icons.person_rounded, size: 36)
                  : ClipOval(
                      child: Image.network(
                        imageUrl,
                        width: 68,
                        height: 68,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.person_rounded, size: 36),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          )),
                  const SizedBox(height: 4),
                  Text(
                      data.username?.trim().isNotEmpty == true
                          ? '@${data.username}'
                          : data.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const _StatusChip(label: '비기너'),
                TextButton(
                  onPressed: () => onEditProfile(),
                  child: const Text('회원정보 수정'),
                ),
              ],
            ),
          ],
        ),
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
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({required this.data, required this.onPressed});

  final HomeData data;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xfffffdfa),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.translate_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${data.activeNativeLanguage ?? data.nativeLanguages.firstOrNull ?? '한국어'}'
                  ' → '
                  '${data.activeLearningLanguage ?? data.learningLanguages.firstOrNull ?? '영어'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _TokenCard extends StatelessWidget {
  const _TokenCard({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    const used = 2450;
    const total = 5000;
    return const _SectionCard(
      title: '남은 토큰',
      icon: Icons.bolt_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('이번 달 사용량'),
              Text('$used / $total',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(6)),
            child: LinearProgressIndicator(value: used / total, minHeight: 9),
          ),
          SizedBox(height: 8),
          Text('매월 1일에 토큰이 충전됩니다.', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xfffffdfa),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xfffffdfa),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.14),
              foregroundColor: color,
              child: Icon(icon),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xfffff7e6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.amber.shade700),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: const Color(0xffe0e6f9),
      labelStyle: const TextStyle(
        color: Color(0xff5369b5),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
