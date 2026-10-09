import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Full-screen or modal scanning view for Screen 1 of Stitch ("Analyzing Image").
/// Provides an optical surveyor inspection console with animated reticle sweep,
/// telemetry steps, and botanical instrument aesthetics.
class AnalyzingView extends StatefulWidget {
  final Uint8List? imageBytes;
  final String statusStep;
  final VoidCallback? onCancel;

  const AnalyzingView({
    super.key,
    this.imageBytes,
    this.statusStep = 'Finding and counting mangoes...',
    this.onCancel,
  });

  @override
  State<AnalyzingView> createState() => _AnalyzingViewState();
}

class _AnalyzingViewState extends State<AnalyzingView>
    with SingleTickerProviderStateMixin {
  late AnimationController _sweepController;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimaryMint : AppColors.primaryGreen;
    final amber = isDark ? AppColors.darkRipeAmber : AppColors.ripeAmber;
    final surface = isDark ? AppColors.darkSurface : AppColors.surfaceWhite;
    final text = isDark ? AppColors.darkTextParchment : AppColors.charcoalText;
    final muted = isDark ? AppColors.darkMutedMist : AppColors.mutedGraphite;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Optical Viewfinder with animated laser sweep
            Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF09120D) : const Color(0xFFEAF4EC),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: primary.withOpacity(0.35), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: primary.withOpacity(0.10),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (widget.imageBytes != null)
                      Opacity(
                        opacity: 0.45,
                        child: Image.memory(
                          widget.imageBytes!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      )
                    else
                      Icon(
                        Icons.park_outlined,
                        size: 72,
                        color: primary.withOpacity(0.25),
                      ),

                    // Optical targeting corner reticles
                    CustomPaint(
                      size: const Size(260, 260),
                      painter: _ViewfinderReticlePainter(color: primary),
                    ),

                    // Animated scanning beam
                    AnimatedBuilder(
                      animation: _sweepController,
                      builder: (context, child) {
                        return Positioned(
                          top: _sweepController.value * 230 + 10,
                          left: 12,
                          right: 12,
                          child: Container(
                            height: 2.5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  amber.withOpacity(0.0),
                                  amber,
                                  amber.withOpacity(0.0),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: amber.withOpacity(0.7),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    // Center crosshair
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: amber.withOpacity(0.7), width: 1.5),
                      ),
                      child: Center(
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: amber,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // Telemetry Monospace Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.12),
                borderRadius: AppShapes.pill,
                border: Border.all(color: primary.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SCANNING IN PROGRESS',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: primary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Editorial Headline
            Text(
              'Analyzing Mango Tree Photo',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
                color: text,
                fontFamilyFallback: const ['Georgia', 'serif'],
              ),
            ),

            const SizedBox(height: 8),

            Text(
              widget.statusStep,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: muted,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 28),

            // Inspection Step Cards
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: AppShapes.leafCut,
                border: Border.all(color: isDark ? AppColors.darkOutline : const Color(0x1F1F5D3F)),
              ),
              child: Column(
                children: [
                  _buildStepTile(
                    number: '01',
                    label: 'Preparing Photo',
                    desc: 'Enhancing image for clear fruit visibility',
                    completed: true,
                    primaryColor: primary,
                    textColor: text,
                    mutedColor: muted,
                  ),
                  const Divider(height: 18, color: Color(0x141F5D3F)),
                  _buildStepTile(
                    number: '02',
                    label: 'Finding Mangoes',
                    desc: 'Locating each fruit on tree branches',
                    active: true,
                    primaryColor: amber,
                    textColor: text,
                    mutedColor: muted,
                  ),
                  const Divider(height: 18, color: Color(0x141F5D3F)),
                  _buildStepTile(
                    number: '03',
                    label: 'Checking Ripeness',
                    desc: 'Classifying ripe, unripe, and harvest-ready fruits',
                    queued: true,
                    primaryColor: primary,
                    textColor: text,
                    mutedColor: muted,
                  ),
                ],
              ),
            ),

            if (widget.onCancel != null) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: widget.onCancel,
                child: Text(
                  'Cancel Scan',
                  style: TextStyle(color: muted, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepTile({
    required String number,
    required String label,
    required String desc,
    bool completed = false,
    bool active = false,
    bool queued = false,
    required Color primaryColor,
    required Color textColor,
    required Color mutedColor,
  }) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: completed
                ? primaryColor
                : (active ? primaryColor.withOpacity(0.15) : Colors.transparent),
            border: Border.all(
              color: completed ? primaryColor : (active ? primaryColor : mutedColor.withOpacity(0.4)),
              width: 1.5,
            ),
          ),
          child: Center(
            child: completed
                ? const Icon(Icons.check, size: 15, color: Colors.white)
                : (active
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
                      )
                    : Text(
                        number,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: mutedColor,
                          fontFamily: 'monospace',
                        ),
                      )),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 11,
                  color: mutedColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ViewfinderReticlePainter extends CustomPainter {
  final Color color;
  _ViewfinderReticlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    const arm = 18.0;
    const pad = 14.0;

    // Top-Left
    canvas.drawLine(const Offset(pad, pad), const Offset(pad + arm, pad), paint);
    canvas.drawLine(const Offset(pad, pad), const Offset(pad, pad + arm), paint);

    // Top-Right
    canvas.drawLine(Offset(size.width - pad, pad), Offset(size.width - pad - arm, pad), paint);
    canvas.drawLine(Offset(size.width - pad, pad), Offset(size.width - pad, pad + arm), paint);

    // Bottom-Left
    canvas.drawLine(Offset(pad, size.height - pad), Offset(pad + arm, size.height - pad), paint);
    canvas.drawLine(Offset(pad, size.height - pad), Offset(pad, size.height - pad - arm), paint);

    // Bottom-Right
    canvas.drawLine(Offset(size.width - pad, size.height - pad), Offset(size.width - pad - arm, size.height - pad), paint);
    canvas.drawLine(Offset(size.width - pad, size.height - pad), Offset(size.width - pad, size.height - pad - arm), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
