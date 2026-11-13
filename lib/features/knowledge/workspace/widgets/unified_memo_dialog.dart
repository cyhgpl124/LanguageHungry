import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:langgry/core/localization/app_text.dart';
import 'package:langgry/core/permissions/permission_gate.dart';
import 'package:langgry/core/permissions/permission_policy.dart';
import 'package:langgry/features/knowledge/memos/services/memo_mode_assistant.dart';
import 'package:langgry/features/knowledge/models/knowledge_node.dart';

class UnifiedMemoResult {
  const UnifiedMemoResult({
    required this.mode,
    required this.title,
    required this.content,
    required this.tags,
    required this.autoGenerateTitle,
    required this.autoGenerateTags,
    this.parentId,
  });

  final AssistantDisplayMode mode;
  final String title;
  final String content;
  final List<String> tags;
  final bool autoGenerateTitle;
  final bool autoGenerateTags;
  final String? parentId;
}

class UnifiedMemoDialog extends StatefulWidget {
  const UnifiedMemoDialog({
    this.initialMode = AssistantDisplayMode.memo,
    this.initialTitle = '',
    this.initialContent = '',
    this.initialTags = const [],
    this.parentComponents = const [],
    this.initialParentId,
    this.dialogTitle = '새 메모 작성',
    super.key,
  });

  final AssistantDisplayMode initialMode;
  final String initialTitle;
  final String initialContent;
  final List<String> initialTags;
  final List<KnowledgeNode> parentComponents;
  final String? initialParentId;
  final String dialogTitle;

  @override
  State<UnifiedMemoDialog> createState() => _UnifiedMemoDialogState();
}

class _UnifiedMemoDialogState extends State<UnifiedMemoDialog> {
  late AssistantDisplayMode _mode;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagsController;
  final TextEditingController _aiRequestController = TextEditingController();

