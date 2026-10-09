import 'dart:math';
import 'package:flutter/services.dart';

class VideoSampling {
  static Future<int> durationMs(String path) async {
    final duration = await const MethodChannel('mangocounter/video')
        .invokeMethod<int>('durationMs', {'path': path});
    if (duration == null || duration <= 0) {
      throw StateError('Unable to read video duration');
    }
    return duration;
  }

  /// Includes both ends of the clip, never requesting a frame past its end.
  static List<int> timestamps(int durationMs, int intervalMs, int maxFrames) {
    if (durationMs <= 0 || intervalMs <= 0 || maxFrames < 2) {
      throw ArgumentError('Invalid video sampling parameters');
    }
    final count = min(maxFrames, max(2, (durationMs / intervalMs).ceil() + 1));
    return List.generate(
            count, (i) => ((durationMs - 1) * i / (count - 1)).round())
        .toSet()
        .toList();
  }
}
