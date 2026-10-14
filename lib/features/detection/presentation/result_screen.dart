import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;
import '../../../core/theme/app_theme.dart';
import '../application/detection_controller.dart';
import '../application/detector_provider.dart';
import '../../history/application/history_controller.dart';
import '../../history/domain/scan_record.dart';
import '../domain/detection.dart';
import '../domain/mango_class.dart';
import '../domain/auto_confidence_calculator.dart';
import '../data/gemini_assistant_service.dart';
import 'widgets/detection_overlay.dart';
import 'widgets/analyzing_view.dart';
import '../../settings/application/settings_controller.dart';
import '../../chat/domain/scan_chat_context.dart';
import '../../chat/presentation/chat_screen.dart';

/// Screen 3 of Stitch: "Result - Photo View" (#aa5c52df83f148a5ace182ff252f1c78).
/// Combines an optical viewfinder canvas with the AgriPrecision Botanical console sheet.
class ResultScreen extends ConsumerStatefulWidget {
  final Uint8List imageBytes;
  final String originalPath;
  final String? treeId;

  const ResultScreen({
    super.key,
    required this.imageBytes,
    required this.originalPath,
    this.treeId,
  });

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  bool _showLabels = true;
  final bool _showBoxes = true;
  double _confThreshold = 0.25;
  bool _isAiVerifying = false;
  bool _isAddMangoMode = false;
  bool _hasTriggeredAutoAi = false;
  String _aiStatusMessage = 'AI is analyzing fruit crops... ✨';
  String? _lastAiProvider;

  /// True once YOLO has produced a result for THIS image (prevents showing a stale previous scan).
  bool _yoloReady = false;

  /// Outcome of the last automatic AI pass (used for the AI status line).
  bool _aiCompleted = false;
  int _aiRemovedCount = 0;
  int _aiNeedsReviewCount = 0;

  /// Confidence mode: automatic calibration vs manual slider override.
  bool _isAutoConfidence = true;
  bool _showConfSlider = false;

  List<Detection> _allDetections = [];
  List<Detection> _filteredDetections = [];
  List<Detection> _yoloOriginalDetections = [];
  List<Detection> _aiReconciledDetections = [];
  bool _showAiVerified = true;

  final TextEditingController _actualCountCtrl = TextEditingController();
  img.Image? _cachedOrientedImage;
  bool _isSaving = false;
  bool _hasSaved = false;

