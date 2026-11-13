import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:langgry/core/localization/app_text.dart';
import 'package:langgry/features/knowledge/memos/services/memo_mode_assistant.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class TableData {
  const TableData({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;
}

class GraphData {
  const GraphData({
    required this.title,
    required this.xAxisLabel,
    required this.yAxisLabel,
    required this.items,
  });

  final String title;
  final String xAxisLabel;
  final String yAxisLabel;
  final List<({String label, double value})> items;

  List<double> get values => items.map((e) => e.value).toList();
  List<String> get labels => items.map((e) => e.label).toList();
}

class MindMapBranchData {
  const MindMapBranchData({
    required this.title,
    this.subNodes = const [],
  });

  final String title;
  final List<String> subNodes;
}

class MindMapData {
  const MindMapData({
    required this.root,
    required this.branches,
  });

  final String root;
  final List<MindMapBranchData> branches;
}

class OutlineItemData {
  const OutlineItemData({required this.level, required this.text});

  final int level;
  final String text;
}

class OutlineData {
  const OutlineData({required this.items});

  final List<OutlineItemData> items;
}

class PlotBeatData {
  const PlotBeatData({required this.step, required this.title, this.description});

  final int step;
  final String title;
  final String? description;
}

class PlotData {
  const PlotData({required this.beats});

  final List<PlotBeatData> beats;
}

class ListData {
  const ListData({required this.items});

  final List<String> items;
}

class MemoDataParser {
  static TableData parseTable(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('|---') && !l.startsWith('---'))
        .toList();

    if (lines.isEmpty) return const TableData(headers: [], rows: []);

    final delimiterPattern = RegExp(r'\t|\||,');
    final firstRow = lines.first
        .split(delimiterPattern)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final dataRows = <List<String>>[];
    for (final line in lines.skip(1)) {
      final cells = line
          .split(delimiterPattern)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (cells.isNotEmpty) {
        dataRows.add(cells);
      }
    }

    if (dataRows.isEmpty) {
      return TableData(
        headers: ['항목', '값'],
        rows: [
          for (final item in firstRow) [item, ''],
        ],
      );
    }

    return TableData(headers: firstRow, rows: dataRows);
  }

  static GraphData parseGraph(String text) {
    String title = '';
    String xAxisLabel = '범주';
    String yAxisLabel = '수치';
    final items = <({String label, double value})>[];

    final lines = text.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('제목:') || trimmed.startsWith('제목=')) {
        title = trimmed.replaceAll(RegExp(r'^제목[:=]\s*'), '').trim();
        continue;
      }
      if (trimmed.startsWith('x축:') || trimmed.startsWith('X축:')) {
        xAxisLabel = trimmed.replaceAll(RegExp(r'^[xX]축[:=]\s*'), '').trim();
        continue;
      }
      if (trimmed.startsWith('y축:') || trimmed.startsWith('Y축:')) {
        yAxisLabel = trimmed.replaceAll(RegExp(r'^[yY]축[:=]\s*'), '').trim();
        continue;
      }

      if (trimmed.contains(':') || trimmed.contains('=')) {
        final parts = trimmed.split(RegExp(r'[:=]'));
        if (parts.length >= 2) {
          final label = parts[0].trim();
          final val = double.tryParse(parts[1].trim());
          if (val != null) {
            items.add((
              label: label.isEmpty ? '범주 ${items.length + 1}' : label,
              value: val,
            ));
            continue;
          }
        }
      }

      final numericTokens = trimmed
          .split(RegExp(r'[\s,;]+'))
          .map(double.tryParse)
          .whereType<double>()
          .toList();

      for (var i = 0; i < numericTokens.length; i++) {
        items.add((label: '범주 ${items.length + 1}', value: numericTokens[i]));
      }
    }

    if (title.isEmpty && items.isNotEmpty) {
      title = '그래프 요약';
    }

    return GraphData(
      title: title,
      xAxisLabel: xAxisLabel,
      yAxisLabel: yAxisLabel,
      items: items,
    );
  }

  static MindMapData parseMindMap(String text) {
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      return const MindMapData(root: '중심 주제', branches: []);
    }

    String root = lines.first.replaceAll(RegExp(r'^[\[\s\-*•]+|[\]\s]+$'), '').trim();
    if (root.isEmpty) root = '중심 주제';

    final branches = <MindMapBranchData>[];
    MindMapBranchData? currentBranch;

    for (final line in lines.skip(1)) {
      final trimmed = line.trim();
      final isSub = line.startsWith(' ') || line.startsWith('\t') || line.startsWith('*');

      if (isSub && currentBranch != null) {
        final subText = trimmed.replaceAll(RegExp(r'^[*•\-\s]+'), '').trim();
        if (subText.isNotEmpty) {
          currentBranch = MindMapBranchData(
            title: currentBranch.title,
            subNodes: [...currentBranch.subNodes, subText],
          );
        }
      } else {
        if (currentBranch != null) {
          branches.add(currentBranch);
        }
        final branchTitle = trimmed.replaceAll(RegExp(r'^[-*•\d+.\s]+'), '').trim();
        if (branchTitle.isNotEmpty) {
          currentBranch = MindMapBranchData(title: branchTitle, subNodes: []);
        }
      }
    }
    if (currentBranch != null) {
      branches.add(currentBranch);
    }

    return MindMapData(root: root, branches: branches);
  }

  static OutlineData parseOutline(String text) {
    final rawLines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty);
    final items = <OutlineItemData>[];

    for (final line in rawLines) {
      final indent = RegExp(r'^\s*').firstMatch(line)?.group(0)?.length ?? 0;
      final level = (indent / 2).floor() + 1;
      final cleanedText = line.trim().replaceAll(RegExp(r'^[-*•\d+.\s]+'), '');
      if (cleanedText.isNotEmpty) {
        items.add(OutlineItemData(level: level.clamp(1, 4), text: cleanedText));
      }
    }

    return OutlineData(items: items);
  }

  static PlotData parsePlot(String text) {
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    final beats = <PlotBeatData>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].replaceAll(RegExp(r'^\d+[.:]\s*'), '').trim();
      beats.add(PlotBeatData(step: i + 1, title: line));
    }

    return PlotData(beats: beats);
  }

  static ListData parseList(String text) {
    final items = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim().replaceAll(RegExp(r'^[-*•\d+.\s]+'), ''))
        .where((l) => l.isNotEmpty)
        .toList();
    return ListData(items: items);
  }
}

