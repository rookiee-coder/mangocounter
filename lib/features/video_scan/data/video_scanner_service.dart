import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:get_thumbnail_video/index.dart';

import '../../detection/domain/detector.dart';
import '../../detection/domain/detection.dart';
import '../domain/video_frame_data.dart';
import '../domain/video_scan_result.dart';
import 'tree_tracker.dart';
import 'tree_canopy_validator.dart';
import 'video_sampling.dart';

class VideoScannerService {
  final Detector detector;
  final TreeCanopyValidator canopyValidator;

  const VideoScannerService(
    this.detector, {
    this.canopyValidator = const TreeCanopyValidator(),
  });

  /// Scans a recorded whole-tree video file, extracts keyframes, runs YOLO detection,
  /// tracks unique mango trajectories, and eliminates duplicate counts and false positives.
  Future<VideoScanResult> processVideo({
    required String videoPath,
    String? apiKey,
    double confThreshold = 0.18,
    double iouThreshold = 0.45,
    bool enableTiling = true,
    int samplingIntervalMs =
        650, // ~1.5 FPS (optimal balance of overlap and speed)
    int maxKeyframes = 32,
    void Function(double progress, String status)? onProgress,
  }) async {
    final file = File(videoPath);
    if (!await file.exists()) {
      throw Exception('Video file not found at: $videoPath');
    }
    final durationMs = await VideoSampling.durationMs(videoPath);
    if (durationMs > 30000) {
      throw ArgumentError(
          'Choose a video of 30 seconds or less and pan slowly across one side of the tree.');
    }
    final timestamps =
        VideoSampling.timestamps(durationMs, samplingIntervalMs, maxKeyframes);

    onProgress?.call(0.04, 'Extracting initial video keyframe...');

    // Extract Frame 0 for pre-inspection
    Uint8List? firstFrameBytes;
    try {
      firstFrameBytes = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: 0,
        maxWidth: 1280,
        quality: 90,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VideoScanner] Frame extraction error at 0 ms: $e');
      }
    }

    if (firstFrameBytes == null || firstFrameBytes.isEmpty) {
      throw Exception('Unable to read video frames from: $videoPath');
    }

    // Canopy Gatekeeper: Fast early check to prevent wasting time on non-tree / nonsense videos
    onProgress?.call(0.08, 'Checking if video shows a mango tree...');
    final canopyVerdict = await canopyValidator.validateCanopy(
      firstFrameBytes,
      apiKey: apiKey ?? '',
    );

    if (kDebugMode) {
      debugPrint('[VideoScanner] Canopy Check: $canopyVerdict');
    }

    if (!canopyVerdict.isMangoTree &&
        canopyVerdict.isOnline &&
        canopyVerdict.confidence >= 0.9) {
      // Abort immediately! Save 10–20 seconds of multi-frame YOLO inference
      throw InvalidTreeVideoException(
        reason: canopyVerdict.reason,
        detectedSubject: canopyVerdict.detectedSubject,
        isOnline: canopyVerdict.isOnline,
      );
    }

    onProgress?.call(0.12, 'Starting visible mango estimate...');

    final tracker = TreeTracker(
      iouThreshold: 0.22,
      maxConsecutiveMisses: 3,
      minHitsToConfirm: 2,
    );

    final List<VideoFrameData> processedFrames = [];
    int totalRawDetections = 0;
    int inferenceTimeMs = 0;

    int currentFrameIndex = 0;

    for (final timeMs in timestamps) {
      final double progressRatio =
          0.12 + (currentFrameIndex / timestamps.length) * 0.80;
      onProgress?.call(
        progressRatio,
        'Finding mangoes in video (${(timeMs / 1000).toStringAsFixed(1)}s)...',
      );

      Uint8List? frameBytes;
      if (timeMs == 0) {
        // Reuse pre-extracted first frame
        frameBytes = firstFrameBytes;
      } else {
        try {
          frameBytes = await VideoThumbnail.thumbnailData(
            video: videoPath,
            imageFormat: ImageFormat.JPEG,
            timeMs: timeMs,
            maxWidth: 1280,
            quality: 90,
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                '[VideoScanner] Frame extraction error at $timeMs ms: $e');
          }
          throw StateError(
              'Could not read video frame at $timeMs ms. Try recording again.');
        }
      }

      if (frameBytes.isEmpty) {
        throw StateError('Empty video frame at $timeMs ms');
      }

      int imageWidth = 0;
      int imageHeight = 0;

      // Run YOLO TFLite inference
      List<Detection> rawDetections = [];
      try {
        final detResult = await detector.detect(
          frameBytes,
          confThreshold: confThreshold,
          iouThreshold: iouThreshold,
          enableTiling: enableTiling,
        );
        rawDetections = detResult.detections;
        inferenceTimeMs += detResult.inferenceTimeMs;
        imageWidth = detResult.imageWidth;
        imageHeight = detResult.imageHeight;
      } catch (e) {
        if (kDebugMode) debugPrint('[VideoScanner] YOLO inference error: $e');
        throw StateError(
            'Mango detection failed at $timeMs ms. Please retry the scan.');
      }

      totalRawDetections += rawDetections.length;

      // Update tracker and get annotated detections
      final trackedDetections = tracker.updateFrame(
        rawDetections: rawDetections,
        frameIndex: currentFrameIndex,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );

      processedFrames.add(
        VideoFrameData(
          frameIndex: currentFrameIndex,
          timestampMs: timeMs,
          imageBytes: frameBytes,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          detections: trackedDetections,
        ),
      );

      currentFrameIndex++;
    }

    onProgress?.call(
        0.95, 'Combining observations into a visible fruit estimate...');

    // Finalize all tracks
    final confirmedTracks = tracker.finalize(
      totalFramesProcessed: processedFrames.length,
    );

    onProgress?.call(1.0, 'Counting complete!');

    return VideoScanResult.fromTracks(
      videoPath: videoPath,
      frames: processedFrames,
      trackedMangoes: confirmedTracks,
      durationMs: durationMs,
      totalRawDetections: totalRawDetections,
      confThreshold: confThreshold,
      iouThreshold: iouThreshold,
      inferenceTimeMs: inferenceTimeMs,
    );
  }
}
