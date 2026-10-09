import 'dart:math';
import '../../detection/domain/detection.dart';
import '../../detection/domain/mango_class.dart';
import '../domain/tracked_mango.dart';

class _ActiveTrack {
  final int trackId;
  Detection currentBox;
  double highestConfidence;
  final Map<MangoClass, int> classVotes;
  int hitCount;
  int consecutiveMisses;
  final int firstFrameIndex;
  int lastFrameIndex;
  Detection bestDetection;
  int bestFrameIndex;

  _ActiveTrack({
    required this.trackId,
    required this.currentBox,
    required this.firstFrameIndex,
    required this.lastFrameIndex,
  })  : highestConfidence = currentBox.confidence,
        classVotes = {currentBox.mangoClass: 1},
        hitCount = 1,
        consecutiveMisses = 0,
        bestDetection = currentBox,
        bestFrameIndex = firstFrameIndex;

  MangoClass get dominantClass {
    MangoClass bestClass = currentBox.mangoClass;
    int maxVotes = -1;
    classVotes.forEach((cls, votes) {
      if (votes > maxVotes) {
        maxVotes = votes;
        bestClass = cls;
      }
    });
    return bestClass;
  }
}

class TreeTracker {
  final double iouThreshold;
  final int maxConsecutiveMisses;
  final int minHitsToConfirm;

  int _nextTrackId = 1;
  final List<_ActiveTrack> _activeTracks = [];
  final List<TrackedMango> _confirmedTracks = [];

  TreeTracker({
    this.iouThreshold = 0.22,
    this.maxConsecutiveMisses = 3,
    this.minHitsToConfirm = 2,
  });

  /// Evaluates whether a raw detection has typical mango geometry,
  /// filtering out human hands, long branches, and flat leaves.
  static bool isValidMangoGeometry(
    Detection det,
    int imageWidth,
    int imageHeight,
  ) {
    if (![det.x1, det.y1, det.x2, det.y2, det.confidence]
        .every((value) => value.isFinite)) return false;
    final double width = det.x2 - det.x1;
    final double height = det.y2 - det.y1;

    if (width <= 0 || height <= 0) return false;

    // Aspect ratio filter: Mangoes are roughly spherical/ellipsoid (0.45 <= width/height <= 2.2)
    final double aspect = width / height;
    if (aspect < 0.45 || aspect > 2.2) {
      return false; // Hands, flat leaves, long branches
    }

    // Relative area check
    final double boxArea = width * height;
    final double frameArea = (imageWidth * imageHeight).toDouble();
    if (frameArea > 0) {
      final double areaRatio = boxArea / frameArea;
      if (areaRatio > 0.65 || width < 2 || height < 2) {
        return false; // Extreme oversized artifacts or tiny sub-pixel noise
      }
    }

    // Bottom edge ground clutter filter
    if (imageHeight > 0 && det.y1 > imageHeight * 0.92 && aspect > 1.6) {
      return false; // Ground rocks/fallen debris
    }

    return true;
  }

  /// Calculates Intersection over Union (IoU) between two bounding boxes.
  static double computeIoU(Detection a, Detection b) {
    final double xA = max(a.x1, b.x1);
    final double yA = max(a.y1, b.y1);
    final double xB = min(a.x2, b.x2);
    final double yB = min(a.y2, b.y2);

    final double interWidth = max(0.0, xB - xA);
    final double interHeight = max(0.0, yB - yA);
    final double interArea = interWidth * interHeight;

    if (interArea <= 0) return 0.0;

    final double areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
    final double areaB = (b.x2 - b.x1) * (b.y2 - b.y1);
    final double unionArea = areaA + areaB - interArea;

    if (unionArea <= 0) return 0.0;
    return interArea / unionArea;
  }

