import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangocounter/features/detection/domain/detector.dart';
import 'package:mangocounter/features/detection/domain/detection_result.dart';
import 'package:mangocounter/features/video_scan/data/video_scanner_service.dart';
import 'package:mangocounter/features/video_scan/data/tree_canopy_validator.dart';

class _Detector implements Detector {
  bool fail = false;
  double? confidence;
  bool? tiling;
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
  @override
  Future<DetectionResult> detect(Uint8List bytes,
      {double confThreshold = 0.4,
      double iouThreshold = 0.45,
      bool enableTiling = true}) async {
    if (fail) throw StateError('inference failed');
    confidence = confThreshold;
    tiling = enableTiling;
    return DetectionResult(
        detections: [],
        imageWidth: 1280,
        imageHeight: 720,
        inferenceTimeMs: 10,
        preprocessTimeMs: 1,
        postprocessTimeMs: 1,
        confThreshold: confThreshold,
        iouThreshold: iouThreshold,
        modelInputSize: 640);
  }
}

class _Canopy extends TreeCanopyValidator {
  @override
  Future<CanopyValidationResult> validateCanopy(Uint8List bytes,
          {String apiKey = ''}) async =>
      const CanopyValidationResult(
          isMangoTree: false,
          isOnline: false,
          detectedSubject: 'Low foliage',
          reason: 'Shaded canopy');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const metadata = MethodChannel('mangocounter/video');
  const thumbnails = MethodChannel('plugins.justsoft.xyz/video_thumbnail');
  late Directory temporary;
  late File video;
  final times = <int>[];
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('mango_video_test_');
    video = await File('${temporary.path}/test.mp4').writeAsBytes([0]);
    times.clear();
    messenger.setMockMethodCallHandler(metadata, (_) async => 20000);
    messenger.setMockMethodCallHandler(thumbnails, (call) async {
      times.add(call.arguments['timeMs'] as int);
      expect(call.arguments['maxw'], 1280);
      return Uint8List.fromList([1, 2, 3]);
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(metadata, null);
    messenger.setMockMethodCallHandler(thumbnails, null);
    await video.delete();
    await temporary.delete();
  });
  test('full clip is sampled and low foliage does not veto a scan', () async {
    final detector = _Detector();
    final result =
        await VideoScannerService(detector, canopyValidator: _Canopy())
            .processVideo(
                videoPath: video.path, confThreshold: 0.3, enableTiling: false);
    expect(times.last, 19999);
    expect(times.where((t) => t == 0), hasLength(1));
    expect(result.durationMs, 20000);
    expect(result.inferenceTimeMs, result.frames.length * 10);
    expect(result.confThreshold, 0.3);
    expect(detector.confidence, 0.3);
    expect(detector.tiling, isFalse);
  });
  test('inference failure cannot return a successful zero-fruit scan',
      () async {
    final detector = _Detector()..fail = true;
    await expectLater(
        VideoScannerService(detector, canopyValidator: _Canopy())
            .processVideo(videoPath: video.path),
        throwsStateError);
  });
  test('a missing middle frame cannot silently truncate the scan', () async {
    messenger.setMockMethodCallHandler(
        thumbnails,
        (call) async => call.arguments['timeMs'] == 0
            ? Uint8List.fromList([1])
            : Uint8List(0));
    await expectLater(
        VideoScannerService(_Detector(), canopyValidator: _Canopy())
            .processVideo(videoPath: video.path),
        throwsStateError);
  });
}
