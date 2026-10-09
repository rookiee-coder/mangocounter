import 'tracked_mango.dart';
import 'video_frame_data.dart';
import '../../detection/domain/mango_class.dart';

class VideoScanResult {
  final String videoPath;
  final int totalUniqueCount;
  final int ripeCount;
  final int unripeCount;
  final int overRipeCount;
  final List<VideoFrameData> frames;
  final List<TrackedMango> trackedMangoes;
  final int durationMs;
  final int processedFramesCount;
  final int totalRawDetections;

  const VideoScanResult({
    required this.videoPath,
    required this.totalUniqueCount,
    required this.ripeCount,
    required this.unripeCount,
    required this.overRipeCount,
    required this.frames,
    required this.trackedMangoes,
    required this.durationMs,
    required this.processedFramesCount,
    required this.totalRawDetections,
  });

  int get duplicateDetectionsFiltered =>
      (totalRawDetections - totalUniqueCount).clamp(0, 99999);

  factory VideoScanResult.fromTracks({
    required String videoPath,
    required List<VideoFrameData> frames,
    required List<TrackedMango> trackedMangoes,
    required int durationMs,
    required int totalRawDetections,
  }) {
    int ripe = 0;
    int unripe = 0;
    int overRipe = 0;

    for (final mango in trackedMangoes) {
      switch (mango.mangoClass) {
        case MangoClass.ripe:
          ripe++;
          break;
        case MangoClass.unripe:
          unripe++;
          break;
        case MangoClass.over_ripe:
          overRipe++;
          break;
      }
    }

    return VideoScanResult(
      videoPath: videoPath,
      totalUniqueCount: trackedMangoes.length,
      ripeCount: ripe,
      unripeCount: unripe,
      overRipeCount: overRipe,
      frames: frames,
      trackedMangoes: trackedMangoes,
      durationMs: durationMs,
      processedFramesCount: frames.length,
      totalRawDetections: totalRawDetections,
    );
  }
}
