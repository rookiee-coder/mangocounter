import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../application/history_controller.dart';
import 'history_detail_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final state = ref.read(historyProvider);
    if (!state.hasValue || state.value!.isEmpty) return;

    final scans = state.value!;

    List<List<dynamic>> rows = [];
    rows.add([
      "id", "timestamp", "image_path", "image_width", "image_height",
      "model_count", "over_ripe_count", "ripe_count", "unripe_count",
      "edited_over_ripe_count", "edited_ripe_count", "edited_unripe_count", "edited_total",
      "actual_count", "abs_error", "pct_error",
      "conf_threshold", "iou_threshold", "inference_ms", "is_demo"
    ]);

    for (var s in scans) {
      int modelCount = s.modelHalfRipe + s.modelRipe + s.modelUnripe;
      int editedTotal = (s.editedHalfRipe ?? s.modelHalfRipe) +
          (s.editedRipe ?? s.modelRipe) +
          (s.editedUnripe ?? s.modelUnripe);

      double absError = 0;
      double pctError = 0;
      if (s.actualCount != null && s.actualCount! > 0) {
        absError = (editedTotal - s.actualCount!).abs().toDouble();
        pctError = (absError / s.actualCount!) * 100;
      }

      rows.add([
        s.id, s.createdAt, s.imagePath, s.imageWidth, s.imageHeight,
        modelCount, s.modelHalfRipe, s.modelRipe, s.modelUnripe,
        s.editedHalfRipe ?? "", s.editedRipe ?? "", s.editedUnripe ?? "", editedTotal,
        s.actualCount ?? "", absError, pctError,
        s.confThreshold, s.iouThreshold, s.inferenceMs, s.isDemo ? 1 : 0
      ]);
    }

    String csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final path = "${dir.path}/mangocount_export_${DateTime.now().millisecondsSinceEpoch}.csv";
    final file = File(path);
    await file.writeAsString(csv);

    // ignore: deprecated_member_use
    await Share.shareXFiles([XFile(path)], text: 'MangoCount Harvest History Export');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyProvider);
    final df = DateFormat('MMM d, yyyy · h:mm a');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primary = isDark ? AppColors.darkPrimaryMint : AppColors.primaryGreen;
    final amber = isDark ? AppColors.darkRipeAmber : AppColors.ripeAmber;
    final surface = isDark ? AppColors.darkSurface : AppColors.surfaceWhite;
    final text = isDark ? AppColors.darkTextParchment : AppColors.charcoalText;
    final muted = isDark ? AppColors.darkMutedMist : AppColors.mutedGraphite;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export CSV',
            onPressed: () => _exportCsv(context, ref),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading history: $err')),
        data: (scans) {
          if (scans.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 56, color: muted.withOpacity(0.4)),
                    const SizedBox(height: 16),
                    Text(
                      'No harvest scans recorded yet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Take a tree photo or video from Home to start counting mangoes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: scans.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final s = scans[index];
              final total = s.currentTotal;
              final ripe = s.currentRipe;
              final unripe = s.currentUnripe;
              final overRipe = s.currentOverRipe;

              return Dismissible(
                key: Key(s.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.errorCrimson,
                    borderRadius: AppShapes.leafCut,
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
                ),
                onDismissed: (_) {
                  ref.read(historyProvider.notifier).deleteScan(s.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Scan removed from log'),
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () {
                          ref.read(historyProvider.notifier).addScan(s);
                        },
                      ),
                    ),
                  );
                },
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => HistoryDetailScreen(scan: s)),
                      );
                    },
                    borderRadius: AppShapes.leafCut,
                    child: Ink(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: AppShapes.leafCut,
                        border: Border.all(
                          color: isDark ? AppColors.darkOutline : const Color(0x1F1F5D3F),
                        ),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: s.imagePath.isNotEmpty && File(s.imagePath).existsSync()
                                ? Image.file(
                                    File(s.imagePath),
                                    width: 62,
                                    height: 62,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: 62,
                                    height: 62,
                                    color: primary.withOpacity(0.1),
                                    child: Icon(Icons.image_outlined, color: primary),
                                  ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '$total Mangoes',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: text,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (s.isDemo)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        margin: const EdgeInsets.only(right: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'DEMO',
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange.shade900,
                                          ),
                                        ),
                                      ),
                                    if (s.editedHalfRipe != null || s.editedRipe != null || s.editedUnripe != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: primary.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'EDITED',
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: primary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  df.format(DateTime.fromMillisecondsSinceEpoch(s.createdAt)),
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    _buildMiniPill('Ripe: $ripe', amber),
                                    const SizedBox(width: 4),
                                    _buildMiniPill('Unripe: $unripe', AppColors.unripeGreen),
                                    const SizedBox(width: 4),
                                    _buildMiniPill('Over: $overRipe', AppColors.overRipeEarth),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: muted),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMiniPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
