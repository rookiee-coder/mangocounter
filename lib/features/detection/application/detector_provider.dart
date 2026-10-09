import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/tflite_detector.dart';
import '../domain/detector.dart';

final isDemoModeProvider = StateProvider<bool>((ref) => false);

final detectorProvider = FutureProvider<Detector>((ref) async {
  final tflite = TfliteDetector();
  ref.onDispose(tflite.dispose);
  try {
    await tflite.init();
    ref.read(isDemoModeProvider.notifier).state = false;
    return tflite;
  } catch (e) {
    tflite.dispose();
    // Never substitute fabricated fruit counts for a failed production model.
    rethrow;
  }
});
