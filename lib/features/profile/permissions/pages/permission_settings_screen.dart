import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:langgry/core/localization/app_text.dart';
import 'package:langgry/core/permissions/permission_policy.dart';

class PermissionSettingsScreen extends StatefulWidget {
  const PermissionSettingsScreen({super.key});

  @override
  State<PermissionSettingsScreen> createState() =>
      _PermissionSettingsScreenState();
}

class _PermissionSettingsScreenState extends State<PermissionSettingsScreen> {
  late Future<PermissionMatrix> _matrix;
  PermissionMatrix? _baseMatrix;
  PermissionMatrix? _edited;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _matrix = context.read<PermissionPolicyRepository>().loadMatrix();
  }

  void _update(PermissionFeature feature, PermissionTier tier, bool allowed) {
    setState(() {
      _edited = (_edited ?? _loadedMatrix).withGrant(
        feature.key,
        tier,
        allowed,
      );
    });
  }

  PermissionMatrix get _loadedMatrix =>
      _edited ?? _baseMatrix ?? PermissionMatrix.allEnabled();

  Future<void> _save() async {
    final matrix = _edited;
    if (matrix == null) return;
    setState(() => _saving = true);
    try {
      await context.read<PermissionPolicyRepository>().saveMatrix(matrix);
      if (!mounted) return;
      setState(() {
        _baseMatrix = matrix;
        _edited = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('권한 설정을 저장했습니다.')),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: error.code == 'permission-denied'
              ? const AppText(
                  '권한 설정 저장이 거부되었습니다. 최신 Firestore 규칙을 배포해 주세요.',
                )
              : AppText(
                  '권한 설정 저장 실패: ${error.message ?? error.code}',
                ),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('권한 설정 저장 실패: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppText('권한 설정'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: _saving
                ? const CircularProgressIndicator()
                : const AppText('저장'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<PermissionMatrix>(
        future: _matrix,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: AppText('권한 설정을 불러오지 못했습니다: ${snapshot.error}'),
            );
          }
          _baseMatrix ??= snapshot.data!;
          final matrix = _edited ?? snapshot.data!;
          final usesDefaults =
              context.read<PermissionPolicyRepository>().isUsingDefaultMatrix;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: AppText(
                  '각 권한 단계에서 사용할 수 있는 화면과 기능을 선택합니다. 기본값은 모두 허용입니다.',
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: AppText('최고 권한은 권한 설정 접근이 유지되도록 항상 허용됩니다.'),
              ),
              if (usesDefaults)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: AppText(
                    '현재 기본 권한표를 표시 중입니다. 저장하려면 최신 Firestore 규칙을 배포해 주세요.',
                  ),
                ),
              Expanded(
                child: Scrollbar(
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          const DataColumn(label: AppText('화면 / 기능')),
                          for (final tier in PermissionTier.values)
                            DataColumn(label: AppText(tier.label)),
                        ],
                        rows: [
                          for (final feature in PermissionFeatures.all)
                            DataRow(
                              cells: [
                                DataCell(AppText(feature.label)),
                                for (final tier in PermissionTier.values)
                                  DataCell(
                                    Checkbox(
                                      value: tier == PermissionTier.superAdmin
                                          ? true
                                          : matrix.allows(feature.key, tier),
                                      onChanged:
                                          tier == PermissionTier.superAdmin
                                              ? null
                                              : (value) => _update(
                                                    feature,
                                                    tier,
                                                    value ?? false,
                                                  ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
