import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimaryMint : AppColors.primaryGreen;
    final surface = isDark ? AppColors.darkSurface : AppColors.surfaceWhite;
    final text = isDark ? AppColors.darkTextParchment : AppColors.charcoalText;
    final muted = isDark ? AppColors.darkMutedMist : AppColors.mutedGraphite;

    return Scaffold(
      appBar: AppBar(title: const Text('About MangoCount')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // App Mark
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF14241B), Color(0xFF0F1A13)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [Color(0xFFE6F5EA), Color(0xFFF3FAF5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: AppShapes.leafCut,
              border: Border.all(color: primary.withOpacity(0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.eco, color: primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppConstants.appName,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: text,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'VERSION 1.0.0 · FARMER EDITION',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'MangoCount helps farmers and fruit growers count mangoes quickly and check fruit ripeness using your phone camera. It works directly in the orchard even without an internet connection.',
                  style: TextStyle(fontSize: 13, height: 1.45, color: text),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'HOW IT WORKS',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: AppShapes.leafCut,
              border: Border.all(
                  color:
                      isDark ? AppColors.darkOutline : const Color(0x1F1F5D3F)),
            ),
            child: Column(
              children: [
                _buildSpecRow(
                  icon: Icons.flash_on_rounded,
                  title: '1. Instant On-Device Scanner',
                  detail:
                      'Finds and counts mangoes directly on your phone in less than a second, even without internet or cell service.',
                  primary: primary,
                  text: text,
                  muted: muted,
                ),
                const Divider(height: 24, color: Color(0x141F5D3F)),
                _buildSpecRow(
                  icon: Icons.auto_awesome,
                  title: '2. Smart Ripeness Check',
                  detail:
                      'Checks whether fruits are ripe, unripe, or ready for harvest, and filters out leaves and branches.',
                  primary: Colors.purple,
                  text: text,
                  muted: muted,
                ),
                const Divider(height: 24, color: Color(0x141F5D3F)),
                _buildSpecRow(
                  icon: Icons.wb_sunny_outlined,
                  title: '3. Smart Sunlight Adjustment',
                  detail:
                      'Automatically adjusts for bright sun, shadows, and tree distance so you get an accurate fruit count.',
                  primary: AppColors.ripeAmber,
                  text: text,
                  muted: muted,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'HELPFUL FARM TIPS',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: AppShapes.leafCut,
              border: Border.all(
                  color:
                      isDark ? AppColors.darkOutline : const Color(0x1F1F5D3F)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTip(
                  '1. Distance from Tree',
                  'Stand 5 to 10 feet from the tree branches. If the tree is large, use the Whole-Tree Video Scan or scan in sections.',
                  text,
                  muted,
                ),
                const SizedBox(height: 12),
                _buildTip(
                  '2. Hidden Fruits',
                  'The scanner counts all visible fruits. If branches are thick, gently move leaves aside to capture hidden mangoes.',
                  text,
                  muted,
                ),
                const SizedBox(height: 12),
                _buildTip(
                  '3. Record Keeping',
                  'Save your scans to keep track of harvest numbers and compare your counts season to season.',
                  text,
                  muted,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSpecRow({
    required IconData icon,
    required String title,
    required String detail,
    required Color primary,
    required Color text,
    required Color muted,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14, color: text)),
              const SizedBox(height: 3),
              Text(detail,
                  style: TextStyle(fontSize: 12, height: 1.4, color: muted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTip(String title, String desc, Color text, Color muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: text)),
        const SizedBox(height: 2),
        Text(desc, style: TextStyle(fontSize: 12, height: 1.35, color: muted)),
      ],
    );
  }
}
