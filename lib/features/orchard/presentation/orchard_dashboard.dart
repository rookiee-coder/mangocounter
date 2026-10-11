import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../history/domain/scan_record.dart';

class OrchardTreeRef {
  final int lane;
  final int number;
  final int lanePosition;
  final int treePosition;

  const OrchardTreeRef({
    required this.lane,
    required this.number,
    required this.lanePosition,
    required this.treePosition,
  });

  String get id => 'lane_${lane}_tree_$number';
  String get label => 'Lane $lane / Tree $number';

  static List<OrchardTreeRef> fromLayout(
    List<int> treesPerLane, {
    Set<String> removedTreeIds = const {},
    Set<int> removedLaneIds = const {},
  }) {
    final activeLanes = [
      for (var lane = 1; lane <= treesPerLane.length; lane++)
        if (!removedLaneIds.contains(lane)) lane,
    ];
    return [
      for (var lanePosition = 1;
          lanePosition <= activeLanes.length;
          lanePosition++)
        for (var number = 1, treePosition = 0;
            number <= treesPerLane[activeLanes[lanePosition - 1] - 1];
            number++)
          if (!removedTreeIds
              .contains('lane_${activeLanes[lanePosition - 1]}_tree_$number'))
            OrchardTreeRef(
              lane: activeLanes[lanePosition - 1],
              number: number,
              lanePosition: lanePosition,
              treePosition: ++treePosition,
            ),
    ];
  }
}

/// Interactive, isometric orchard plan. Latest scans are associated with the
/// tree they were taken from; tapping a tree opens its details/actions.
class OrchardDashboard extends StatefulWidget {
  final List<ScanRecord> scans;
  final String? selectedTreeId;
  final ValueChanged<OrchardTreeRef> onTreeSelected;

  const OrchardDashboard({
    super.key,
    required this.scans,
    required this.selectedTreeId,
    required this.onTreeSelected,
  });

  @override
  State<OrchardDashboard> createState() => _OrchardDashboardState();
}

