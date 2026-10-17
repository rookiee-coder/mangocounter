import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/detection.dart';
import '../../domain/mango_class.dart';

class DetectionOverlay extends StatelessWidget {
  final List<Detection> detections;
  final int imageWidth;
  final int imageHeight;
  final bool showLabels;
  final bool showBoxes;
  final Function(Detection)? onBoxTap;
  final Function(double imageX, double imageY)? onImageTap;
  final Function(double imageX, double imageY)? onImageLongPress;

  const DetectionOverlay({
    super.key,
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    this.showLabels = true,
    this.showBoxes = true,
    this.onBoxTap,
    this.onImageTap,
    this.onImageLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleX = constraints.maxWidth / imageWidth;
        final scaleY = constraints.maxHeight / imageHeight;
        final scale = scaleX < scaleY ? scaleX : scaleY; // fit uniformly

        final renderW = imageWidth * scale;
        final renderH = imageHeight * scale;

        final offsetX = (constraints.maxWidth - renderW) / 2;
        final offsetY = (constraints.maxHeight - renderH) / 2;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final localX = details.localPosition.dx - offsetX;
            final localY = details.localPosition.dy - offsetY;

            // Check if tap was on the image
            if (localX < 0 ||
                localX > renderW ||
                localY < 0 ||
                localY > renderH) return;

            final imgX = (localX / scale).clamp(0.0, imageWidth.toDouble());
            final imgY = (localY / scale).clamp(0.0, imageHeight.toDouble());

            // Check if tap falls inside an existing detection box
            Detection? tappedDet;
            final hitPad = 14.0 / scale; // touch forgiveness
            for (int i = detections.length - 1; i >= 0; i--) {
              final d = detections[i];
              if (imgX >= (d.x1 - hitPad) &&
                  imgX <= (d.x2 + hitPad) &&
                  imgY >= (d.y1 - hitPad) &&
                  imgY <= (d.y2 + hitPad)) {
                tappedDet = d;
                break;
              }
            }

            if (tappedDet != null && onBoxTap != null) {
              onBoxTap!(tappedDet);
            } else if (onImageTap != null) {
              onImageTap!(imgX, imgY);
            }
          },
          onLongPressStart: onImageLongPress != null
              ? (details) {
                  final localX = details.localPosition.dx - offsetX;
                  final localY = details.localPosition.dy - offsetY;
                  if (localX < 0 ||
                      localX > renderW ||
                      localY < 0 ||
                      localY > renderH) return;
                  final imgX =
                      (localX / scale).clamp(0.0, imageWidth.toDouble());
                  final imgY =
                      (localY / scale).clamp(0.0, imageHeight.toDouble());
                  onImageLongPress!(imgX, imgY);
                }
              : null,
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _OpticalBoxPainter(
              detections: detections,
              imageWidth: imageWidth,
              imageHeight: imageHeight,
              scale: scale,
              offsetX: offsetX,
              offsetY: offsetY,
              showLabels: showLabels,
              showBoxes: showBoxes,
            ),
          ),
        );
      },
    );
  }
}

class _OpticalBoxPainter extends CustomPainter {
  final List<Detection> detections;
  final int imageWidth;
  final int imageHeight;
  final double scale;
  final double offsetX;
  final double offsetY;
  final bool showLabels;
  final bool showBoxes;

