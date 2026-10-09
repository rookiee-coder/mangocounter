import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/detection_result.dart';
import 'detector_provider.dart';
import '../../settings/application/settings_controller.dart';

class DetectionState {
  final bool isProcessing;
  final DetectionResult? result;
  final String? error;

  DetectionState({
    this.isProcessing = false,
    this.result,
    this.error,
  });
}

class DetectionController extends StateNotifier<DetectionState> {
  final Ref ref;
  int _requestId = 0;

  DetectionController(this.ref) : super(DetectionState());

  Future<void> processImage(Uint8List imageBytes) async {
    final requestId = ++_requestId;
    state = DetectionState(isProcessing: true);
    try {
      final detector = await ref.read(detectorProvider.future);
      if (!mounted || requestId != _requestId) return;
      final settings = ref.read(settingsProvider);

      final result = await detector.detect(
        imageBytes,
        confThreshold: 0.05,
        iouThreshold: settings.iouThreshold,
        enableTiling: settings.tiledInference,
      );

      if (mounted && requestId == _requestId) {
        state = DetectionState(isProcessing: false, result: result);
      }
    } catch (e) {
      if (mounted && requestId == _requestId) {
        state = DetectionState(isProcessing: false, error: e.toString());
      }
    }
  }

  void reset() {
    _requestId++;
    state = DetectionState();
  }
}

final detectionControllerProvider =
    StateNotifierProvider<DetectionController, DetectionState>((ref) {
  return DetectionController(ref);
});
