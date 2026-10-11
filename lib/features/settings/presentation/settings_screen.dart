import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../application/settings_controller.dart';
import '../../history/application/history_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primary = isDark ? AppColors.darkPrimaryMint : AppColors.primaryGreen;
    final amber = isDark ? AppColors.darkRipeAmber : AppColors.ripeAmber;
    final surface = isDark ? AppColors.darkSurface : AppColors.surfaceWhite;
    final text = isDark ? AppColors.darkTextParchment : AppColors.charcoalText;
    final muted = isDark ? AppColors.darkMutedMist : AppColors.mutedGraphite;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Section 1: Vision Model & Reticle Sensitivity
          _buildSectionHeader('SCANNER SETTINGS', primary),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: AppShapes.leafCut,
              border: Border.all(
                  color:
                      isDark ? AppColors.darkOutline : const Color(0x1F1F5D3F)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.label_outline_rounded, color: primary),
                  title: Text('Show Fruit Labels',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, color: text)),
                  subtitle: Text(
                      'Shows ripeness and fruit tags over detected mangoes',
                      style: TextStyle(color: muted, fontSize: 12)),
                  value: settings.showLabels,
                  onChanged: notifier.updateShowLabels,
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: Icon(Icons.auto_awesome, color: amber),
                  title: Text('Auto Sensitivity',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, color: text)),
                  subtitle: Text(
                    settings.autoConfidence
                        ? 'Automatically adjusts sensitivity for sunlight and tree distance'
                        : 'Manual sensitivity configured below',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  value: settings.autoConfidence,
                  onChanged: notifier.updateAutoConfidence,
                ),
                if (!settings.autoConfidence) ...[
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const SizedBox(width: 24),
                    title: Text('Manual Sensitivity',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: text,
                            fontSize: 13)),
                    subtitle: Slider(
                      value: settings.confThreshold,
                      min: 0.05,
                      max: 0.50,
                      divisions: 18,
                      label:
                          '${(settings.confThreshold * 100).toStringAsFixed(0)}%',
                      onChanged: notifier.updateConfThreshold,
                    ),
                    trailing: Text(
                      '${(settings.confThreshold * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: text),
                    ),
                  ),
                ],
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading:
                      Icon(Icons.filter_center_focus_rounded, color: primary),
                  title: Text('Overlap Filter',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, color: text)),
                  subtitle: Slider(
                    value: settings.iouThreshold,
                    min: 0.3,
                    max: 0.7,
                    divisions: 8,
                    label: settings.iouThreshold.toStringAsFixed(2),
                    onChanged: notifier.updateIouThreshold,
                  ),
                  trailing: Text(
                    settings.iouThreshold.toStringAsFixed(2),
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: text),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(Icons.aspect_ratio_rounded, color: primary),
                  title: Text('Photo Detail Level',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, color: text)),
                  subtitle: DropdownButton<int>(
                    value: settings.maxResolution,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                          value: 1280, child: Text('Fast Scan (lower memory)')),
                      DropdownMenuItem(
                          value: 1920,
                          child: Text('High Accuracy (recommended)')),
                      DropdownMenuItem(
                          value: 4000, child: Text('Maximum Detail')),
                    ],
                    onChanged: (val) {
                      if (val != null) notifier.updateMaxResolution(val);
                    },
                  ),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.grid_goldenratio_rounded,
                      color: Color(0xFF00796B)),
                  title: Text('Wide Photo Scanner',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, color: text)),
                  subtitle: Text(
                    'Scans large or wide tree photos in sections to find distant fruits.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  value: settings.tiledInference,
                  onChanged: notifier.updateTiledInference,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Section 2: Online AI Check
          _buildSectionHeader('ONLINE AI CHECK', Colors.purple),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: AppShapes.leafCut,
              border: Border.all(color: Colors.purple.withOpacity(0.25)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.cloud_sync_rounded,
                      color: Colors.purple),
                  title: Text('AI Fruit Check',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, color: text)),
                  subtitle: Text(
                    'Reviews detected fruit for ripeness and possible leaf or hand false positives.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  value: settings.autoAiAssist,
                  onChanged: notifier.updateAutoAiAssist,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.key_rounded, color: Colors.purple),
                  title: Text('Google Gemini API Key',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, color: text)),
                  subtitle: Text(
                    settings.geminiApiKey.isEmpty
                        ? 'Not configured (tap to set)'
                        : 'Active · ••••••••${settings.geminiApiKey.length > 8 ? settings.geminiApiKey.substring(settings.geminiApiKey.length - 4) : ""}',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    final ctrl =
                        TextEditingController(text: settings.geminiApiKey);
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Row(
                          children: [
                            Icon(Icons.auto_awesome, color: Colors.purple),
                            SizedBox(width: 8),
                            Text('Gemini API Key'),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Enter your Google AI Studio Gemini API key to enable online fruit ripeness checking and chatbot advice.',
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: ctrl,
                              decoration: const InputDecoration(
                                labelText: 'Gemini API Key',
                                hintText: 'AIzaSy...',
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              notifier.updateGeminiApiKey(ctrl.text.trim());
                              Navigator.pop(ctx);
                            },
                            child: const Text('Save Key'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Section 3: Data & Maintenance
          _buildSectionHeader('SAVED DATA', muted),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: AppShapes.leafCut,
              border: Border.all(
                  color:
                      isDark ? AppColors.darkOutline : const Color(0x1F1F5D3F)),
            ),
            child: ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.errorCrimson),
              title: const Text('Clear All Harvest Records',
                  style: TextStyle(
                      color: AppColors.errorCrimson,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(
                  'Deletes all saved scans and photos from this device',
                  style: TextStyle(color: muted, fontSize: 12)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Confirm Reset'),
                    content: const Text(
                        'Are you sure you want to permanently erase all harvest records? This action cannot be undone.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.errorCrimson),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Erase All',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  ref.read(historyProvider.notifier).clearHistory();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('All harvest records cleared.')),
                    );
                  }
                }
              },
            ),
          ),

          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: color,
        ),
      ),
    );
  }
}
