import 'dart:typed_data';
import '../../detection/domain/detection.dart';

class VideoFrameData {
  final int frameIndex;
  final int timestampMs;
  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final List<Detection> detections;

  const VideoFrameData({
    required this.frameIndex,
    required this.timestampMs,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.detections,
  });
}
