import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:langgry/core/localization/app_text.dart';
import 'package:langgry/core/permissions/permission_gate.dart';
import 'package:langgry/core/permissions/permission_policy.dart';
import 'package:uuid/uuid.dart';

class MemoModeAssistantService {
  MemoModeAssistantService({GenerativeModel? model, ImagenModel? imageModel})
      : _model = model ??
            FirebaseAI.googleAI().generativeModel(model: 'gemini-3.6-flash'),
        _imageModel = imageModel ??
            FirebaseAI.googleAI().imagenModel(
              model: 'imagen-3.0-generate-002',
              generationConfig: ImagenGenerationConfig(
                numberOfImages: 1,
                imageFormat: ImagenFormat.jpeg(compressionQuality: 75),
              ),
            );

  final GenerativeModel _model;
  final ImagenModel _imageModel;

  Future<String> generateText({
    required String mode,
    required String request,
  }) async {
    final modeInstruction = switch (mode) {
      'table' =>
        'Return a tab-separated table with a header row and data rows only.',
      'list' =>
        'Return a clean list of items, one per line.',
      'graph' =>
        'Return structured graph data in this format:\n제목: <그래프 제목>\nx축: <x축 범주 이름>\ny축: <y축 수치 이름>\n<범주1>: <수치1>\n<범주2>: <수치2>\n<범주3>: <수치3>',
      'mindMap' =>
        'Return an organic mindmap hierarchy in this format:\n[중심주제]\n- <주요 가지 1>\n  * <세부 노드 1.1>\n  * <세부 노드 1.2>\n- <주요 가지 2>\n  * <세부 노드 2.1>',
      'outline' =>
        'Return a hierarchical outline, one item per line using indentation.',
      'plot' =>
        'Return a clear plot with concise headings and actionable scene beats.',
      'prompt' =>
        'Return a polished, reusable prompt only, preserving the requested language.',
      _ => 'Answer the request directly in clear plain text.',
    };
    final response = await _model.generateContent([
      Content.text('''
You are an assistant embedded in a $mode writing mode.
$modeInstruction
Follow the user's intent, preserve their language, and do not invent facts when
the request concerns real-world information. Return only the content to display.
User request:
$request
'''),
    ]);
    final text = response.text?.trim();
    if (text == null || text.isEmpty) {
      throw StateError('AI가 표시할 내용을 생성하지 못했습니다.');
    }
    return text;
  }

  Future<String> generateAndUploadImage(String prompt) async {
    final response = await _imageModel.generateImages(prompt);
    final image = response.images.firstOrNull;
    if (image == null) {
      throw StateError(
        response.filteredReason ?? 'AI가 이미지를 생성하지 못했습니다.',
      );
    }
    final bytes = Uint8List.fromList(image.bytesBase64Encoded);
    final reference = FirebaseStorage.instance
        .ref('generated_memo_images/${const Uuid().v4()}.jpg');
    final snapshot = await reference.putData(
      bytes,
      SettableMetadata(contentType: image.mimeType),
    );
    return snapshot.ref.getDownloadURL();
  }
}

enum AssistantDisplayMode {
  memo('memo', '메모/텍스트', Icons.notes_rounded),
  table('table', '표', Icons.table_chart_rounded),
  graph('graph', '그래프', Icons.bar_chart_rounded),
  mindMap('mindMap', '마인드맵', Icons.hub_rounded),
  image('image', '사진', Icons.image_rounded),
  plot('plot', '플롯', Icons.auto_graph_rounded),
  outline('outline', '개요', Icons.account_tree_rounded),
  list('list', '리스트', Icons.table_view_rounded),
  prompt('prompt', '프롬프트', Icons.chat_bubble_outline_rounded);

  const AssistantDisplayMode(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;

  static AssistantDisplayMode fromKey(String key) => values.firstWhere(
        (mode) => mode.key == key,
        orElse: () => AssistantDisplayMode.memo,
      );
}

class MemoModeAssistantPanel extends StatefulWidget {
  const MemoModeAssistantPanel({
    required this.mode,
    required this.onTextGenerated,
    this.onImageGenerated,
    this.imagePrompt,
    this.onApplyModeDisplay,
    super.key,
  });

  final String mode;
  final ValueChanged<String> onTextGenerated;
  final ValueChanged<String>? onImageGenerated;
  final String? Function()? imagePrompt;
  final void Function(String content, AssistantDisplayMode mode)?
      onApplyModeDisplay;

  @override
  State<MemoModeAssistantPanel> createState() =>
      _MemoModeAssistantPanelState();
}

class _MemoModeAssistantPanelState extends State<MemoModeAssistantPanel> {
  final _requestController = TextEditingController();
  bool _generatingText = false;
  bool _generatingImage = false;
  String _generatedText = '';
  String _generatedImageUrl = '';
  late AssistantDisplayMode _displayMode;

