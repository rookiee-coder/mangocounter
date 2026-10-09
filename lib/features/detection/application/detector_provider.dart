import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/demo_detector.dart';
import '../data/tflite_detector.dart';
import '../domain/detector.dart';

final isDemoModeProvider = StateProvider<bool>((ref) => false);

final detectorProvider = FutureProvider<Detector>((ref) async {
  final tflite = TfliteDetector();
  try {
    await tflite.init();
    ref.read(isDemoModeProvider.notifier).state = false;
    return tflite;
  } catch (e) {
    // Fallback to demo
    ref.read(isDemoModeProvider.notifier).state = true;
    final demo = DemoDetector();
    await demo.init();
    return demo;
  }
});
