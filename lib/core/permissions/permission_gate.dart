import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:langgry/core/localization/app_text.dart';
import 'permission_policy.dart';

class PermissionGate extends StatefulWidget {
  const PermissionGate({
    required this.feature,
    required this.child,
    this.superuserOnly = false,
    super.key,
  }) : features = null;

  PermissionGate.any({
    required List<PermissionFeature> features,
    required this.child,
    this.superuserOnly = false,
    super.key,
  })  : assert(features.isNotEmpty),
        feature = features.first,
        features = features;

  final PermissionFeature feature;
  final List<PermissionFeature>? features;
  final Widget child;
  final bool superuserOnly;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  late Future<(PermissionTier, PermissionMatrix)> _permission;

  @override
  void initState() {
    super.initState();
    _loadPermission();
  }

  void _loadPermission() {
    final repository = context.read<PermissionPolicyRepository>();
    if (repository.isSuperuser) {
      _permission = Future.value((
        PermissionTier.superAdmin,
        PermissionMatrix.allEnabled(),
      ));
      return;
    }
    _permission = Future.wait<Object>([
      repository.currentTier(),
      repository.loadMatrix(),
    ]).then((values) => (
          values[0] as PermissionTier,
          values[1] as PermissionMatrix,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(PermissionTier, PermissionMatrix)>(
      future: _permission,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const AppText('권한 확인')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppText('권한 정보를 불러오지 못했습니다. 다시 시도해 주세요.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        context
                            .read<PermissionPolicyRepository>()
                            .invalidateCache();
                        setState(_loadPermission);
                      },
                      child: const AppText('다시 시도'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final (tier, matrix) = snapshot.data!;
        final features = widget.features ?? [widget.feature];
        final repository = context.read<PermissionPolicyRepository>();
        if ((!widget.superuserOnly || repository.isSuperuser) &&
            features.any((feature) => matrix.allows(feature.key, tier))) {
          return widget.child;
        }
        return PermissionUpgradeScreen(feature: widget.feature, tier: tier);
      },
    );
  }
}

class PermissionUpgradeScreen extends StatelessWidget {
  const PermissionUpgradeScreen({
    required this.feature,
    required this.tier,
    super.key,
  });

  final PermissionFeature feature;
  final PermissionTier tier;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppText('권한 업그레이드'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
          icon: const Icon(Icons.arrow_back),
          tooltip: AppText.localize(context, '뒤로'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 56),
                const SizedBox(height: 16),
                AppText(
                  feature.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const AppText(
                  '기능은 현재 권한에서 사용할 수 없습니다.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const AppText('현재 권한:'),
                AppText(tier.label, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const AppText(
                  '상위 권한으로 업그레이드하거나 무료 체험을 시작해 더 많은 기능을 이용해 보세요.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const AppText('무료 체험'),
                      content: const AppText(
                        '체험판 및 구독 결제 기능은 준비 중입니다.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const AppText('확인'),
                        ),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.star_outline_rounded),
                  label: const AppText('무료 체험 및 업그레이드'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> requireFeatureAccess(
  BuildContext context,
  PermissionFeature feature,
) async {
  final repository = context.read<PermissionPolicyRepository>();
  late PermissionTier tier;
  late PermissionMatrix matrix;
  try {
    tier = await repository.currentTier();
    matrix = await repository.loadMatrix();
  } on FirebaseException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('권한 정보를 불러오지 못했습니다. 다시 시도해 주세요.'),
        ),
      );
    }
    return false;
  } on StateError {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('권한 정보를 불러오지 못했습니다. 다시 시도해 주세요.'),
        ),
      );
    }
    return false;
  }
  if (!context.mounted) return false;
  if (matrix.allows(feature.key, tier)) return true;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => PermissionUpgradeScreen(feature: feature, tier: tier),
    ),
  );
  return false;
}
