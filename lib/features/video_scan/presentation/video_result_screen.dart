import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_theme.dart';
import '../../detection/domain/detection.dart';
import '../../detection/presentation/widgets/detection_overlay.dart';
import '../../chat/domain/scan_chat_context.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../history/application/history_controller.dart';
import '../../history/domain/scan_record.dart';
import '../domain/video_scan_result.dart';

class VideoResultScreen extends ConsumerStatefulWidget {
  final VideoScanResult result;
  final String? treeId;

  const VideoResultScreen({
    super.key,
    required this.result,
    this.treeId,
  });

  @override
  ConsumerState<VideoResultScreen> createState() => _VideoResultScreenState();
}

class _VideoResultScreenState extends ConsumerState<VideoResultScreen> {
  int _selectedFrameIndex = 0;
  bool _showLabels = true;
  bool _isSaved = false;
  bool _isSaving = false;

  void _openChat([String? initialQuestion]) {
    final curFrame = widget.result.frames.isNotEmpty
        ? widget.result.frames[_selectedFrameIndex]
        : null;

    final scanContext = ScanChatContext(
      imageBytes: curFrame?.imageBytes,
      originalPath: widget.result.videoPath,
      totalCount: widget.result.totalUniqueCount,
      ripeCount: widget.result.ripeCount,
      unripeCount: widget.result.unripeCount,
      overRipeCount: widget.result.overRipeCount,
      inferenceMs: widget.result.inferenceTimeMs,
      confThreshold: widget.result.confThreshold,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          scanContext: scanContext,
          initialQuestion: initialQuestion ??
              'I just scanned this whole mango tree using video. We counted ${widget.result.totalUniqueCount} mangoes (${widget.result.ripeCount} ripe, ${widget.result.unripeCount} green). What is your advice on harvest timing and fruit care?',
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_isSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tree video scan already saved!')),
      );
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final curFrame = widget.result.frames.isNotEmpty
          ? widget.result.frames[_selectedFrameIndex]
          : null;

      String savedImagePath = widget.result.videoPath;
      if (curFrame != null) {
        final dir = await getApplicationDocumentsDirectory();
        final imgPath =
            '${dir.path}/tree_scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(imgPath).writeAsBytes(curFrame.imageBytes);
        savedImagePath = imgPath;
      }

      final frameDetections = curFrame?.detections ?? <Detection>[];
      final record = ScanRecord(
        id: const Uuid().v4(),
        treeId: widget.treeId,
        imagePath: savedImagePath,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        modelRipe: widget.result.ripeCount,
        modelUnripe: widget.result.unripeCount,
        modelHalfRipe: widget.result.overRipeCount,
        confThreshold: widget.result.confThreshold,
        iouThreshold: widget.result.iouThreshold,
        inferenceMs: widget.result.inferenceTimeMs,
        imageWidth: curFrame?.imageWidth ?? 640,
        imageHeight: curFrame?.imageHeight ?? 640,
        isDemo: false,
        detections: frameDetections,
        modelDetections: frameDetections,
      );

      await ref.read(historyProvider.notifier).addScan(record);
      if (!mounted) return;
      setState(() => _isSaved = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.treeId == null
                ? 'Whole tree scan saved to history! 🌾'
                : 'Scan saved and tree count updated! 🌾'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to save record: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _finishScan() async {
    if (!_isSaved) await _save();
    if (mounted && _isSaved) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimaryMint : AppColors.primaryGreen;
    final amber = isDark ? AppColors.darkRipeAmber : AppColors.ripeAmber;
    final surface = isDark ? AppColors.darkSurface : AppColors.surfaceWhite;
    final background = isDark ? AppColors.darkCanopy : AppColors.canvasCream;
    final text = isDark ? AppColors.darkTextParchment : AppColors.charcoalText;
    final muted = isDark ? AppColors.darkMutedMist : AppColors.mutedGraphite;

    final frames = widget.result.frames;
    final curFrame = frames.isNotEmpty ? frames[_selectedFrameIndex] : null;
    final lowConfidenceCount = curFrame?.detections
            .where((detection) => detection.confidence < 0.5)
            .length ??
        0;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Whole-Tree Mango Count',
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
            Text(
              'COUNTED WITHOUT DUPLICATES',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: primary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showLabels ? Icons.label_rounded : Icons.label_off_rounded,
            ),
            tooltip: _showLabels ? 'Hide Labels' : 'Show Labels',
            onPressed: () => setState(() => _showLabels = !_showLabels),
          ),
          IconButton(
            icon: const Icon(Icons.psychology_alt_outlined),
            tooltip: 'Ask Harvest Assistant',
            onPressed: () => _openChat(),
          ),
          IconButton(
            icon: Icon(
              _isSaved ? Icons.bookmark : Icons.bookmark_add_outlined,
              color: _isSaved ? primary : null,
            ),
            tooltip: widget.treeId == null
                ? 'Save Scan'
                : 'Save scan and update this tree',
            onPressed: _isSaving ? null : _save,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (lowConfidenceCount > 0)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: const Color(0xFFFFF3D6),
                child: Text(
                  '$lowConfidenceCount detection${lowConfidenceCount == 1 ? '' : 's'} below 50% confidence in this frame. Check the selected frame before saving.',
                  style: const TextStyle(
                    color: Color(0xFF704B00),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            // Top Frame Viewer with Detection Overlay
            Expanded(
              flex: 5,
              child: Container(
                color: Colors.black,
                child: curFrame != null
                    ? Center(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              curFrame.imageBytes,
                              fit: BoxFit.contain,
                            ),
                            DetectionOverlay(
                              detections: curFrame.detections,
                              imageWidth: curFrame.imageWidth,
                              imageHeight: curFrame.imageHeight,
                              showLabels: _showLabels,
                              showBoxes: true,
                            ),
                          ],
                        ),
                      )
                    : const Center(
                        child: Text(
                          'No frames available',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
              ),
            ),

            // Keyframe Scrubber Carousel
            if (frames.length > 1)
              Container(
                height: 70,
                color:
                    isDark ? const Color(0xFF101B14) : const Color(0xFFEBF6EE),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: frames.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final frame = frames[index];
                    final isSelected = index == _selectedFrameIndex;

                    return GestureDetector(
                      onTap: () => setState(() => _selectedFrameIndex = index),
                      child: Container(
                        width: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? primary : Colors.transparent,
                            width: 2.2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                frame.imageBytes,
                                fit: BoxFit.cover,
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  color: Colors.black.withOpacity(0.65),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 1),
                                  child: Text(
                                    '${(frame.timestampMs / 1000).toStringAsFixed(1)}s',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
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
              ),

            // Botanical Console Sheet for Whole Tree Results
            Expanded(
              flex: 5,
              child: Container(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: AppShapes.consoleSheet,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 16,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Total Count Instrument Cluster
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF101B14)
                                  : const Color(0xFFEBF6EE),
                              borderRadius: AppShapes.leafCut,
                              border:
                                  Border.all(color: primary.withOpacity(0.3)),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${widget.result.totalUniqueCount}',
                                  style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800,
                                    color: text,
                                    height: 1.05,
                                  ),
                                ),
                                Text(
                                  'VISIBLE ESTIMATE',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                    color: primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _buildPill(
                                        'Ripe: ${widget.result.ripeCount}',
                                        amber),
                                    const SizedBox(width: 6),
                                    _buildPill(
                                        'Unripe: ${widget.result.unripeCount}',
                                        AppColors.unripeGreen),
                                    const SizedBox(width: 6),
                                    _buildPill(
                                        'Over: ${widget.result.overRipeCount}',
                                        AppColors.overRipeEarth),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Visible fruit estimate. Hidden or revisited fruit can affect the count.\nFrame ${_selectedFrameIndex + 1}/${frames.length} · ${curFrame?.detections.length ?? 0} in view',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    color: muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Anti-Duplication & Telemetry Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF14241B)
                              : const Color(0xFFF3FAF5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: primary.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.verified_outlined,
                                size: 18, color: primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ACCURATE COUNT',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: primary,
                                    ),
                                  ),
                                  Text(
                                    'Removed ${widget.result.duplicateDetectionsFiltered} duplicate counts · Leaves and non-fruits filtered out',
                                    style:
                                        TextStyle(fontSize: 11.5, color: text),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // AI Harvest Assistant Consultation Button
                      Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.sunsetGradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF8A3D).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.psychology_alt_rounded,
                              color: Colors.white, size: 20),
                          label: const Text(
                            'ASK HARVEST ASSISTANT ABOUT THIS TREE',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => _openChat(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: widget.treeId == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _finishScan,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.done_rounded),
                    label: Text(_isSaving ? 'Saving tree count...' : 'Done'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: AppShapes.pill,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