class _OrchardDashboardState extends State<OrchardDashboard> {
  static const _layoutKey = 'orchard_tree_layout_v1';
  static const _removedTreesKey = 'orchard_removed_trees_v1';
  static const _removedLanesKey = 'orchard_removed_lanes_v1';
  final TransformationController _transform = TransformationController();
  List<int> _treesPerLane = [3, 3, 3];
  Set<String> _removedTreeIds = {};
  Set<int> _removedLaneIds = {};
  Size _viewportSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_layoutKey);
    final removedTrees = prefs.getStringList(_removedTreesKey) ?? const [];
    final removedLanes = prefs
        .getStringList(_removedLanesKey)
        ?.map(int.tryParse)
        .whereType<int>()
        .toSet();
    if (!mounted) return;
    final layout = stored?.map(int.tryParse).whereType<int>().toList();
    setState(() {
      if (layout != null &&
          layout.isNotEmpty &&
          layout.every((count) => count >= 0)) {
        _treesPerLane = layout;
      }
      _removedTreeIds = removedTrees.toSet();
      _removedLaneIds = removedLanes ?? {};
    });
  }

  Future<void> _saveLayout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _layoutKey,
      _treesPerLane.map((count) => count.toString()).toList(),
    );
    await prefs.setStringList(_removedTreesKey, _removedTreeIds.toList());
    await prefs.setStringList(
        _removedLanesKey, _removedLaneIds.map((lane) => '$lane').toList());
  }

  List<int> get _activeLaneIds => [
        for (var lane = 1; lane <= _treesPerLane.length; lane++)
          if (!_removedLaneIds.contains(lane)) lane,
      ];

  Future<void> _addLine() async {
    setState(() => _treesPerLane = [..._treesPerLane, 3]);
    await _saveLayout();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added Lane ${_treesPerLane.length} with 3 trees'),
        ),
      );
    }
  }

  Future<void> _addTree() async {
    final activeLanes = _activeLaneIds;
    if (activeLanes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a line before adding trees')),
      );
      return;
    }
    final lane = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Text('Choose a line for the new tree',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            for (final laneId in activeLanes)
              ListTile(
                leading: const Icon(Icons.linear_scale_rounded,
                    color: AppColors.primaryGreen),
                title: Text('Lane $laneId'),
                subtitle: Text(
                    '${_treesPerLane[laneId - 1] - _removedTreeIds.where((id) => id.startsWith('lane_${laneId}_tree_')).length} trees'),
                onTap: () => Navigator.pop(sheetContext, laneId),
              ),
          ],
        ),
      ),
    );
    if (lane == null || !mounted) return;
    setState(() => _treesPerLane[lane - 1]++);
    await _saveLayout();
  }

  Future<void> _deleteTree() async {
    final trees = OrchardTreeRef.fromLayout(
      _treesPerLane,
      removedTreeIds: _removedTreeIds,
      removedLaneIds: _removedLaneIds,
    );
    if (trees.isEmpty) return;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Text('Choose a tree to remove',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            for (final tree in trees)
              ListTile(
                leading: const Icon(Icons.park_outlined,
                    color: AppColors.primaryGreen),
                title: Text(tree.label),
                onTap: () => Navigator.pop(sheetContext, tree.id),
              ),
          ],
        ),
      ),
    );
    if (id == null || !mounted) return;
    final confirmed = await _confirmRemoval(
      title: 'Remove this tree?',
      message:
          'The tree will disappear from the orchard. Its existing scan records will remain in history.',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removedTreeIds = {..._removedTreeIds, id});
    await _saveLayout();
  }

  Future<void> _deleteLane() async {
    final lanes = _activeLaneIds;
    if (lanes.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('The orchard must keep at least one line')),
      );
      return;
    }
    final lane = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Text('Choose a line to remove',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            for (final laneId in lanes)
              ListTile(
                leading: const Icon(Icons.linear_scale_rounded,
                    color: AppColors.primaryGreen),
                title: Text('Lane $laneId'),
                subtitle: const Text('Remove all trees on this line'),
                onTap: () => Navigator.pop(sheetContext, laneId),
              ),
          ],
        ),
      ),
    );
    if (lane == null || !mounted) return;
    final confirmed = await _confirmRemoval(
      title: 'Remove Lane $lane?',
      message:
          'All trees on this line will disappear from the orchard. Their scan records will remain in history.',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removedLaneIds = {..._removedLaneIds, lane});
    await _saveLayout();
  }

  Future<bool?> _confirmRemoval({
    required String title,
    required String message,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );

  Map<String, ScanRecord> get _latestScans {
    final latest = <String, ScanRecord>{};
    for (final scan in widget.scans) {
      final id = scan.treeId;
      if (id == null) continue;
      final old = latest[id];
      if (old == null || scan.createdAt > old.createdAt) latest[id] = scan;
    }
    return latest;
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoomFromWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _scaleView(event.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12,
        focus: event.localPosition);
  }

  void _scaleView(double factor, {Offset? focus}) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.75, 3.2).toDouble();
    final focalPoint =
        focus ?? Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final adjusted = _transform.value.clone()
      ..translate(focalPoint.dx, focalPoint.dy)
      ..scale(next / current)
      ..translate(-focalPoint.dx, -focalPoint.dy);
    _transform.value = adjusted;
  }

  void _resetView() {
    _transform.value = _transform.value.clone()..setIdentity();
  }

  @override
  Widget build(BuildContext context) {
    final latest = _latestScans;
    final trees = OrchardTreeRef.fromLayout(
      _treesPerLane,
      removedTreeIds: _removedTreeIds,
      removedLaneIds: _removedLaneIds,
    );
    final activeLanes = _activeLaneIds;
    final scannedTrees =
        trees.where((tree) => latest.containsKey(tree.id)).length;
    final maxTreesPerLane = trees.isEmpty
        ? 1
        : trees.fold<int>(
            0,
            (maxCount, tree) =>
                maxCount > tree.treePosition ? maxCount : tree.treePosition);
    final mangoCount = trees.fold<int>(
      0,
      (total, tree) => total + (latest[tree.id]?.currentTotal ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: AppShapes.leafCut,
            border: Border.all(color: AppColors.outlineTint),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'ORCHARD CONTROLS',
                  style: TextStyle(
                    color: AppColors.mutedGraphite,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton.icon(
                    onPressed: _addTree,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add tree'),
                    style: FilledButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: AppColors.primaryGreen,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add_road_rounded, size: 18),
                    label: const Text('Add line (3 trees)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryGreen,
                      backgroundColor: AppColors.surfaceContainer,
                      side: const BorderSide(color: AppColors.outlineTint),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Remove trees or lines',
                    onSelected: (action) {
                      if (action == 'tree') _deleteTree();
                      if (action == 'lane') _deleteLane();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                          value: 'tree', child: Text('Delete a tree')),
                      PopupMenuItem(
                          value: 'lane', child: Text('Delete a line')),
                    ],
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4F2),
                        border: Border.all(
                            color: AppColors.errorCrimson.withOpacity(0.35)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              size: 18, color: AppColors.errorCrimson),
                          SizedBox(width: 6),
                          Text(
                            'Remove',
                            style: TextStyle(
                              color: AppColors.errorCrimson,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: const Color(0xFF1D3529),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF163F32).withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.park_rounded, color: Color(0xFFA6D178)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'MY MANGO ORCHARD',
                      style: TextStyle(
                        color: Color(0xFFD9E9D0),
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  Text(
                    '$scannedTrees / ${trees.length} scanned',
                    style: const TextStyle(
                      color: Color(0xFFC1D9C0),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                'Tap a tree for details · pinch or scroll to zoom · drag to pan',
                style: TextStyle(color: Color(0xFFB7CBBB), fontSize: 11),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = (width * 0.82).clamp(280.0, 460.0).toDouble();
                  _viewportSize = Size(width, height);
                  final extraLanes = math.max(0, activeLanes.length - 3);
                  final extraTrees = math.max(0, maxTreesPerLane - 3);
                  final designWidth = 400.0 + extraTrees * 86 + extraLanes * 31;
                  final designHeight =
                      280.0 + extraTrees * 14 + extraLanes * 57;
                  final canvasWidth = width * designWidth / 400;
                  final canvasHeight = height * designHeight / 280;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Listener(
                      onPointerSignal: _zoomFromWheel,
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: InteractiveViewer(
                                transformationController: _transform,
                                minScale: 0.75,
                                maxScale: 3.2,
                                boundaryMargin: const EdgeInsets.all(125),
                                clipBehavior: Clip.none,
                                child: SizedBox(
                                  width: canvasWidth,
                                  height: canvasHeight,
                                  child: LayoutBuilder(
                                    builder: (context, canvas) {
                                      final size = Size(
                                          canvas.maxWidth, canvas.maxHeight);
                                      return Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          CustomPaint(
                                            painter: _OrchardPainter(
                                              laneIds: activeLanes,
                                              maxTreesPerLane: maxTreesPerLane,
                                            ),
                                            size: size,
                                          ),
                                          for (final tree in trees)
                                            _positionedTree(
                                              tree,
                                              size,
                                              latest[tree.id],
                                              laneCount: activeLanes.length,
                                              maxTreesPerLane: maxTreesPerLane,
                                              viewportWidth: width,
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Material(
                                color: const Color(0xCC173A2A),
                                borderRadius: BorderRadius.circular(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Zoom in',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _scaleView(1.25),
                                      icon: const Icon(Icons.add_rounded,
                                          color: Colors.white),
                                    ),
                                    IconButton(
                                      tooltip: 'Zoom out',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _scaleView(0.8),
                                      icon: const Icon(Icons.remove_rounded,
                                          color: Colors.white),
                                    ),
                                    IconButton(
                                      tooltip: 'Reset view',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: _resetView,
                                      icon: const Icon(
                                          Icons.center_focus_strong,
                                          color: Colors.white,
                                          size: 19),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  const Icon(Icons.spa_outlined,
                      size: 16, color: Color(0xFFF3D36A)),
                  const SizedBox(width: 6),
                  const Text(
                    'LATEST TREE ESTIMATES',
                    style: TextStyle(
                      color: Color(0xFFD9E9D0),
                      fontFamily: 'monospace',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$mangoCount mangoes',
                    style: const TextStyle(
                      color: Color(0xFFFFE08A),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _positionedTree(
    OrchardTreeRef tree,
    Size size,
    ScanRecord? scan, {
    required int laneCount,
    required int maxTreesPerLane,
    required double viewportWidth,
  }) {
    final point = _treePoint(tree, size, laneCount, maxTreesPerLane);
    // A slightly smaller hit area keeps neighboring canopies from covering
    // each other's tap targets, especially where isometric rows cross.
    final diameter = viewportWidth * 0.19;
    return Positioned(
      left: point.dx - diameter / 2,
      top: point.dy - diameter * 0.63,
      width: diameter,
      height: diameter * 1.1,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _TreePainter(
                  lane: tree.lane,
                  number: tree.number,
                  count: scan?.currentTotal,
                  selected: widget.selectedTreeId == tree.id,
                  seed: tree.lane * 19 + tree.number,
                ),
              ),
            ),
          ),
          Positioned(
            left: diameter * 0.11,
            top: diameter * 0.07,
            width: diameter * 0.78,
            height: diameter * 0.78,
            child: Semantics(
              button: true,
              label: '${tree.label}, ${scan?.currentTotal ?? 0} mangoes',
              child: ClipOval(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onTreeSelected(tree),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Offset _treePoint(
  OrchardTreeRef tree,
  Size size,
  int laneCount,
  int maxTreesPerLane,
) {
  final extraLanes = math.max(0, laneCount - 3);
  final extraTrees = math.max(0, maxTreesPerLane - 3);
  final designWidth = 400.0 + extraTrees * 86 + extraLanes * 31;
  final designHeight = 280.0 + extraTrees * 14 + extraLanes * 57;
  final sx = size.width / designWidth;
  final sy = size.height / designHeight;
  final row = tree.lanePosition - 1;
  final col = tree.treePosition - 1;
  // Visual positions compact after removals, while stable IDs keep old scans
  // associated with their original tree and lane.
  return Offset(
    (71 + col * 86 + row * 31) * sx,
    (191 + col * 14 - row * 57 + extraLanes * 57) * sy,
  );
}

class _OrchardPainter extends CustomPainter {
  final List<int> laneIds;
  final int maxTreesPerLane;

  int get laneCount => laneIds.length;

  const _OrchardPainter({
    required this.laneIds,
    required this.maxTreesPerLane,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final extraLanes = math.max(0, laneCount - 3);
    final extraTrees = math.max(0, maxTreesPerLane - 3);
    final designWidth = 400.0 + extraTrees * 86 + extraLanes * 31;
    final designHeight = 280.0 + extraTrees * 14 + extraLanes * 57;
    final sx = size.width / designWidth;
    final sy = size.height / designHeight;
    Offset p(double x, double y) => Offset(x * sx, (y + extraLanes * 57) * sy);
    final topLeftX = 112.0 + extraLanes * 31;
    final topLeftY = 31.0 - extraLanes * 57;
    final topRightX = 388.0 + extraTrees * 86 + extraLanes * 31;
    final topRightY = 97.0 + extraTrees * 14 - extraLanes * 57;
    final bottomRightX = 288.0 + extraTrees * 86;
    final bottomRightY = 269.0 + extraTrees * 14;
    final bg = Paint()..color = const Color(0xFF819C58);
    canvas.drawRect(Offset.zero & size, bg);

    final field = Path()
      ..moveTo(p(12, 228).dx, p(12, 228).dy)
      ..lineTo(p(topLeftX, topLeftY).dx, p(topLeftX, topLeftY).dy)
      ..lineTo(p(topRightX, topRightY).dx, p(topRightX, topRightY).dy)
      ..lineTo(
          p(bottomRightX, bottomRightY).dx, p(bottomRightX, bottomRightY).dy)
      ..close();
    canvas.drawPath(field, Paint()..color = const Color(0xFFA98D5F));

    final interior = Path()
      ..moveTo(p(21, 221).dx, p(21, 221).dy)
      ..lineTo(
          p(topLeftX + 5, topLeftY + 8).dx, p(topLeftX + 5, topLeftY + 8).dy)
      ..lineTo(p(topRightX - 9, topRightY + 5).dx,
          p(topRightX - 9, topRightY + 5).dy)
      ..lineTo(p(bottomRightX - 5, bottomRightY - 8).dx,
          p(bottomRightX - 5, bottomRightY - 8).dy)
      ..close();
    canvas.drawPath(interior, Paint()..color = const Color(0xFF78934F));

    // Isometric planting lanes and pale tractor paths.
    for (var lane = 0; lane <= laneCount; lane++) {
      final start = p(28 + lane * 31, 217 - lane * 57);
      final end = p(
        287 + lane * 24 + extraTrees * 86,
        260 - lane * 53 + extraTrees * 14,
      );
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFC8B487).withOpacity(0.88)
          ..strokeWidth = 7 * math.min(sx, sy)
          ..strokeCap = StrokeCap.butt,
      );
      final inner = Path()
        ..moveTo(start.dx, start.dy - 2 * sy)
        ..lineTo(end.dx, end.dy - 2 * sy);
      canvas.drawPath(
        inner,
        Paint()
          ..color = const Color(0xFFE1D0A5).withOpacity(0.55)
          ..strokeWidth = 1 * math.min(sx, sy),
      );
    }
    for (var lane = 0; lane < laneCount; lane++) {
      _drawLabel(
        canvas,
        'L${laneIds[lane]}',
        p(14 + lane * 31, 219 - lane * 57),
        6.5 * math.min(sx, sy),
      );
    }
    final border = Path()
      ..moveTo(p(12, 228).dx, p(12, 228).dy)
      ..lineTo(p(topLeftX, topLeftY).dx, p(topLeftX, topLeftY).dy)
      ..lineTo(p(topRightX, topRightY).dx, p(topRightX, topRightY).dy)
      ..lineTo(
          p(bottomRightX, bottomRightY).dx, p(bottomRightX, bottomRightY).dy)
      ..close();
    canvas.drawPath(
      border,
      Paint()
        ..color = const Color(0xFFD8C89E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    _drawLabel(
      canvas,
      'FIELD ENTRANCE',
      p(112 + extraTrees * 30, 246 + extraTrees * 14),
      6.5 * math.min(sx, sy),
    );
    _drawLabel(
        canvas, 'N', p(topRightX - 15, topRightY - 10), 7 * math.min(sx, sy));
    for (final point in [
      p(12, 228),
      p(topLeftX, topLeftY),
      p(topRightX, topRightY),
      p(bottomRightX, bottomRightY),
    ]) {
      canvas.drawCircle(point, 1.6 * math.min(sx, sy),
          Paint()..color = const Color(0xFFF3E4BB));
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset point, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF344A30).withOpacity(0.82),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, point);
  }

  bool _sameLaneIds(List<int> other) {
    if (other.length != laneIds.length) return false;
    for (var i = 0; i < laneIds.length; i++) {
      if (other[i] != laneIds[i]) return false;
    }
    return true;
  }

  @override
  bool shouldRepaint(covariant _OrchardPainter oldDelegate) =>
      !oldDelegate._sameLaneIds(laneIds) ||
      oldDelegate.maxTreesPerLane != maxTreesPerLane;
}

class _TreePainter extends CustomPainter {
  final int lane;
  final int number;
  final int? count;
  final bool selected;
  final int seed;

  const _TreePainter({
    required this.lane,
    required this.number,
    required this.count,
    required this.selected,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 92;
    final center = Offset(size.width * 0.5, size.height * 0.42);
    final crown = 31 * s;
    final ground = Paint()..color = const Color(0xFF4B5730).withOpacity(0.4);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + 8 * s, size.height * 0.89),
        width: 72 * s,
        height: 17 * s,
      ),
      ground,
    );

    final trunk = Path()
      ..moveTo(center.dx - 4 * s, center.dy + 16 * s)
      ..lineTo(center.dx + 5 * s, center.dy + 16 * s)
      ..lineTo(center.dx + 7 * s, size.height * 0.91)
      ..lineTo(center.dx - 5 * s, size.height * 0.91)
      ..close();
    canvas.drawPath(trunk, Paint()..color = const Color(0xFF69462D));
    canvas.drawLine(
        center,
        Offset(center.dx - 14 * s, center.dy + 8 * s),
        Paint()
          ..color = const Color(0xFF755034)
          ..strokeWidth = 4.5 * s);
    canvas.drawLine(
        center,
        Offset(center.dx + 16 * s, center.dy + 4 * s),
        Paint()
          ..color = const Color(0xFF755034)
          ..strokeWidth = 4 * s);

    final shadow = Paint()..color = const Color(0xFF173A28).withOpacity(0.42);
    canvas.drawCircle(center.translate(3 * s, 4 * s), crown + 1 * s, shadow);
    canvas.drawCircle(
      center,
      crown + 5 * s,
      Paint()
        ..color = selected ? const Color(0xFF95E3C7) : const Color(0xFF345B35),
    );
    canvas.drawCircle(
        center, crown + 2 * s, Paint()..color = const Color(0xFF174A31));

    // Irregular layered foliage and small highlights create a fuller canopy.
    final random = math.Random(seed);
    for (var i = 0; i < 18; i++) {
      final angle = i * math.pi * 2 / 18;
      final radius = crown * (0.25 + random.nextDouble() * 0.48);
      final leafCenter = center.translate(
        math.cos(angle) * radius,
        math.sin(angle) * radius * 0.78,
      );
      final leafRadius = (5.5 + random.nextDouble() * 4.5) * s;
      final shades = [
        const Color(0xFF28633B),
        const Color(0xFF367642),
        const Color(0xFF4B8547),
        const Color(0xFF215638),
      ];
      canvas.drawCircle(
          leafCenter, leafRadius, Paint()..color = shades[i % shades.length]);
      canvas.drawCircle(
        leafCenter.translate(-leafRadius * 0.22, -leafRadius * 0.28),
        leafRadius * 0.25,
        Paint()..color = const Color(0xFF9DBD62).withOpacity(0.6),
      );
    }

    // Give every mango its own visible fruit. For exceptionally crowded
    // canopies, the label still preserves the exact saved count.
    final fruitCount = count == null ? 0 : math.min(24, count!);
    for (var i = 0; i < fruitCount; i++) {
      final angle = i * 2.399963229728653 + seed * 0.37;
      final radius = crown * 0.76 * math.sqrt((i + 0.5) / fruitCount);
      final fruit = center.translate(
          math.cos(angle) * radius, math.sin(angle) * radius * 0.72);
      canvas.save();
      canvas.translate(fruit.dx, fruit.dy);
      canvas.rotate(-0.3);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 5.5 * s, height: 8 * s),
        Paint()..color = const Color(0xFFF4C64F),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(-1.1 * s, -1.2 * s),
          width: 1.4 * s,
          height: 3.4 * s,
        ),
        Paint()..color = const Color(0xFFFFE78E),
      );
      canvas.restore();
    }

    final label =
        count == null ? 'L$lane T$number: --' : 'L$lane T$number: $count';
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 8.5 * s,
          fontWeight: FontWeight.w800,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, size.height * 0.9),
        width: text.width + 12 * s,
        height: text.height + 6 * s,
      ),
      Radius.circular(4 * s),
    );
    canvas.drawRRect(labelRect, Paint()..color = const Color(0xFF173A2A));
    text.paint(canvas, Offset(labelRect.left + 6 * s, labelRect.top + 3 * s));
  }

  @override
  bool shouldRepaint(covariant _TreePainter oldDelegate) =>
      oldDelegate.count != count ||
      oldDelegate.selected != selected ||
      oldDelegate.lane != lane ||
      oldDelegate.number != number;
}

class OrchardTreeDetailsSheet extends StatelessWidget {
  final OrchardTreeRef tree;
  final ScanRecord? latestScan;
  final VoidCallback onCameraScan;
  final VoidCallback onGalleryScan;
  final VoidCallback onVideoScan;

  const OrchardTreeDetailsSheet({
    super.key,
    required this.tree,
    required this.latestScan,
    required this.onCameraScan,
    required this.onGalleryScan,
    required this.onVideoScan,
  });

  @override
  Widget build(BuildContext context) {
    final scan = latestScan;
    final text = Theme.of(context).colorScheme.onSurface;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: const Icon(Icons.park_rounded,
                      size: 32, color: AppColors.primaryGreen),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tree.label,
                          style: TextStyle(
                              color: text,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                      Text('Mango orchard / Lane ${tree.lane}',
                          style: const TextStyle(
                              color: AppColors.mutedGraphite, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F7F2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: scan == null
                  ? const Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.primaryGreen),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This tree has not been scanned yet. Its mango count will appear here after you save a scan.',
                            style: TextStyle(height: 1.35),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${scan.currentTotal}',
                                style: const TextStyle(
                                    color: AppColors.primaryGreen,
                                    fontSize: 34,
                                    height: 1,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(width: 8),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 3),
                              child: Text('mangoes in latest scan',
                                  style: TextStyle(
                                      color: AppColors.mutedGraphite,
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _countPill('Ripe', scan.currentRipe,
                                const Color(0xFFE49A20)),
                            _countPill('Unripe', scan.currentUnripe,
                                const Color(0xFF548A48)),
                            _countPill('Overripe', scan.currentOverRipe,
                                const Color(0xFF9B6545)),
                          ],
                        ),
                        const SizedBox(height: 9),
                        Text(
                          'Scanned ${DateTime.fromMillisecondsSinceEpoch(scan.createdAt).toLocal().toString().substring(0, 16)}',
                          style: const TextStyle(
                              color: AppColors.mutedGraphite, fontSize: 11),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            const Text(
              'UPDATE TREE COUNT',
              style: TextStyle(
                color: AppColors.mutedGraphite,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onCameraScan,
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Scan this tree with camera'),
            ),
            const SizedBox(height: 7),
            OutlinedButton.icon(
              onPressed: onVideoScan,
              icon: const Icon(Icons.videocam_rounded),
              label: const Text('Scan whole tree with video'),
            ),
            TextButton.icon(
              onPressed: onGalleryScan,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose tree photo from gallery'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countPill(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$label $count',
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