  img.Image? _getOrientedImage() {
    if (_cachedOrientedImage != null) return _cachedOrientedImage;
    try {
      final decoded = img.decodeImage(widget.imageBytes);
      if (decoded != null) {
        _cachedOrientedImage = img.bakeOrientation(decoded);
      }
    } catch (_) {}
    return _cachedOrientedImage;
  }

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _isAutoConfidence = settings.autoConfidence;
    _confThreshold = settings.confThreshold;
    _showLabels = settings.showLabels;
    _allDetections = [];
    _filteredDetections = [];
    _hasTriggeredAutoAi = false;

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _runDetectionPipeline());
  }

  /// Runs YOLO for this image, then (when online) the AI verification pass.
  Future<void> _runDetectionPipeline() async {
    final controller = ref.read(detectionControllerProvider.notifier);
    controller.reset();
    await controller.processImage(widget.imageBytes);
    if (!mounted) return;

    final result = ref.read(detectionControllerProvider).result;
    setState(() {
      _yoloReady = true;
      _allDetections =
          result != null ? List<Detection>.from(result.detections) : [];
      _yoloOriginalDetections = List<Detection>.from(_allDetections);
      _updateFiltered();
    });

    if (result != null && !_hasTriggeredAutoAi) {
      _hasTriggeredAutoAi = true;
      _triggerAutomaticAiAssistAdaptive();
    }
  }

  @override
  void dispose() {
    _actualCountCtrl.dispose();
    super.dispose();
  }

  /// Recomputes the visible detections based on Auto or Manual confidence.
  void _updateFiltered({double? manualConf}) {
    if (_isAutoConfidence && manualConf == null) {
      final autoConf = AutoConfidenceCalculator.calculate(_allDetections);
      _confThreshold = autoConf;
      _filteredDetections =
          AutoConfidenceCalculator.filterDetections(_allDetections, autoConf);
    } else {
      final conf = manualConf ?? _confThreshold;
      _confThreshold = conf;
      _filteredDetections = _allDetections.where((d) {
        if (d.userEdited || d.aiVerified) return true;
        return d.confidence >= conf;
      }).toList();
    }
  }

  /// Automatically and adaptively triggers per-crop AI ripeness verification
  Future<void> _triggerAutomaticAiAssistAdaptive() async {
    final settings = ref.read(settingsProvider);
    if (!settings.autoAiAssist) return;

    final hasKey = settings.geminiApiKey.isNotEmpty ||
        GeminiAssistantService.defaultApiKey.isNotEmpty;
    if (!hasKey || !mounted) return;

    setState(() {
      _isAiVerifying = true;
      _aiStatusMessage = 'Gemini AI verifying fruit crops... ✨';
    });

    try {
      final state = ref.read(detectionControllerProvider);
      final imgW = state.result?.imageWidth ?? 1920;
      final imgH = state.result?.imageHeight ?? 1080;

      final sentSnapshot = List<Detection>.from(_allDetections);

      final result = await GeminiAssistantService.assistDetectionAndCount(
        fullImageBytes: widget.imageBytes,
        existingYoloDetections: sentSnapshot,
        imageWidth: imgW,
        imageHeight: imgH,
        geminiApiKey: settings.geminiApiKey,
      );

      if (!mounted) return;

      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ??
                'Online verification unavailable (showing standard scan results)'),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      // A response applies only to detections still present in the request
      // snapshot. Manual deletions and class edits made while waiting win.
      final unchanged = sentSnapshot.where(_allDetections.contains).toList();
      bool sameBox(Detection a, Detection b) =>
          a.x1 == b.x1 && a.y1 == b.y1 && a.x2 == b.x2 && a.y2 == b.y2;
      final addedByUser = _allDetections.where((d) => d.userEdited).toList();
      final merged = result.reconciledDetections
          .where((d) =>
              unchanged.any((original) => sameBox(original, d)) &&
              !addedByUser.any((edited) => sameBox(edited, d)))
          .toList();
      for (final u in addedByUser) {
        if (!merged.contains(u)) merged.add(u);
      }

      _aiReconciledDetections = List<Detection>.from(merged);
      _lastAiProvider = result.providerName;
      _aiCompleted = true;
      _aiRemovedCount = result.rejectedCount;
      _aiNeedsReviewCount = result.needsReviewCount;

      setState(() {
        _showAiVerified = true;
        _allDetections = List<Detection>.from(merged);
        _updateFiltered();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI verification failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAiVerifying = false);
      }
    }
  }

  Future<void> _verifySingleWithAi(Detection det) async {
    final settings = ref.read(settingsProvider);
    var apiKey = settings.geminiApiKey;
    if (apiKey.isEmpty && GeminiAssistantService.defaultApiKey.isNotEmpty) {
      apiKey = GeminiAssistantService.defaultApiKey;
    }
    if (apiKey.isEmpty) {
      final entered = await _promptApiKeyDialog();
      if (entered == null || entered.isEmpty) return;
      apiKey = entered;
    }

    setState(() {
      _isAiVerifying = true;
      _aiStatusMessage = 'Verifying selected fruit...';
    });

    try {
      // Use the same padded, aspect-ratio-preserving crop as automatic review.
      // This retains peel texture and enough leaf context to identify occlusion.
      final crops = GeminiAssistantService.extractCrops(
        fullImageBytes: widget.imageBytes,
        detections: [det.copyWith(userEdited: false)],
        candidateMinConf: 0,
      );
      if (crops.isEmpty) throw Exception('Could not prepare image crop');

      final verdicts = await GeminiAssistantService.verifyCropsBatch(
        crops: crops,
        apiKey: apiKey,
      );

      if (!mounted) return;

      final verdict = verdicts[0];
      if (verdict != null) {
        setState(() {
          final idx = _allDetections.indexOf(det);
          if (idx != -1) {
            _allDetections[idx] = det.copyWith(
              mangoClass: verdict.isMango
                  ? verdict.ripeness ?? det.mangoClass
                  : det.mangoClass,
              aiVerified: true,
              aiReason: verdict.reason,
              needsReview: !verdict.isMango,
            );
            _updateFiltered();
          }
        });

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.purple),
                const SizedBox(width: 8),
                Text(verdict.isMango
                    ? 'AI Confirmed: ${verdict.ripeness?.displayName ?? det.mangoClass.displayName}'
                    : 'AI: Not a Mango'),
              ],
            ),
            content: Text(verdict.reason.isNotEmpty
                ? verdict.reason
                : 'AI inspection completed.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('AI verification failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAiVerifying = false);
      }
    }
  }

  Future<String?> _promptApiKeyDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.purple),
            SizedBox(width: 8),
            Text('Gemini API Key Needed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your Google Gemini API key to enable AI-assisted detection and ripeness verification.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Gemini API Key',
                hintText: 'AIzaSy...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final key = ctrl.text.trim();
              if (key.isNotEmpty) {
                ref.read(settingsProvider.notifier).updateGeminiApiKey(key);
              }
              Navigator.pop(ctx, key);
            },
            child: const Text('Save & Verify'),
          ),
        ],
      ),
    );
  }

  Future<void> _onAddMangoAtPoint(double imageX, double imageY) async {
    final state = ref.read(detectionControllerProvider);
    final imgW = state.result?.imageWidth ?? 1000;
    final imgH = state.result?.imageHeight ?? 1000;

    double baseW = 0;
    double baseH = 0;
    if (_filteredDetections.isNotEmpty) {
      double sumW = 0;
      double sumH = 0;
      for (final d in _filteredDetections) {
        sumW += (d.x2 - d.x1).abs();
        sumH += (d.y2 - d.y1).abs();
      }
      baseW = sumW / _filteredDetections.length;
      baseH = sumH / _filteredDetections.length;
    } else {
      baseW = imgW * 0.16;
      baseH = imgH * 0.16;
    }

    double sizeMultiplier = 1.0;
    MangoClass selectedClass = MangoClass.ripe;

    final oriented = _getOrientedImage();

    Uint8List? getPreviewBytes(double mult) {
      if (oriented == null) return null;
      final w = (baseW * mult).clamp(20.0, oriented.width.toDouble());
      final h = (baseH * mult).clamp(20.0, oriented.height.toDouble());
      int cx = (imageX - w / 2).toInt().clamp(0, oriented.width - 1);
      int cy = (imageY - h / 2).toInt().clamp(0, oriented.height - 1);
      int cw = w.toInt().clamp(10, oriented.width - cx);
      int ch = h.toInt().clamp(10, oriented.height - cy);

      final crop = img.copyCrop(oriented, x: cx, y: cy, width: cw, height: ch);
      final resized = img.copyResize(crop, width: 220, height: 220);
      return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
    }

    Uint8List? cropBytes = getPreviewBytes(sizeMultiplier);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppShapes.consoleSheet),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.add_circle,
                            color: AppColors.ripeAmber, size: 24),
                        const SizedBox(width: 10),
                        const Text(
                          'Add Mango',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (cropBytes != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              cropBytes!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Box Size',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Slider(
                                value: sizeMultiplier,
                                min: 0.5,
                                max: 2.0,
                                divisions: 15,
                                label: '${(sizeMultiplier * 100).toInt()}%',
                                onChanged: (val) {
                                  setSheetState(() {
                                    sizeMultiplier = val;
                                    cropBytes = getPreviewBytes(val);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: MangoClass.values.map((c) {
                        final isSel = selectedClass == c;
                        return ChoiceChip(
                          label: Text(c.displayName),
                          selected: isSel,
                          onSelected: (val) {
                            if (val) setSheetState(() => selectedClass = c);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text('Confirm ${selectedClass.displayName} Mango'),
                      onPressed: () {
                        final finalW = (baseW * sizeMultiplier)
                            .clamp(15.0, imgW.toDouble());
                        final finalH = (baseH * sizeMultiplier)
                            .clamp(15.0, imgH.toDouble());
                        final double x1 =
                            (imageX - finalW / 2).clamp(0.0, imgW.toDouble());
                        final double y1 =
                            (imageY - finalH / 2).clamp(0.0, imgH.toDouble());
                        final double x2 =
                            (x1 + finalW).clamp(0.0, imgW.toDouble());
                        final double y2 =
                            (y1 + finalH).clamp(0.0, imgH.toDouble());

                        final newDet = Detection(
                          x1: x1,
                          y1: y1,
                          x2: x2,
                          y2: y2,
                          mangoClass: selectedClass,
                          confidence: 0.95,
                          userEdited: true,
                          aiVerified: false,
                          aiReason: 'Manually added by grower',
                        );

                        setState(() {
                          _allDetections.add(newDet);
                          _updateFiltered();
                        });

                        Navigator.pop(ctx);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                '🥭 Added ${selectedClass.displayName} mango! Total: ${_filteredDetections.length}'),
                            backgroundColor: AppColors.primaryGreen,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _onBoxTap(Detection det) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppShapes.consoleSheet),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: Colors.purple),
                title: const Text('Verify ripeness with AI'),
                subtitle:
                    det.aiReason != null ? Text('AI: ${det.aiReason}') : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _verifySingleWithAi(det);
                },
              ),
              ListTile(
                leading: const Icon(Icons.change_circle_outlined,
                    color: AppColors.primaryGreen),
                title: const Text('Change ripeness'),
                onTap: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (c) => SimpleDialog(
                      title: const Text('Select Ripeness'),
                      children: [
                        SimpleDialogOption(
                          onPressed: () => _changeClass(det, MangoClass.ripe),
                          child: const Text('Ripe (Harvest Ready)'),
                        ),
                        SimpleDialogOption(
                          onPressed: () => _changeClass(det, MangoClass.unripe),
                          child: const Text('Unripe (Developing)'),
                        ),
                        SimpleDialogOption(
                          onPressed: () =>
                              _changeClass(det, MangoClass.over_ripe),
                          child: const Text('Over-ripe (Ground/Late)'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.errorCrimson),
                title: const Text('Remove fruit',
                    style: TextStyle(color: AppColors.errorCrimson)),
                onTap: () {
                  setState(() {
                    _allDetections.remove(det);
                    _updateFiltered();
                  });
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _changeClass(Detection det, MangoClass newClass) {
    setState(() {
      final index = _allDetections.indexOf(det);
      if (index != -1) {
        _allDetections[index] = det.copyWith(
          mangoClass: newClass,
          userEdited: true,
        );
        _updateFiltered();
      }
    });
  }

  Future<void> _save() async {
    final state = ref.read(detectionControllerProvider);
    if (state.result == null || _isSaving || _hasSaved) return;
    setState(() => _isSaving = true);
    try {
      final id = const Uuid().v4();
      final directory = await getApplicationDocumentsDirectory();
      final savedPath = '${directory.path}/scan_$id.image';
      await File(savedPath).writeAsBytes(widget.imageBytes, flush: true);

      int? actualCount;
      if (_actualCountCtrl.text.isNotEmpty) {
        actualCount = int.tryParse(_actualCountCtrl.text);
      }

      final overRipeCount = _filteredDetections
          .where((d) => d.mangoClass == MangoClass.over_ripe)
          .length;
      final ripeCount = _filteredDetections
          .where((d) => d.mangoClass == MangoClass.ripe)
          .length;
      final unripeCount = _filteredDetections
          .where((d) => d.mangoClass == MangoClass.unripe)
          .length;

      final record = ScanRecord(
        id: id,
        treeId: widget.treeId,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        imagePath: savedPath,
        imageWidth: state.result!.imageWidth,
        imageHeight: state.result!.imageHeight,
        modelHalfRipe: state.result!.overRipeCount,
        modelRipe: state.result!.ripeCount,
        modelUnripe: state.result!.unripeCount,
        editedHalfRipe: overRipeCount,
        editedRipe: ripeCount,
        editedUnripe: unripeCount,
        actualCount: actualCount,
        confThreshold: _confThreshold,
        iouThreshold: state.result!.iouThreshold,
        inferenceMs: state.result!.inferenceTimeMs,
        isDemo: ref.read(isDemoModeProvider),
        detections: _filteredDetections,
        modelDetections: state.result!.detections,
      );

      await ref.read(historyProvider.notifier).addScan(record);
      _hasSaved = true;

      if (actualCount != null) {
        final yoloCount = state.result?.detections.length ?? 0;
        final finalCount = _filteredDetections.length;
        final imageId = widget.originalPath.split(Platform.pathSeparator).last;
        await _appendEvaluationLog(
          imageId: imageId,
          yoloCount: yoloCount,
          finalCount: finalCount,
          actualCount: actualCount,
          usedGemini: _aiCompleted,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.treeId == null
                ? 'Harvest scan saved to history! 💾'
                : 'Scan saved and tree count updated! 💾'),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not save this scan. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _finishScan() async {
    if (!_hasSaved) await _save();
    if (mounted && _hasSaved) Navigator.of(context).pop();
  }

  Future<void> _appendEvaluationLog({
    required String imageId,
    required int yoloCount,
    required int finalCount,
    required int actualCount,
    required bool usedGemini,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/evaluation_logs.csv');
      final exists = await file.exists();
      final sink = file.openWrite(mode: FileMode.append);
      if (!exists) {
        sink.writeln(
            'timestamp,image_id,yolo_count,final_count,actual_count,used_gemini');
      }
      final now = DateTime.now().toIso8601String();
      sink.writeln(
          '$now,$imageId,$yoloCount,$finalCount,$actualCount,$usedGemini');
      await sink.flush();
      await sink.close();
      if (kDebugMode) {
        debugPrint(
            '[EvaluationLog] Appended record: image=$imageId, yolo=$yoloCount, final=$finalCount, actual=$actualCount, usedGemini=$usedGemini');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EvaluationLog] Failed to append log: $e');
      }
    }
  }

  void _openChat([String? initialQuestion]) {
    final count = int.tryParse(_actualCountCtrl.text.trim());
    final scanContext = ScanChatContext(
      imageBytes: widget.imageBytes,
      originalPath: widget.originalPath,
      totalCount: _filteredDetections.length,
      ripeCount: _filteredDetections
          .where((d) => d.mangoClass == MangoClass.ripe)
          .length,
      unripeCount: _filteredDetections
          .where((d) => d.mangoClass == MangoClass.unripe)
          .length,
      overRipeCount: _filteredDetections
          .where((d) => d.mangoClass == MangoClass.over_ripe)
          .length,
      inferenceMs:
          ref.read(detectionControllerProvider).result?.inferenceTimeMs ?? 0,
      confThreshold: _confThreshold,
      aiVerifiedCount: _filteredDetections.where((d) => d.aiVerified).length,
      userEditedCount: _filteredDetections.where((d) => d.userEdited).length,
      actualCount: count,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          scanContext: scanContext,
          initialQuestion: initialQuestion,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(detectionControllerProvider);
    final isDemo = ref.watch(isDemoModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primary = isDark ? AppColors.darkPrimaryMint : AppColors.primaryGreen;
    final amber = isDark ? AppColors.darkRipeAmber : AppColors.ripeAmber;
    final surface = isDark ? AppColors.darkSurface : AppColors.surfaceWhite;
    final text = isDark ? AppColors.darkTextParchment : AppColors.charcoalText;
    final muted = isDark ? AppColors.darkMutedMist : AppColors.mutedGraphite;

    // Screen 1: Analyzing State
    if (state.isProcessing || (!_yoloReady && state.error == null)) {
      return Scaffold(
        body: SafeArea(
          child: AnalyzingView(
            imageBytes: widget.imageBytes,
            statusStep: 'Finding mangoes and checking ripeness...',
          ),
        ),
      );
    }

    if (state.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: AppColors.errorCrimson),
                const SizedBox(height: 16),
                Text(state.error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Return to Home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final int overRipeCount = _filteredDetections
        .where((d) => d.mangoClass == MangoClass.over_ripe)
        .length;
    final int ripeCount = _filteredDetections
        .where((d) => d.mangoClass == MangoClass.ripe)
        .length;
    final int unripeCount = _filteredDetections
        .where((d) => d.mangoClass == MangoClass.unripe)
        .length;
    final int totalCount = _filteredDetections.length;
    final int aiVerifiedCount =
        _filteredDetections.where((d) => d.aiVerified).length;
    final int lowConfidenceCount =
        _filteredDetections.where((d) => d.confidence < 0.5).length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          'Scan Results',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: text,
          ),
        ),
        actions: [
          // Add missed fruit mode toggle
          IconButton(
            icon: Icon(
              _isAddMangoMode ? Icons.check_circle : Icons.add_circle_outline,
              color: _isAddMangoMode ? const Color(0xFF2E7D32) : amber,
            ),
            tooltip: _isAddMangoMode ? 'Done Adding' : 'Add Missed Mango (+)',
            onPressed: () => setState(() => _isAddMangoMode = !_isAddMangoMode),
          ),

          // A/B AI verified toggle
          if (_aiCompleted)
            IconButton(
              icon: Icon(
                _showAiVerified ? Icons.auto_awesome : Icons.layers_clear,
                color: _showAiVerified ? Colors.purple : muted,
              ),
              tooltip: _showAiVerified
                  ? 'Showing AI-checked (tap for standard scan)'
                  : 'Showing standard scan (tap for AI-checked)',
              onPressed: () {
                setState(() {
                  _showAiVerified = !_showAiVerified;
                  _allDetections = _showAiVerified
                      ? List<Detection>.from(_aiReconciledDetections)
                      : List<Detection>.from(_yoloOriginalDetections);
                  _updateFiltered();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_showAiVerified
                        ? 'Switched to AI-checked results ✨'
                        : 'Switched to standard scan results 🥭'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),

          if (_isAiVerifying)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: amber),
                ),
              ),
            ),

          // Consult AI Agronomist Chatbot
          IconButton(
            icon: const Icon(Icons.psychology_alt_outlined),
            tooltip: 'Ask Harvest Assistant',
            onPressed: () => _openChat(),
          ),

          // Save button
          IconButton(
            icon:
                Icon(_hasSaved ? Icons.bookmark : Icons.bookmark_add_outlined),
            tooltip: widget.treeId == null
                ? 'Save Scan'
                : 'Save scan and update this tree',
            onPressed: _save,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Add Fruit Banner
          if (_isAddMangoMode)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: const Color(0xFFFFECC8),
              width: double.infinity,
              child: Row(
                children: [
                  const Icon(Icons.touch_app,
                      color: Color(0xFFE65100), size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tap any missed fruit on photo to mark it',
                      style: TextStyle(
                          color: Color(0xFF5D4037),
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => setState(() => _isAddMangoMode = false),
                    child: const Text('DONE',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          // AI Verification in-flight banner
          if (_isAiVerifying)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              color: Colors.purple.shade50,
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.purple),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _aiStatusMessage,
                      style: const TextStyle(
                          color: Colors.purple,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Demo Mode pill banner
          if (isDemo)
            Container(
              padding: const EdgeInsets.all(4),
              color: const Color(0xFFFFE0B2),
              width: double.infinity,
              child: const Text(
                'DEMO MODE: model not found. Results are NOT real.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFFBF360C),
                    fontWeight: FontWeight.bold,
                    fontSize: 11),
              ),
            ),

          if (lowConfidenceCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFFFFF3D6),
              child: Row(
                children: [
                  const Icon(Icons.fact_check_outlined,
                      color: Color(0xFF9A6500), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$lowConfidenceCount detection${lowConfidenceCount == 1 ? '' : 's'} below 50% confidence. Review the marked fruit before saving.',
                      style: const TextStyle(
                        color: Color(0xFF704B00),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Interactive Viewfinder Image Canvas
          Expanded(
            child: InteractiveViewer(
              panEnabled: !_isAddMangoMode,
              scaleEnabled: !_isAddMangoMode,
              minScale: 1.0,
              maxScale: 4.0,
              child: Center(
                child: Stack(
                  children: [
                    Image.memory(widget.imageBytes, fit: BoxFit.contain),
                    if (state.result != null)
                      Positioned.fill(
                        child: DetectionOverlay(
                          detections: _filteredDetections,
                          imageWidth: state.result!.imageWidth,
                          imageHeight: state.result!.imageHeight,
                          showLabels: _showLabels,
                          showBoxes: _showBoxes,
                          onBoxTap: _onBoxTap,
                          onImageTap: _onAddMangoAtPoint,
                          onImageLongPress: _onAddMangoAtPoint,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Botanical Console Sheet
          _buildBotanicalConsoleSheet(
            overRipe: overRipeCount,
            ripe: ripeCount,
            unripe: unripeCount,
            total: totalCount,
            aiVerifiedCount: aiVerifiedCount,
            inferMs: state.result?.inferenceTimeMs ?? 0,
            surface: surface,
            text: text,
            muted: muted,
            primary: primary,
            amber: amber,
            isDark: isDark,
          ),
        ],
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
                      backgroundColor: primary,
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

  String _buildAiStatusLine(int total, int ripe, int unripe, int overRipe) {
    final parts = <String>[
      '$total verified: $ripe ripe, $unripe unripe, $overRipe over-ripe',
    ];
    if (_aiNeedsReviewCount > 0) {
      parts.add('$_aiNeedsReviewCount need review (?)');
    }
    if (_aiRemovedCount > 0) {
      parts.add(
          '$_aiRemovedCount non-mango${_aiRemovedCount == 1 ? '' : 'es'} filtered');
    }
    return parts.join(' · ');
  }

  Widget _buildBotanicalConsoleSheet({
    required int overRipe,
    required int ripe,
    required int unripe,
    required int total,
    required int aiVerifiedCount,
    required int inferMs,
    required Color surface,
    required Color text,
    required Color muted,
    required Color primary,
    required Color amber,
    required bool isDark,
  }) {
    int actualCount = int.tryParse(_actualCountCtrl.text) ?? 0;
    double? err;
    if (actualCount > 0) {
      err = ((total - actualCount).abs() / actualCount) * 100;
    }

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppShapes.consoleSheet,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkOutline : const Color(0x261F5D3F),
            width: 1.5,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Console Grab Handle
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: muted.withOpacity(0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Count Gauge & Details
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Large Total Count Dial
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF101B14)
                      : const Color(0xFFEBF6EE),
                  borderRadius: AppShapes.leafCut,
                  border: Border.all(
                    color: primary.withOpacity(0.3),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '$total',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: text,
                        letterSpacing: -1.0,
                        height: 1.05,
                        fontFamilyFallback: const ['Georgia', 'serif'],
                      ),
                    ),
                    Text(
                      'TOTAL MANGOES',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              // Segmented Ripeness Pills Breakdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildRipenessBadge(
                          label: 'Ripe: $ripe',
                          color: amber,
                          icon: Icons.wb_sunny_rounded,
                        ),
                        const SizedBox(width: 6),
                        _buildRipenessBadge(
                          label: 'Unripe: $unripe',
                          color: AppColors.unripeGreen,
                          icon: Icons.eco_rounded,
                        ),
                        const SizedBox(width: 6),
                        _buildRipenessBadge(
                          label: 'Over: $overRipe',
                          color: AppColors.overRipeEarth,
                          icon: Icons.grain_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Speed: ${inferMs}ms',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                        if (aiVerifiedCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.12),
                              borderRadius: AppShapes.pill,
                              border: Border.all(
                                  color: Colors.purple.withOpacity(0.3)),
                            ),
                            child: Text(
                              '✨ $aiVerifiedCount AI Checked',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.purple.shade200
                                    : Colors.purple.shade800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // AI Ripeness Status Box
          if (_aiCompleted) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF22162B) : const Color(0xFFF7F1FC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.purple.withOpacity(0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: Colors.purple, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_lastAiProvider != null)
                          Text(
                            'AI Fruit Check (${_lastAiProvider!})',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple,
                            ),
                          ),
                        Text(
                          _buildAiStatusLine(total, ripe, unripe, overRipe),
                          style: TextStyle(fontSize: 11, color: text),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          // AI Harvest Assistant Card & Follow-up Questions
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF14241B), Color(0xFF172B20)])
                  : const LinearGradient(
                      colors: [Color(0xFFEBF6EE), Color(0xFFF3FAF5)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: primary.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology_alt_rounded,
                        color: primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'AI HARVEST ASSISTANT',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: primary,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => _openChat(),
                      child: Row(
                        children: [
                          Text(
                            'Open Chat',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: primary),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded,
                              size: 10, color: primary),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildFollowUpChip(
                      label: 'When to harvest?',
                      question:
                          'Based on this tree scan with $total mangoes ($ripe ripe, $unripe green), when should I pick them?',
                      primary: primary,
                      surface: surface,
                      text: text,
                    ),
                    _buildFollowUpChip(
                      label: 'Ripening forecast',
                      question:
                          'How long will it take for the $unripe unripe mangoes to mature on the tree?',
                      primary: primary,
                      surface: surface,
                      text: text,
                    ),
                    _buildFollowUpChip(
                      label: 'Pest & disease check',
                      question:
                          'What are the main pest and fruit fly risks for this fruit batch and how to prevent them?',
                      primary: primary,
                      surface: surface,
                      text: text,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Actual Hand Count Input
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _actualCountCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(fontSize: 13, color: text),
                    decoration: InputDecoration(
                      hintText: 'Actual hand count (optional)',
                      hintStyle: TextStyle(fontSize: 12, color: muted),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      prefixIcon:
                          Icon(Icons.pin_outlined, size: 16, color: muted),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (val) {
                      final count = int.tryParse(val);
                      if (count != null && count > 0) {
                        final curState = ref.read(detectionControllerProvider);
                        final yoloCount =
                            curState.result?.detections.length ?? 0;
                        final finalCount = _filteredDetections.length;
                        final imageId = widget.originalPath
                            .split(Platform.pathSeparator)
                            .last;
                        _appendEvaluationLog(
                          imageId: imageId,
                          yoloCount: yoloCount,
                          finalCount: finalCount,
                          actualCount: count,
                          usedGemini: _aiCompleted,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Saved actual count 📊'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
              if (actualCount > 0) ...[
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (total == actualCount)
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Δ: ${(total - actualCount).abs()} (${err?.toStringAsFixed(1)}%)',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: (total == actualCount)
                          ? Colors.green.shade900
                          : Colors.deepOrange.shade900,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Sensitivity Slider (expandable)
          if (_showConfSlider || !_isAutoConfidence) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Sensitivity: ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: muted,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _confThreshold.clamp(0.05, 0.50),
                    min: 0.05,
                    max: 0.50,
                    divisions: 18,
                    label: '${(_confThreshold * 100).toStringAsFixed(0)}%',
                    onChanged: (val) {
                      setState(() {
                        _isAutoConfidence = false;
                        _confThreshold = val;
                        _updateFiltered(manualConf: val);
                      });
                    },
                  ),
                ),
                Text(
                  '${(_confThreshold * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: text,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),

          // Calibration & Labels Quick Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Auto Confidence Calibration Pill
              FilterChip(
                avatar: Icon(
                  _isAutoConfidence ? Icons.auto_awesome : Icons.tune,
                  size: 14,
                  color: _isAutoConfidence ? amber : muted,
                ),
                label: Text(
                  _isAutoConfidence
                      ? 'Auto (${(_confThreshold * 100).toStringAsFixed(0)}%)'
                      : 'Manual (${(_confThreshold * 100).toStringAsFixed(0)}%)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _isAutoConfidence ? amber : text,
                  ),
                ),
                selected: _isAutoConfidence,
                selectedColor: amber.withOpacity(0.15),
                onSelected: (selected) {
                  setState(() {
                    _isAutoConfidence = selected;
                    _showConfSlider = !selected;
                    _updateFiltered();
                  });
                },
              ),

              // Labels Switch
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Labels',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: text),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: _showLabels,
                    activeColor: primary,
                    onChanged: (v) {
                      setState(() => _showLabels = v);
                      ref.read(settingsProvider.notifier).updateShowLabels(v);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRipenessBadge({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: AppShapes.pill,
        border: Border.all(color: color.withOpacity(0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowUpChip({
    required String label,
    required String question,
    required Color primary,
    required Color surface,
    required Color text,
  }) {
    return ActionChip(
      avatar: Icon(Icons.chat_bubble_outline_rounded, size: 11, color: primary),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: primary.withOpacity(0.35)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: () => _openChat(question),
    );
  }
}