  _OpticalBoxPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    required this.showLabels,
    required this.showBoxes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showBoxes && !showLabels) return;

    final imgLeft = offsetX;
    final imgTop = offsetY;
    final imgRight = offsetX + imageWidth * scale;
    final imgBottom = offsetY + imageHeight * scale;

    for (final det in detections) {
      Color color = AppColors.unripeGreen;
      if (det.mangoClass == MangoClass.ripe) color = AppColors.ripeAmber;
      if (det.mangoClass == MangoClass.over_ripe) {
        color = AppColors.overRipeEarth;
      }
      if (det.userEdited) color = const Color(0xFF0288D1);
      if (det.needsReview) color = const Color(0xFFE65100);

      // Strict clamping of bounding box to displayed image rect
      final left = (offsetX + det.x1 * scale).clamp(imgLeft, imgRight);
      final top = (offsetY + det.y1 * scale).clamp(imgTop, imgBottom);
      final right = (offsetX + det.x2 * scale).clamp(imgLeft, imgRight);
      final bottom = (offsetY + det.y2 * scale).clamp(imgTop, imgBottom);

      if (right <= left || bottom <= top) continue;

      final rect = Rect.fromLTRB(left, top, right, bottom);

      if (showBoxes) {
        // 1. Subtle translucent fill
        final fillPaint = Paint()
          ..color = color.withOpacity(det.needsReview ? 0.16 : 0.08)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(6)), fillPaint);

        // 2. Optical Precision Corner Brackets (Surveyor Reticle Tenet)
        final strokePaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = det.needsReview ? 2.5 : 2.0
          ..strokeCap = StrokeCap.round;

        final double armLength = (rect.width * 0.28).clamp(8.0, 20.0);
        final double armHeight = (rect.height * 0.28).clamp(8.0, 20.0);

        // Top-Left bracket
        canvas.drawLine(Offset(rect.left, rect.top),
            Offset(rect.left + armLength, rect.top), strokePaint);
        canvas.drawLine(Offset(rect.left, rect.top),
            Offset(rect.left, rect.top + armHeight), strokePaint);

        // Top-Right bracket
        canvas.drawLine(Offset(rect.right, rect.top),
            Offset(rect.right - armLength, rect.top), strokePaint);
        canvas.drawLine(Offset(rect.right, rect.top),
            Offset(rect.right - armHeight, rect.top), strokePaint);

        // Bottom-Left bracket
        canvas.drawLine(Offset(rect.left, rect.bottom),
            Offset(rect.left + armLength, rect.bottom), strokePaint);
        canvas.drawLine(Offset(rect.left, rect.bottom),
            Offset(rect.left, rect.bottom - armHeight), strokePaint);

        // Bottom-Right bracket
        canvas.drawLine(Offset(rect.right, rect.bottom),
            Offset(rect.right - armLength, rect.bottom), strokePaint);
        canvas.drawLine(Offset(rect.right, rect.bottom),
            Offset(rect.right - armHeight, rect.bottom), strokePaint);

        // Hairline boundary guide connecting brackets
        final guidePaint = Paint()
          ..color = color.withOpacity(0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(4)),
            guidePaint);
      }

      if (showLabels) {
        final aiBadge = det.aiVerified ? ' ✨' : '';
        final reviewBadge = det.needsReview ? ' ❓' : '';
        final confStr = '${(det.confidence * 100).toStringAsFixed(0)}%';
        final labelText =
            '${det.mangoClass.displayName}$aiBadge$reviewBadge $confStr';

        final textSpan = TextSpan(
          text: labelText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
            letterSpacing: 0.3,
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();

        final labelWidth = textPainter.width + 12;
        final labelHeight = textPainter.height + 6;

        double labelTop = rect.top - labelHeight - 2;
        if (labelTop < imgTop) {
          labelTop = rect.top + 2;
        }

        double labelLeft = rect.left;
        if (labelLeft + labelWidth > imgRight) {
          labelLeft = imgRight - labelWidth;
        }
        if (labelLeft < imgLeft) {
          labelLeft = imgLeft;
        }

        final pillRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(labelLeft, labelTop, labelWidth, labelHeight),
          const Radius.circular(6),
        );

        canvas.drawRRect(
          pillRect,
          Paint()
            ..color = const Color(0xE0101F16)
            ..style = PaintingStyle.fill,
        );
        canvas.drawRRect(
          pillRect,
          Paint()
            ..color = color.withOpacity(0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );

        textPainter.paint(canvas, Offset(labelLeft + 6, labelTop + 3));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OpticalBoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.scale != scale ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.showBoxes != showBoxes;
  }
}
