import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class VideoAnalyzingView extends StatelessWidget {
  final double progress;
  final String statusStep;
  final VoidCallback? onCancel;

  const VideoAnalyzingView({
    super.key,
    required this.progress,
    required this.statusStep,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimaryMint : AppColors.primaryGreen;
    final surface = isDark ? AppColors.darkSurface : AppColors.surfaceWhite;
    final text = isDark ? AppColors.darkTextParchment : AppColors.charcoalText;
    final muted = isDark ? AppColors.darkMutedMist : AppColors.mutedGraphite;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Optical Radar Animation Container
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary.withOpacity(0.08),
                border: Border.all(color: primary.withOpacity(0.3), width: 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      strokeWidth: 4,
                      color: primary,
                      backgroundColor: primary.withOpacity(0.12),
                    ),
                  ),
                  Icon(Icons.videocam_rounded, size: 44, color: primary),
                ],
              ),
            ),

            const SizedBox(height: 28),

            Text(
              'SCANNING TREE VIDEO',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Counting Each Mango Once',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),

            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 6,
                color: primary,
                backgroundColor: isDark ? AppColors.darkOutline : const Color(0x1F1F5D3F),
              ),
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress * 100).toStringAsFixed(0)}% COMPLETE',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
                ),
                Text(
                  'SMART COUNTER',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Status Step Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppColors.darkOutline : const Color(0x1A1F5D3F),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.track_changes_rounded, size: 18, color: primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusStep.isNotEmpty ? statusStep : 'Scanning video...',
                      style: TextStyle(fontSize: 12.5, color: text),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            if (onCancel != null) ...[
              const SizedBox(height: 24),
              TextButton(
                onPressed: onCancel,
                child: Text('Cancel', style: TextStyle(color: muted, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
