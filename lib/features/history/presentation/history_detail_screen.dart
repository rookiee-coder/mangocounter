import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../detection/presentation/widgets/detection_overlay.dart';
import '../domain/scan_record.dart';
import '../application/history_controller.dart';

class HistoryDetailScreen extends ConsumerWidget {
  final ScanRecord scan;

  const HistoryDetailScreen({super.key, required this.scan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('MMM d, yyyy · h:mm a');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primary = isDark ? AppColors.darkPrimaryMint : AppColors.primaryGreen;
    final amber = isDark ? AppColors.darkRipeAmber : AppColors.ripeAmber;
    final surface = isDark ? AppColors.darkSurface : AppColors.surfaceWhite;
    final text = isDark ? AppColors.darkTextParchment : AppColors.charcoalText;
    final muted = isDark ? AppColors.darkMutedMist : AppColors.mutedGraphite;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete Record',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Confirm Deletion'),
                  content: const Text('Delete this harvest scan from your history?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorCrimson),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                ref.read(historyProvider.notifier).deleteScan(scan.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Center(
                child: Stack(
                  children: [
                    if (scan.imagePath.isNotEmpty && File(scan.imagePath).existsSync())
                      Image.file(File(scan.imagePath), fit: BoxFit.contain)
                    else
                      const Center(child: Text('Image file not found on device')),

                    Positioned.fill(
                      child: DetectionOverlay(
                        detections: scan.detections,
                        imageWidth: scan.imageWidth,
                        imageHeight: scan.imageHeight,
                        showLabels: true,
                        showBoxes: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: AppShapes.consoleSheet,
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.darkOutline : const Color(0x261F5D3F),
                  width: 1.5,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: muted.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF101B14) : const Color(0xFFEBF6EE),
                        borderRadius: AppShapes.leafCut,
                        border: Border.all(color: primary.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${scan.currentTotal}',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: text,
                              letterSpacing: -1.0,
                              fontFamilyFallback: const ['Georgia', 'serif'],
                            ),
                          ),
                          Text(
                            'TOTAL MANGOES',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            df.format(DateTime.fromMillisecondsSinceEpoch(scan.createdAt)),
                            style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: muted),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _buildPill('Ripe: ${scan.currentRipe}', amber),
                              const SizedBox(width: 6),
                              _buildPill('Unripe: ${scan.currentUnripe}', AppColors.unripeGreen),
                              const SizedBox(width: 6),
                              _buildPill('Over: ${scan.currentOverRipe}', AppColors.overRipeEarth),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (scan.actualCount != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Actual Hand Count: ${scan.actualCount} · Difference: ${(scan.currentTotal - scan.actualCount!).abs()}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sensitivity: ${(scan.confThreshold * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: muted),
                    ),
                    Text(
                      'Speed: ${scan.inferenceMs}ms',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: AppShapes.pill,
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
