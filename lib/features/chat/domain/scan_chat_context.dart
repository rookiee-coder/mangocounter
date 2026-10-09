import 'dart:typed_data';

class ScanChatContext {
  final Uint8List? imageBytes;
  final String originalPath;
  final int totalCount;
  final int ripeCount;
  final int unripeCount;
  final int overRipeCount;
  final int inferenceMs;
  final double confThreshold;
  final int aiVerifiedCount;
  final int userEditedCount;
  final int? actualCount;

  const ScanChatContext({
    this.imageBytes,
    this.originalPath = '',
    required this.totalCount,
    required this.ripeCount,
    required this.unripeCount,
    required this.overRipeCount,
    this.inferenceMs = 0,
    this.confThreshold = 0.20,
    this.aiVerifiedCount = 0,
    this.userEditedCount = 0,
    this.actualCount,
  });

  String toSummaryPrompt() {
    final buffer = StringBuffer();
    buffer.writeln('CANOPY SCAN TELEMETRY SUMMARY:');
    buffer.writeln('• Total visible mangoes detected: $totalCount');
    buffer.writeln('• Ripeness distribution:');
    buffer.writeln('  - Ripe (Harvest ready): $ripeCount');
    buffer.writeln('  - Unripe (Developing green): $unripeCount');
    buffer.writeln('  - Over-ripe (Late stage): $overRipeCount');
    if (aiVerifiedCount > 0) {
      buffer.writeln('• AI Verified fruits: $aiVerifiedCount');
    }
    if (userEditedCount > 0) {
      buffer.writeln('• Field user manually placed boxes: $userEditedCount');
    }
    if (actualCount != null && actualCount! > 0) {
      final diff = (totalCount - actualCount!).abs();
      buffer.writeln('• Ground truth manual count: $actualCount (variance: $diff)');
    }
    buffer.writeln('• Optical detection confidence: ${(confThreshold * 100).toStringAsFixed(0)}%');
    buffer.writeln('• Model inference time: ${inferenceMs}ms');
    return buffer.toString();
  }
}
