import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../detection/application/detector_provider.dart';
import '../domain/video_scan_result.dart';
import '../data/video_scanner_service.dart';

import '../data/tree_canopy_validator.dart';

class VideoScanState {
  final bool isScanning;
  final double progress;
  final String statusMessage;
  final VideoScanResult? result;
  final String? errorMessage;
  final bool isNonTreeVideo;
  final String? nonTreeReason;
  final String? detectedSubject;

  const VideoScanState({
    this.isScanning = false,
    this.progress = 0.0,
    this.statusMessage = '',
    this.result,
    this.errorMessage,
    this.isNonTreeVideo = false,
    this.nonTreeReason,
    this.detectedSubject,
  });

  VideoScanState copyWith({
    bool? isScanning,
    double? progress,
    String? statusMessage,
    VideoScanResult? result,
    String? errorMessage,
    bool? isNonTreeVideo,
    String? nonTreeReason,
    String? detectedSubject,
  }) {
    return VideoScanState(
      isScanning: isScanning ?? this.isScanning,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      result: result ?? this.result,
      errorMessage: errorMessage,
      isNonTreeVideo: isNonTreeVideo ?? this.isNonTreeVideo,
      nonTreeReason: nonTreeReason ?? this.nonTreeReason,
      detectedSubject: detectedSubject ?? this.detectedSubject,
    );
  }
}

class VideoScanController extends StateNotifier<VideoScanState> {
  final Ref ref;

  VideoScanController(this.ref) : super(const VideoScanState());

  Future<VideoScanResult?> scanVideo(String videoPath, {String? apiKey}) async {
    final detectorAsync = ref.read(detectorProvider);
    final detector = detectorAsync.value;

    if (detector == null) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: 'Scanner is still preparing, please try again in a moment.',
        isNonTreeVideo: false,
      );
      return null;
    }

    state = const VideoScanState(
      isScanning: true,
      progress: 0.04,
      statusMessage: 'Preparing video scan...',
    );

    try {
      final service = VideoScannerService(detector);
      final result = await service.processVideo(
        videoPath: videoPath,
        apiKey: apiKey,
        onProgress: (progress, status) {
          state = state.copyWith(
            progress: progress,
            statusMessage: status,
          );
        },
      );

      state = state.copyWith(
        isScanning: false,
        progress: 1.0,
        result: result,
        isNonTreeVideo: false,
      );

      return result;
    } on InvalidTreeVideoException catch (e) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: e.reason,
        isNonTreeVideo: true,
        nonTreeReason: e.reason,
        detectedSubject: e.detectedSubject,
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: e.toString(),
        isNonTreeVideo: false,
      );
      return null;
    }
  }

  void reset() {
    state = const VideoScanState();
  }
}

final videoScanControllerProvider =
    StateNotifierProvider<VideoScanController, VideoScanState>((ref) {
  return VideoScanController(ref);
});