class MemoDisplayEngineWidget extends StatelessWidget {
  const MemoDisplayEngineWidget({
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
            '내용을 입력하거나 AI 답변을 생성하면 설정한 모드로 디스플레이됩니다.',
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
        final tableData = MemoDataParser.parseTable(text);
        if (tableData.headers.isEmpty && tableData.rows.isEmpty) {
          return SelectableText(text);
        }
        final colCount = tableData.headers.isNotEmpty
            ? tableData.headers.length
            : (tableData.rows.isNotEmpty ? tableData.rows.first.length : 1);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
            ),
            columns: [
              for (var c = 0; c < colCount; c++)
                DataColumn(
                  label: AppText(
                    tableData.headers.length > c
                        ? tableData.headers[c]
                        : '열 ${c + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
            rows: [
              for (final row in tableData.rows)
                DataRow(
                  cells: [
                    for (var c = 0; c < colCount; c++)
                      DataCell(
                        AppText(row.length > c ? row[c] : ''),
                      ),
                  ],
                ),
            ],
          ),
        );

      case AssistantDisplayMode.graph:
        final graphData = MemoDataParser.parseGraph(text);
        if (graphData.items.isEmpty) return SelectableText(text);
        return SyncfusionGraphVisualizer(graphData: graphData);

      case AssistantDisplayMode.mindMap:
        final mindMapData = MemoDataParser.parseMindMap(text);
        return ReactiveMindMapVisualizer(data: mindMapData);

      case AssistantDisplayMode.image:
        final uri = Uri.tryParse(text);
        if (uri != null && uri.hasScheme) {
          return Image.network(
            text,
            fit: BoxFit.contain,
            height: 200,
            errorBuilder: (_, __, ___) => SelectableText(text),
          );
        } else if (File(text).existsSync()) {
          return Image.file(
            File(text),
            fit: BoxFit.contain,
            height: 200,
            errorBuilder: (_, __, ___) => SelectableText(text),
          );
        }
        return SelectableText(text);

      case AssistantDisplayMode.plot:
        final plotData = MemoDataParser.parsePlot(text);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final beat in plotData.beats)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor:
                            Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        child: AppText(
                          '${beat.step}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppText(
                          beat.title,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );

      case AssistantDisplayMode.outline:
        final outlineData = MemoDataParser.parseOutline(text);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in outlineData.items)
              Padding(
                padding: EdgeInsets.only(
                  left: (item.level - 1) * 16.0,
                  top: 3,
                  bottom: 3,
                ),
                child: Row(
                  children: [
                    Icon(
                      item.level == 1
                          ? Icons.folder_open_rounded
                          : Icons.account_tree_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AppText(
                        item.text,
                        style: TextStyle(
                          fontWeight: item.level == 1
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

      case AssistantDisplayMode.list:
        final listData = MemoDataParser.parseList(text);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in listData.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
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

class SyncfusionGraphVisualizer extends StatefulWidget {
  const SyncfusionGraphVisualizer({
    required this.graphData,
    this.chartType = 'column',
    super.key,
  });

  final GraphData graphData;
  final String chartType;

  @override
  State<SyncfusionGraphVisualizer> createState() =>
      _SyncfusionGraphVisualizerState();
}

class _SyncfusionGraphVisualizerState extends State<SyncfusionGraphVisualizer> {
  late TooltipBehavior _tooltipBehavior;

  @override
  void initState() {
    super.initState();
    _tooltipBehavior = TooltipBehavior(enable: true);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.graphData;
    if (data.items.isEmpty) return const SizedBox.shrink();

    final palette = const <Color>[
      Color(0xff4969cf),
      Color(0xff42a57a),
      Color(0xfff28c28),
      Color(0xff8b63bd),
      Color(0xffc64c65),
      Color(0xff00a896),
    ];

    if (widget.chartType == 'pie') {
      return SizedBox(
        height: 240,
        child: SfCircularChart(
          title: ChartTitle(
            text: data.title.isNotEmpty ? data.title : '그래프 요약',
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          legend: const Legend(isVisible: true, overflowMode: LegendItemOverflowMode.wrap),
          tooltipBehavior: _tooltipBehavior,
          palette: palette,
          series: <CircularSeries<({String label, double value}), String>>[
            PieSeries<({String label, double value}), String>(
              dataSource: data.items,
              xValueMapper: (item, _) => item.label,
              yValueMapper: (item, _) => item.value,
              dataLabelSettings: const DataLabelSettings(isVisible: true),
              enableTooltip: true,
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 240,
      child: SfCartesianChart(
        title: ChartTitle(
          text: data.title.isNotEmpty ? data.title : '그래프 요약',
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        tooltipBehavior: _tooltipBehavior,
        primaryXAxis: CategoryAxis(
          title: AxisTitle(text: data.xAxisLabel),
          labelRotation: data.items.length > 5 ? -45 : 0,
        ),
        primaryYAxis: NumericAxis(
          title: AxisTitle(text: data.yAxisLabel),
        ),
        palette: palette,
        series: <CartesianSeries<({String label, double value}), String>>[
          ColumnSeries<({String label, double value}), String>(
            dataSource: data.items,
            xValueMapper: (item, _) => item.label,
            yValueMapper: (item, _) => item.value,
            name: data.yAxisLabel,
            dataLabelSettings: const DataLabelSettings(
              isVisible: true,
              textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            enableTooltip: true,
          ),
        ],
      ),
    );
  }
}

class ReactiveMindMapVisualizer extends StatefulWidget {
  const ReactiveMindMapVisualizer({required this.data, super.key});

  final MindMapData data;

  @override
  State<ReactiveMindMapVisualizer> createState() =>
      _ReactiveMindMapVisualizerState();
}

class _ReactiveMindMapVisualizerState extends State<ReactiveMindMapVisualizer> {
  String? _selectedNodeId;
  final Set<int> _expandedBranches = {};

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.data.branches.length; i++) {
      _expandedBranches.add(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 250, maxHeight: 340),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: InteractiveViewer(
          boundaryMargin: const EdgeInsets.all(30),
          minScale: 0.7,
          maxScale: 2.2,
          child: CustomMultiChildLayout(
            delegate: _ReactiveMindMapLayoutDelegate(
              widget.data,
              _expandedBranches,
            ),
            children: [
              LayoutId(
                id: 'edges',
                child: CustomPaint(
                  painter: _ReactiveMindMapEdgePainter(
                    widget.data,
                    _expandedBranches,
                    _selectedNodeId,
                  ),
                ),
              ),
              LayoutId(
                id: 'root',
                child: GestureDetector(
                  onTap: () => setState(() => _selectedNodeId = 'root'),
                  child: Chip(
                    elevation: _selectedNodeId == 'root' ? 6 : 3,
                    backgroundColor: _selectedNodeId == 'root'
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                      color: _selectedNodeId == 'root'
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                    ),
                    avatar: const Icon(Icons.hub_rounded, size: 18),
                    label: AppText(
                      widget.data.root,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              for (var b = 0; b < widget.data.branches.length; b++) ...[
                LayoutId(
                  id: 'branch-$b',
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedNodeId = 'branch-$b';
                        if (_expandedBranches.contains(b)) {
                          _expandedBranches.remove(b);
                        } else {
                          _expandedBranches.add(b);
                        }
                      });
                    },
                    child: Chip(
                      elevation: _selectedNodeId == 'branch-$b' ? 5 : 2,
                      backgroundColor: _selectedNodeId == 'branch-$b'
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context).colorScheme.secondaryContainer,
                      labelStyle: TextStyle(
                        color: _selectedNodeId == 'branch-$b'
                            ? Theme.of(context).colorScheme.onSecondary
                            : null,
                      ),
                      avatar: Icon(
                        _expandedBranches.contains(b)
                            ? Icons.remove_circle_outline_rounded
                            : Icons.add_circle_outline_rounded,
                        size: 16,
                      ),
                      label: AppText(widget.data.branches[b].title),
                    ),
                  ),
                ),
                if (_expandedBranches.contains(b))
                  for (var s = 0; s < widget.data.branches[b].subNodes.length; s++)
                    LayoutId(
                      id: 'sub-$b-$s',
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedNodeId = 'sub-$b-$s'),
                        child: Chip(
                          elevation: _selectedNodeId == 'sub-$b-$s' ? 4 : 1,
                          avatar: const Icon(
                            Icons.subdirectory_arrow_right_rounded,
                            size: 14,
                          ),
                          label: AppText(widget.data.branches[b].subNodes[s]),
                        ),
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

class _ReactiveMindMapLayoutDelegate extends MultiChildLayoutDelegate {
  _ReactiveMindMapLayoutDelegate(this.data, this.expandedBranches);

  final MindMapData data;
  final Set<int> expandedBranches;

  @override
  void performLayout(Size size) {
    if (hasChild('edges')) {
      layoutChild('edges', BoxConstraints.tight(size));
      positionChild('edges', Offset.zero);
    }

    final center = Offset(size.width / 2, size.height / 2);
    Size rootSize = Size.zero;

    if (hasChild('root')) {
      rootSize = layoutChild('root', const BoxConstraints());
      positionChild(
        'root',
        Offset(center.dx - rootSize.width / 2, center.dy - rootSize.height / 2),
      );
    }

    final branchCount = data.branches.length;
    if (branchCount == 0) return;

    final radiusX = math.min(size.width * 0.35, 160.0);
    final radiusY = math.min(size.height * 0.35, 110.0);

    for (var b = 0; b < branchCount; b++) {
      final angle = (b * 2 * math.pi / branchCount) - (math.pi / 2);
      final bx = center.dx + radiusX * math.cos(angle);
      final by = center.dy + radiusY * math.sin(angle);

      final branchId = 'branch-$b';
      if (hasChild(branchId)) {
        final bSize = layoutChild(branchId, const BoxConstraints());
        positionChild(
          branchId,
          Offset(bx - bSize.width / 2, by - bSize.height / 2),
        );

        if (expandedBranches.contains(b)) {
          final subs = data.branches[b].subNodes;
          final subCount = subs.length;
          for (var s = 0; s < subCount; s++) {
            final subAngle = angle + ((s - (subCount - 1) / 2) * 0.45);
            final sx = bx + 70 * math.cos(subAngle);
            final sy = by + 50 * math.sin(subAngle);
            final subId = 'sub-$b-$s';
            if (hasChild(subId)) {
              final sSize = layoutChild(subId, const BoxConstraints());
              positionChild(
                subId,
                Offset(
                  (sx - sSize.width / 2).clamp(0.0, size.width - sSize.width),
                  (sy - sSize.height / 2).clamp(0.0, size.height - sSize.height),
                ),
              );
            }
          }
        }
      }
    }
  }

  @override
  bool shouldRelayout(covariant _ReactiveMindMapLayoutDelegate oldDelegate) =>
      oldDelegate.data != data || oldDelegate.expandedBranches != expandedBranches;
}

class _ReactiveMindMapEdgePainter extends CustomPainter {
  const _ReactiveMindMapEdgePainter(
    this.data,
    this.expandedBranches,
    this.selectedNodeId,
  );

  final MindMapData data;
  final Set<int> expandedBranches;
  final String? selectedNodeId;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final branchCount = data.branches.length;
    if (branchCount == 0) return;

    final radiusX = math.min(size.width * 0.35, 160.0);
    final radiusY = math.min(size.height * 0.35, 110.0);

    final colors = [
      const Color(0xff4969cf),
      const Color(0xff42a57a),
      const Color(0xfff28c28),
      const Color(0xff8b63bd),
      const Color(0xffc64c65),
    ];

    for (var b = 0; b < branchCount; b++) {
      final angle = (b * 2 * math.pi / branchCount) - (math.pi / 2);
      final bx = center.dx + radiusX * math.cos(angle);
      final by = center.dy + radiusY * math.sin(angle);
      final branchPos = Offset(bx, by);

      final isSelected = selectedNodeId == 'branch-$b' || selectedNodeId == 'root';
      final color = colors[b % colors.length];

      final paintBranch = Paint()
        ..color = isSelected ? color : color.withValues(alpha: 0.6)
        ..strokeWidth = isSelected ? 3.5 : 2.0
        ..style = PaintingStyle.stroke;

      final controlPoint = Offset(
        (center.dx + bx) / 2 + 18 * math.sin(angle),
        (center.dy + by) / 2 - 18 * math.cos(angle),
      );

      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..quadraticBezierTo(
          controlPoint.dx,
          controlPoint.dy,
          branchPos.dx,
          branchPos.dy,
        );
      canvas.drawPath(path, paintBranch);

      if (expandedBranches.contains(b)) {
        final subs = data.branches[b].subNodes;
        final subCount = subs.length;

        for (var s = 0; s < subCount; s++) {
          final isSubSelected = selectedNodeId == 'sub-$b-$s';
          final subAngle = angle + ((s - (subCount - 1) / 2) * 0.45);
          final sx = bx + 70 * math.cos(subAngle);
          final sy = by + 50 * math.sin(subAngle);
          final subPos = Offset(
            sx.clamp(12.0, size.width - 12.0),
            sy.clamp(12.0, size.height - 12.0),
          );

          final paintSub = Paint()
            ..color = isSubSelected ? color : color.withValues(alpha: 0.45)
            ..strokeWidth = isSubSelected ? 2.5 : 1.5
            ..style = PaintingStyle.stroke;

          final subControl = Offset((bx + subPos.dx) / 2, (by + subPos.dy) / 2);
          final subPath = Path()
            ..moveTo(branchPos.dx, branchPos.dy)
            ..quadraticBezierTo(
              subControl.dx,
              subControl.dy,
              subPos.dx,
              subPos.dy,
            );
          canvas.drawPath(subPath, paintSub);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ReactiveMindMapEdgePainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.expandedBranches != expandedBranches ||
      oldDelegate.selectedNodeId != selectedNodeId;
}