  /// Processes detections for a new keyframe and updates active tracks.
  /// Returns a list of detections annotated with persistent track IDs.
  List<Detection> updateFrame({
    required List<Detection> rawDetections,
    required int frameIndex,
    required int imageWidth,
    required int imageHeight,
  }) {
    // 1. Filter out obvious non-mango geometries (hands, long sticks, flat leaves)
    final List<Detection> validDetections = rawDetections.where((d) {
      return isValidMangoGeometry(d, imageWidth, imageHeight);
    }).toList();

    final List<Detection> trackedFrameDetections = [];
    final Set<int> matchedTrackIndices = {};
    final Set<int> matchedDetectionIndices = {};

    // 2. Greedy IoU matching with existing active tracks
    // Build candidate match pairs sorted by descending IoU
    final List<({int trackIdx, int detIdx, double iou})> matches = [];

    for (int t = 0; t < _activeTracks.length; t++) {
      for (int d = 0; d < validDetections.length; d++) {
        final iou = computeIoU(_activeTracks[t].currentBox, validDetections[d]);
        if (iou >= iouThreshold) {
          matches.add((trackIdx: t, detIdx: d, iou: iou));
        }
      }
    }

    matches.sort((a, b) => b.iou.compareTo(a.iou));

    for (final m in matches) {
      if (matchedTrackIndices.contains(m.trackIdx) ||
          matchedDetectionIndices.contains(m.detIdx)) {
        continue;
      }

      matchedTrackIndices.add(m.trackIdx);
      matchedDetectionIndices.add(m.detIdx);

      final track = _activeTracks[m.trackIdx];
      final det = validDetections[m.detIdx];

      // Update track
      track.currentBox = det;
      track.lastFrameIndex = frameIndex;
      track.hitCount++;
      track.consecutiveMisses = 0;
      track.classVotes[det.mangoClass] =
          (track.classVotes[det.mangoClass] ?? 0) + 1;

      if (det.confidence > track.highestConfidence) {
        track.highestConfidence = det.confidence;
        track.bestDetection = det;
        track.bestFrameIndex = frameIndex;
      }

      // Add detection labeled with track ID
      trackedFrameDetections.add(
        det.copyWith(
          // Use trackId as user note or class annotation
          mangoClass: track.dominantClass,
        ),
      );
    }

    // 3. Initiate new tracks for unmatched detections
    for (int d = 0; d < validDetections.length; d++) {
      if (!matchedDetectionIndices.contains(d)) {
        final det = validDetections[d];
        final newTrack = _ActiveTrack(
          trackId: _nextTrackId++,
          currentBox: det,
          firstFrameIndex: frameIndex,
          lastFrameIndex: frameIndex,
        );
        _activeTracks.add(newTrack);
        // A track observed in this frame has not missed this frame.
        matchedTrackIndices.add(_activeTracks.length - 1);

        trackedFrameDetections.add(det);
      }
    }

    // 4. Age and retire inactive tracks
    final List<_ActiveTrack> remainingActive = [];

    for (int t = 0; t < _activeTracks.length; t++) {
      if (!matchedTrackIndices.contains(t)) {
        final track = _activeTracks[t];
        track.consecutiveMisses++;

        if (track.consecutiveMisses > maxConsecutiveMisses) {
          // Retire track: confirm if it met the minimum hit threshold
          if (track.hitCount >= minHitsToConfirm) {
            _confirmedTracks.add(
              TrackedMango(
                trackId: track.trackId,
                mangoClass: track.dominantClass,
                confidence: track.highestConfidence,
                hitCount: track.hitCount,
                firstFrameIndex: track.firstFrameIndex,
                lastFrameIndex: track.lastFrameIndex,
                bestDetection: track.bestDetection,
                bestFrameIndex: track.bestFrameIndex,
              ),
            );
          }
          continue; // Don't keep in active tracks
        }
      }
      remainingActive.add(_activeTracks[t]);
    }

    _activeTracks.clear();
    _activeTracks.addAll(remainingActive);

    return trackedFrameDetections;
  }

  /// Finalizes tracking at video completion and returns the deduplicated list of confirmed mangoes.
  List<TrackedMango> finalize({int totalFramesProcessed = 1}) {
    // Confirm any remaining active tracks that meet threshold
    final effectiveMinHits = totalFramesProcessed <= 2 ? 1 : minHitsToConfirm;

    for (final track in _activeTracks) {
      if (track.hitCount >= effectiveMinHits) {
        // Prevent duplicate IDs
        final alreadyAdded =
            _confirmedTracks.any((t) => t.trackId == track.trackId);
        if (!alreadyAdded) {
          _confirmedTracks.add(
            TrackedMango(
              trackId: track.trackId,
              mangoClass: track.dominantClass,
              confidence: track.highestConfidence,
              hitCount: track.hitCount,
              firstFrameIndex: track.firstFrameIndex,
              lastFrameIndex: track.lastFrameIndex,
              bestDetection: track.bestDetection,
              bestFrameIndex: track.bestFrameIndex,
            ),
          );
        }
      }
    }
    _activeTracks.clear();

    return List<TrackedMango>.from(_confirmedTracks);
  }
}