  @override
  void initState() {
    super.initState();
    _displayMode = AssistantDisplayMode.fromKey(widget.mode);
  }

  @override
  void dispose() {
    _requestController.dispose();
    super.dispose();
  }

  Future<void> _generateText() async {
    final request = _requestController.text.trim();
    if (request.isEmpty) {
      _showError('AI 요청 내용을 입력해 주세요.');
      return;
    }
    if (!await requireFeatureAccess(
        context, PermissionFeatures.aiMultiModeAssistant)) {
      return;
    }
    if (!mounted) return;
    setState(() => _generatingText = true);
    try {
      final response = await MemoModeAssistantService().generateText(
        mode: _displayMode.key,
        request: request,
      );
      if (!mounted) return;
      setState(() {
        _generatedText = response;
      });
      widget.onTextGenerated(response);
    } catch (error) {
      if (mounted) _showError('AI 생성 실패: $error');
    } finally {
      if (mounted) setState(() => _generatingText = false);
    }
  }

  Future<void> _generateImage() async {
    final prompt = widget.imagePrompt?.call()?.trim() ??
        (_generatedText.isNotEmpty
            ? _generatedText
            : _requestController.text.trim());
    if (prompt.isEmpty) {
      _showError('먼저 AI 응답을 생성하거나 이미지 설명을 입력해 주세요.');
      return;
    }
    if (!await requireFeatureAccess(
        context, PermissionFeatures.aiMultiModeAssistant)) {
      return;
    }
    if (!mounted) return;
    setState(() => _generatingImage = true);
    try {
      final url =
          await MemoModeAssistantService().generateAndUploadImage(prompt);
      if (!mounted) return;
      setState(() {
        _generatedImageUrl = url;
      });
      widget.onImageGenerated?.call(url);
    } catch (error) {
      if (mounted) _showError('이미지 생성 실패: $error');
    } finally {
      if (mounted) setState(() => _generatingImage = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: AppText(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome_rounded),
                SizedBox(width: 8),
                AppText('AI Multi-Mode Assistant'),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('ai-request-${widget.mode}'),
              controller: _requestController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: AppText.localize(context, 'AI 요청'),
                hintText: AppText.localize(
                  context,
                  '원하는 내용이나 아이디어를 자유롭게 적어보세요.',
                ),
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _generatingImage ? null : _generateImage,
                  icon: _generatingImage
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.image_rounded),
                  label: AppText(
                    _generatingImage ? '이미지 생성 중...' : '응답으로 이미지 생성',
                  ),
                ),
                FilledButton.icon(
                  onPressed: _generatingText ? null : _generateText,
                  icon: _generatingText
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: AppText(
                    _generatingText ? '생성 중...' : 'AI 답변 생성',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            const AppText(
              '디스플레이 모드 선택:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final mode in AssistantDisplayMode.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        avatar: Icon(mode.icon, size: 16),
                        label: AppText(mode.label),
                        selected: _displayMode == mode,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _displayMode = mode);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(minHeight: 120, maxHeight: 320),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                ),
              ),
              child: SingleChildScrollView(
                child: _buildModeContentDisplay(),
              ),
            ),
            if (widget.onApplyModeDisplay != null && _generatedText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () {
                      widget.onApplyModeDisplay!(
                        _displayMode == AssistantDisplayMode.image
                            ? (_generatedImageUrl.isNotEmpty
                                ? _generatedImageUrl
                                : _generatedText)
                            : _generatedText,
                        _displayMode,
                      );
                    },
                    icon: Icon(_displayMode.icon, size: 18),
                    label: AppText('${_displayMode.label} 모드로 적용'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeContentDisplay() {
    final text = _generatedText.trim();
    if (text.isEmpty && _generatedImageUrl.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: AppText(
            '원하는 내용을 적은 뒤 [AI 답변 생성]을 누르면 설정한 모드로 디스플레이됩니다.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    switch (_displayMode) {
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
          height: 180,
          child: CustomPaint(
            painter: _AssistantGraphPainter(values),
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
        final url = _generatedImageUrl.isNotEmpty ? _generatedImageUrl : text;
        final uri = Uri.tryParse(url);
        if (uri != null && uri.hasScheme) {
          return Image.network(
            url,
            fit: BoxFit.contain,
            height: 200,
            errorBuilder: (_, __, ___) => SelectableText(text),
          );
        }
        return Column(
          children: [
            AppText(text),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _generatingImage ? null : _generateImage,
              icon: const Icon(Icons.image_rounded),
              label: const AppText('AI 이미지 생성하기'),
            ),
          ],
        );

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
              ListTile(
                dense: true,
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: AppText(item),
              ),
          ],
        );
    }
  }
}

class _AssistantGraphPainter extends CustomPainter {
  const _AssistantGraphPainter(this.values);

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
  bool shouldRepaint(covariant _AssistantGraphPainter oldDelegate) =>
      oldDelegate.values != values;
}
