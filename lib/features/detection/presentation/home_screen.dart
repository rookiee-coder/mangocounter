import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../application/detection_controller.dart';
import '../application/detector_provider.dart';
import 'result_screen.dart';
import 'widgets/analyzing_view.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../history/presentation/history_screen.dart';
import '../../about/presentation/about_screen.dart';
import '../../history/application/history_controller.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../video_scan/application/video_scan_controller.dart';
import '../../video_scan/presentation/video_analyzing_view.dart';
import '../../video_scan/presentation/video_result_screen.dart';
import '../../settings/application/settings_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;

  Future<void> _pickImage(ImageSource source) async {
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (status.isPermanentlyDenied) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Camera Permission Denied'),
              content: const Text(
                'Camera access is required for real-time orchard canopy scanning. Please enable it in system settings.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    openAppSettings();
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        }
        return;
      } else if (!status.isGranted) {
        return;
      }
    }

    final XFile? image = await _picker.pickImage(
      source: source,
      maxWidth: AppConstants.modelMaxResolution.toDouble(),
      maxHeight: AppConstants.modelMaxResolution.toDouble(),
      imageQuality: 95,
    );
    if (image != null && mounted) {
      setState(() => _isProcessing = true);

      final bytes = await image.readAsBytes();

      if (mounted) {
        setState(() => _isProcessing = false);
        ref.read(detectionControllerProvider.notifier).reset();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResultScreen(imageBytes: bytes, originalPath: image.path),
          ),
        );
      }
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (status.isPermanentlyDenied) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Camera Permission Denied'),
              content: const Text(
                'Camera access is required for tree video scanning. Please enable it in system settings.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    openAppSettings();
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        }
        return;
      } else if (!status.isGranted) {
        return;
      }
    }

    final XFile? video = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 20),
    );

    if (video != null && mounted) {
      final settings = ref.read(settingsProvider);
      final result = await ref
          .read(videoScanControllerProvider.notifier)
          .scanVideo(video.path, apiKey: settings.geminiApiKey);

      if (!mounted) return;

      if (result != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoResultScreen(result: result),
          ),
        );
      } else {
        final scanState = ref.read(videoScanControllerProvider);
        if (scanState.isNonTreeVideo) {
          _showNonTreeSubjectDialog(
            detectedSubject: scanState.detectedSubject ?? 'Non-tree scene',
            reason: scanState.nonTreeReason ?? 'The video does not depict a mango tree canopy.',
            source: source,
          );
        } else if (scanState.errorMessage != null && scanState.errorMessage!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(scanState.errorMessage!),
              backgroundColor: AppColors.errorCrimson,
            ),
          );
        }
      }
    }
  }

  void _showNonTreeSubjectDialog({
    required String detectedSubject,
    required String reason,
    required ImageSource source,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimaryMint : AppColors.primaryGreen;
    final surface = isDark ? AppColors.darkSurface : AppColors.surfaceWhite;
    final text = isDark ? AppColors.darkTextParchment : AppColors.charcoalText;
    final amber = isDark ? AppColors.darkRipeAmber : AppColors.ripeAmber;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: amber.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.park_outlined, color: amber, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'MANGO TREE CHECK',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: amber,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Not a Mango Tree Canopy',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The AI inspected the video and determined it is not pointed at a mango tree canopy:',
              style: TextStyle(fontSize: 13, color: text, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2620) : const Color(0xFFF4F7F5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? AppColors.darkOutline : const Color(0xFFE0E8E3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.visibility_outlined, size: 15, color: AppColors.mutedGraphite),
                      SizedBox(width: 6),
                      Text(
                        'Detected Subject:',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.mutedGraphite,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detectedSubject,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    reason,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: text,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.tips_and_updates_outlined, size: 16, color: primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'To reduce scan time and ensure accurate fruit counts, point your camera directly at the tree canopy or fruit branches before recording.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.mutedGraphite,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Dismiss',
              style: TextStyle(color: AppColors.mutedGraphite, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _pickVideo(source);
            },
            icon: Icon(source == ImageSource.camera ? Icons.videocam : Icons.video_library, size: 16),
            label: Text(source == ImageSource.camera ? 'Record Again' : 'Select Video'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  void _showVideoSourceDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final surface = isDark ? AppColors.darkSurface : AppColors.surfaceWhite;
        final primary = isDark ? AppColors.darkPrimaryMint : AppColors.primaryGreen;
        final text = isDark ? AppColors.darkTextParchment : AppColors.charcoalText;

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Whole-Tree Video Scan',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: text),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'Pan camera around canopy to count fruits without duplicates',
                style: TextStyle(fontSize: 12, color: AppColors.mutedGraphite),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.videocam_rounded, color: primary),
                ),
                title: Text('Record Video with Camera', style: TextStyle(fontWeight: FontWeight.bold, color: text)),
                subtitle: const Text('Capture a 5–15 second sweep across the tree', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickVideo(ImageSource.camera);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.video_library_rounded, color: primary),
                ),
                title: Text('Select Video from Gallery', style: TextStyle(fontWeight: FontWeight.bold, color: text)),
                subtitle: const Text('Choose a pre-recorded canopy sweep video', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickVideo(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final detectorAsync = ref.watch(detectorProvider);
    final isDemo = ref.watch(isDemoModeProvider);
    final historyAsync = ref.watch(historyProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primary = isDark ? AppColors.darkPrimaryMint : AppColors.primaryGreen;
    final amber = isDark ? AppColors.darkRipeAmber : AppColors.ripeAmber;
    final surface = isDark ? AppColors.darkSurface : AppColors.surfaceWhite;
    final text = isDark ? AppColors.darkTextParchment : AppColors.charcoalText;
    final muted = isDark ? AppColors.darkMutedMist : AppColors.mutedGraphite;

    final videoScanState = ref.watch(videoScanControllerProvider);

    if (videoScanState.isScanning) {
      return Scaffold(
        body: SafeArea(
          child: VideoAnalyzingView(
            progress: videoScanState.progress,
            statusStep: videoScanState.statusMessage,
            onCancel: () => ref.read(videoScanControllerProvider.notifier).reset(),
          ),
        ),
      );
    }

    if (_isProcessing) {
      return Scaffold(
        body: SafeArea(
          child: AnalyzingView(
            statusStep: 'Reading photo and preparing scan...',
            onCancel: () => setState(() => _isProcessing = false),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.eco, color: primary, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: text,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'MANGO SCANNER',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: primary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology_alt_outlined),
            tooltip: 'AI Pomology Agronomist Chat',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings & Calibration',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About & Model Info',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Demo Mode Warning Banner if model missing (preserving widget test string)
              if (isDemo)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE0B2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFB74D)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'DEMO MODE: model not found. Results are NOT real.',
                          style: TextStyle(
                            color: Color(0xFFBF360C),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Live Reticle Hardware Status Badge
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: AppShapes.pill,
                    border: Border.all(
                      color: isDark ? AppColors.darkOutline : const Color(0x261F5D3F),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: detectorAsync.isLoading
                              ? Colors.amber
                              : (isDemo ? Colors.orange : const Color(0xFF2E7D32)),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        detectorAsync.when(
                          data: (_) => isDemo ? 'DEMO MODE active' : 'Ready to Scan',
                          loading: () => 'Preparing Scanner...',
                          error: (e, _) => 'Scanner Error: $e',
                        ),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Hero Editorial Section
              Container(
                padding: const EdgeInsets.all(22),
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
                  border: Border.all(
                    color: primary.withOpacity(isDark ? 0.3 : 0.2),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'FIELD ASSISTANT · ORCHARD VIEW',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: primary,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.15),
                            borderRadius: AppShapes.pill,
                          ),
                          child: Text(
                            'AI ASSISTED',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Mango Harvest &\nRipeness Counter',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        letterSpacing: -0.6,
                        color: text,
                        fontFamilyFallback: const ['Georgia', 'serif'],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Count your mangoes, check fruit ripeness, and estimate your harvest with fast and accurate scanning.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Primary Action: Take Photo (Sunset Gradient Card)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: detectorAsync.isLoading ? null : () => _pickImage(ImageSource.camera),
                  borderRadius: AppShapes.leafCut,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: AppColors.sunsetGradient,
                      borderRadius: AppShapes.leafCut,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF8A3D).withOpacity(0.32),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B2A21),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Color(0xFFF5C33B),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Scan Tree with Camera',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1B2A21),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Point camera at tree branches or fruit clusters',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xCC1B2A21),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF1B2A21),
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Secondary Action: Choose from Field Gallery
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: detectorAsync.isLoading ? null : () => _pickImage(ImageSource.gallery),
                  borderRadius: AppShapes.leafCut,
                  child: Container(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: AppShapes.leafCut,
                      border: Border.all(
                        color: primary.withOpacity(0.35),
                        width: 1.5,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.photo_library_outlined,
                            color: primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Photo from Gallery',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Choose a saved tree photo from your phone',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: muted,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Tertiary Action: Whole-Tree Video Scan (Sweep Pan)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: detectorAsync.isLoading ? null : () => _showVideoSourceDialog(context),
                  borderRadius: AppShapes.leafCut,
                  child: Container(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: AppShapes.leafCut,
                      border: Border.all(
                        color: AppColors.ripeAmber.withOpacity(isDark ? 0.5 : 0.6),
                        width: 1.5,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.ripeAmber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.videocam_rounded,
                            color: AppColors.ripeAmber,
                            size: 24,
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
                                    'Whole-Tree Video Scan',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: text,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: primary.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'WHOLE TREE',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w800,
                                        color: primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Record a video sweep around the tree to count all fruits',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: muted,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Orchard Summary Card (History metrics)
              historyAsync.when(
                data: (scans) {
                  final totalScans = scans.length;
                  int totalFruit = 0;
                  int ripeFruit = 0;

                  for (final s in scans) {
                    final r = s.editedRipe ?? s.modelRipe;
                    final u = s.editedUnripe ?? s.modelUnripe;
                    final o = s.editedHalfRipe ?? s.modelHalfRipe;
                    ripeFruit += r;
                    totalFruit += (r + u + o);
                  }

                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: AppShapes.leafCut,
                      border: Border.all(
                        color: isDark ? AppColors.darkOutline : const Color(0x1F1F5D3F),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'ORCHARD SUMMARY',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                                color: muted,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const HistoryScreen()),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'View History (${scans.length})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: primary,
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios_rounded, size: 11, color: primary),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricTile(
                                label: 'TOTAL SCANS',
                                value: totalScans.toString(),
                                icon: Icons.history_edu,
                                color: primary,
                              ),
                            ),
                            Container(width: 1, height: 40, color: const Color(0x141F5D3F)),
                            Expanded(
                              child: _buildMetricTile(
                                label: 'TOTAL FRUIT',
                                value: totalFruit.toString(),
                                icon: Icons.grass,
                                color: amber,
                              ),
                            ),
                            Container(width: 1, height: 40, color: const Color(0x141F5D3F)),
                            Expanded(
                              child: _buildMetricTile(
                                label: 'RIPE FRUIT %',
                                value: totalFruit > 0
                                    ? '${((ripeFruit / totalFruit) * 100).toStringAsFixed(0)}%'
                                    : '—',
                                icon: Icons.wb_sunny_outlined,
                                color: const Color(0xFFE65100),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              const SizedBox(height: 20),

              // AI Harvest Advisor Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: isDark
                      ? const LinearGradient(
                          colors: [Color(0xFF14241B), Color(0xFF1B2E23)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFEBF6EE), Color(0xFFF3FAF5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: AppShapes.leafCut,
                  border: Border.all(
                    color: primary.withOpacity(0.3),
                    width: 1.2,
                  ),
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
                          child: Icon(Icons.psychology_alt_rounded, color: primary, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AI HARVEST ASSISTANT',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                  color: primary,
                                ),
                              ),
                              Text(
                                'Ask about Harvest, Pests & Fruit Care',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Have questions about when to pick fruits, pest control, or fruit protection? Ask your harvest assistant anytime.',
                      style: TextStyle(fontSize: 12, color: text, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.chat_bubble_outline_rounded, size: 16, color: primary),
                        label: Text(
                          'ASK HARVEST ASSISTANT',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: primary,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: primary.withOpacity(0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ChatScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Tree Guidance Quick Tips
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111E16) : const Color(0xFFF3EDE2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tips_and_updates_outlined, color: amber, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TREE SCANNING TIP',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Stand 5 to 10 feet from the tree. Make sure leaves and fruits are in clear daylight.',
                            style: TextStyle(
                              fontSize: 12,
                              color: text,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: color,
                  fontFamilyFallback: const ['Georgia', 'serif'],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppColors.mutedGraphite,
            ),
          ),
        ],
      ),
    );
  }
}