  String? _parentId;
  bool _autoGenerateTitle = true;
  bool _autoGenerateTags = true;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _parentId = widget.initialParentId;
    _titleController = TextEditingController(text: widget.initialTitle);
    _contentController = TextEditingController(text: widget.initialContent);
    _tagsController = TextEditingController(
      text: widget.initialTags.map((t) => '#$t').join(' '),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    _aiRequestController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.single.path;
        if (path != null) {
          setState(() {
            _contentController.text = path;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: AppText('이미지 선택 실패: $e')),
        );
      }
    }
  }

  Future<void> _generateAiContent() async {
    final request = _aiRequestController.text.trim();
    if (request.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('AI 요청 내용을 입력해 주세요.')),
      );
      return;
    }
    if (!await requireFeatureAccess(
        context, PermissionFeatures.aiMultiModeAssistant)) {
      return;
    }
    if (!mounted) return;
    setState(() => _generating = true);
    try {
      final assistant = MemoModeAssistantService();
      String response;
      if (_mode == AssistantDisplayMode.image) {
        response = await assistant.generateAndUploadImage(request);
      } else {
        response = await assistant.generateText(
          mode: _mode.key,
          request: request,
        );
      }

      if (!mounted) return;
      setState(() {
        _contentController.text = response;

        if (_autoGenerateTitle && _titleController.text.trim().isEmpty) {
          final titleCandidate =
              String.fromCharCodes(response.runes.take(10)).trim();
          _titleController.text =
              titleCandidate.isEmpty ? 'AI 메모' : titleCandidate;
        }

        if (_autoGenerateTags) {
          final extracted = RegExp(r'#([^\s#]+)')
              .allMatches(response)
              .map((m) => m.group(1)!)
              .toList();
          if (extracted.isNotEmpty) {
            _tagsController.text = extracted.map((t) => '#$t').join(' ');
          } else if (_tagsController.text.trim().isEmpty) {
            _tagsController.text = '#AI생성 #${_mode.label}';
          }
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: AppText('AI 답변 생성 실패: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _save() {
    var title = _titleController.text.trim();
    var content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('제목이나 내용을 입력해 주세요.')),
      );
      return;
    }

    if (title.isEmpty) {
      if (_autoGenerateTitle) {
        title = String.fromCharCodes(content.runes.take(10)).trim();
        if (title.isEmpty) title = '${_mode.label} 메모';
      } else {
        title = '${_mode.label} 메모';
      }
    }

    final rawTags = _tagsController.text;
    final parsedTags = RegExp(r'#([^\s#]+)|([^\s,#]+)')
        .allMatches(rawTags)
        .map((m) => (m.group(1) ?? m.group(2))!.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    Navigator.of(context).pop(
      UnifiedMemoResult(
        mode: _mode,
        title: title,
        content: content,
        tags: parsedTags,
        autoGenerateTitle: _autoGenerateTitle,
        autoGenerateTags: _autoGenerateTags,
        parentId: _parentId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: AppText(widget.dialogTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 메모 모드
              DropdownButtonFormField<AssistantDisplayMode>(
                value: _mode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: AppText.localize(context, '메모 모드'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final mode in AssistantDisplayMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Row(
                        children: [
                          Icon(mode.icon, size: 18),
                          const SizedBox(width: 8),
                          AppText(mode.label),
                        ],
                      ),
                    ),
                ],
                onChanged: (mode) {
                  if (mode != null) {
                    setState(() => _mode = mode);
                  }
                },
              ),
              const SizedBox(height: 12),

              // 1-1. 상위 개요 선택 (상위 구성요소가 존재하는 경우 노출)
              if (widget.parentComponents.isNotEmpty) ...[
                DropdownButtonFormField<String?>(
                  value: _parentId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: AppText.localize(context, '상위 개요 선택'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: AppText('최상위 (상위 개요 없음)'),
                    ),
                    for (final parent in widget.parentComponents)
                      DropdownMenuItem<String?>(
                        value: parent.id,
                        child: Text(
                          parent.title.isEmpty ? '개요 항목' : parent.title,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => _parentId = id),
                ),
                const SizedBox(height: 12),
              ],

              // 2. 제목
              TextField(
                key: const ValueKey('unified-memo-title'),
                controller: _titleController,
                maxLength: 20,
                decoration: InputDecoration(
                  labelText: AppText.localize(context, '제목'),
                  hintText: AppText.localize(context, '제목을 입력하세요'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),

              // 3. 내용 (사진 모드인 경우 이미지 가져오기 버튼 포함)
              TextField(
                key: const ValueKey('unified-memo-content'),
                controller: _contentController,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: AppText.localize(
                    context,
                    _mode == AssistantDisplayMode.image ? '이미지 URL 또는 경로' : '내용',
                  ),
                  hintText: AppText.localize(context, '내용을 입력해 주세요.'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_mode == AssistantDisplayMode.image) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _pickImageFile,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const AppText('이미지 가져오기'),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // 4. 태그 및 AI 자동 생성 설정
              TextField(
                key: const ValueKey('unified-memo-tags'),
                controller: _tagsController,
                decoration: InputDecoration(
                  labelText: AppText.localize(context, '태그'),
                  hintText: AppText.localize(context, '#태그1 #태그2'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(
                          () => _autoGenerateTitle = !_autoGenerateTitle),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Switch(
                              value: _autoGenerateTitle,
                              onChanged: (val) =>
                                  setState(() => _autoGenerateTitle = val),
                            ),
                            const SizedBox(width: 4),
                            const Flexible(
                              child: AppText(
                                '제목 AI 자동 생성',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(
                          () => _autoGenerateTags = !_autoGenerateTags),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Switch(
                              value: _autoGenerateTags,
                              onChanged: (val) =>
                                  setState(() => _autoGenerateTags = val),
                            ),
                            const SizedBox(width: 4),
                            const Flexible(
                              child: AppText(
                                '태그 AI 자동 생성',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 5. AI 요청 및 디스플레이
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('unified-memo-ai-request'),
                    controller: _aiRequestController,
                    decoration: InputDecoration(
                      labelText: AppText.localize(context, 'AI 요청'),
                      hintText: AppText.localize(
                        context,
                        '원하는 내용이나 아이디어를 적어보세요.',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _generating ? null : _generateAiContent,
                      icon: _generating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.auto_awesome_rounded),
                      label: const AppText('AI 답변 생성'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const AppText(
                '디스플레이 미리보기:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Container(
                constraints:
                    const BoxConstraints(minHeight: 100, maxHeight: 180),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.4),
                  ),
                ),
                child: SingleChildScrollView(
                  child: MemoModeContentDisplay(
                    content: _contentController.text,
                    mode: _mode,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const AppText('취소'),
        ),
        FilledButton(
          onPressed: _save,
          child: const AppText('저장'),
        ),
      ],
    );
  }
}

class MemoModeContentDisplay extends StatelessWidget {
  const MemoModeContentDisplay({
    required this.content,
    required this.mode,
    super.key,
  });

  final String content;
  final AssistantDisplayMode mode;

  @override
  Widget build(BuildContext context) {
    final text = content.trim();
    if (text.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: AppText(
            '내용을 입력하거나 AI 답변을 생성하면 해당 모드로 디스플레이됩니다.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    switch (mode) {
      case AssistantDisplayMode.memo:
      case AssistantDisplayMode.prompt:
        return SelectableText(text);

      case AssistantDisplayMode.table:
        final rows = text
            .split(RegExp(r'\r?\n'))
            .where((line) => line.trim().isNotEmpty)
            .map((line) => line.split(RegExp(r'\t|,')))
            .toList();
        if (rows.isEmpty) return SelectableText(text);
        final columns =
            rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              for (var c = 0; c < columns; c++)
                DataColumn(
                  label: AppText(
                    rows.first.length > c ? rows.first[c].trim() : '',
                  ),
                ),
            ],
            rows: [
              for (final row in rows.skip(1))
                DataRow(
                  cells: [
                    for (var c = 0; c < columns; c++)
                      DataCell(
                        AppText(row.length > c ? row[c].trim() : ''),
                      ),
                  ],
                ),
            ],
          ),
        );

      case AssistantDisplayMode.graph:
        final values = text
            .split(RegExp(r'[\s,;]+'))
            .map(double.tryParse)
            .whereType<double>()
            .toList();
        if (values.isEmpty) return SelectableText(text);
        return SizedBox(
          height: 150,
          child: CustomPaint(
            painter: _UnifiedGraphPainter(values),
            child: const SizedBox.expand(),
          ),
        );

      case AssistantDisplayMode.mindMap:
        final labels = text
            .split(RegExp(r'\r?\n|,'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (labels.isEmpty) return SelectableText(text);
        return Column(
          children: [
            Chip(
              avatar: const Icon(Icons.hub_outlined, size: 16),
              label: AppText(labels.first),
            ),
            if (labels.length > 1) const Icon(Icons.south_rounded, size: 18),
            if (labels.length > 1)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in labels.skip(1))
                    Chip(
                      avatar:
                          const Icon(Icons.subdirectory_arrow_right, size: 16),
                      label: AppText(item),
                    ),
                ],
              ),
          ],
        );

      case AssistantDisplayMode.image:
        final uri = Uri.tryParse(text);
        if (uri != null && uri.hasScheme) {
          return Image.network(
            text,
            fit: BoxFit.contain,
            height: 160,
            errorBuilder: (_, __, ___) => SelectableText(text),
          );
        } else if (File(text).existsSync()) {
          return Image.file(
            File(text),
            fit: BoxFit.contain,
            height: 160,
            errorBuilder: (_, __, ___) => SelectableText(text),
          );
        }
        return SelectableText(text);

      case AssistantDisplayMode.plot:
        final beats = text
            .split(RegExp(r'\r?\n'))
            .where((line) => line.trim().isNotEmpty)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < beats.length; index++)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        child: AppText(
                          '${index + 1}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: AppText(beats[index])),
                    ],
                  ),
                ),
              ),
          ],
        );

      case AssistantDisplayMode.outline:
        final lines = text
            .split(RegExp(r'\r?\n'))
            .where((line) => line.trim().isNotEmpty)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(Icons.account_tree_outlined, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: AppText(line)),
                  ],
                ),
              ),
          ],
        );

      case AssistantDisplayMode.list:
        final items = text
            .split(RegExp(r'\r?\n'))
            .where((line) => line.trim().isNotEmpty)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: AppText(item)),
                  ],
                ),
              ),
          ],
        );
    }
  }
}

class _UnifiedGraphPainter extends CustomPainter {
  const _UnifiedGraphPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
    final paint = Paint()
      ..color = const Color(0xff4969cf)
      ..style = PaintingStyle.fill;

    final barWidth = size.width / (values.length * 1.6);
    for (var index = 0; index < values.length; index++) {
      final left = (index + 0.5) * size.width / values.length - barWidth / 2;
      final barHeight = values[index].abs() /
          (maxValue == 0 ? 1 : maxValue) *
          (size.height * 0.85);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - barHeight, barWidth, barHeight),
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UnifiedGraphPainter oldDelegate) =>
      oldDelegate.values != values;
}
