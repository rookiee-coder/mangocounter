# Codebase index

Inventory of application, tests, tooling, native Android, model assets, and training/configuration files. Generated artifacts, dependency caches, and Git internals are excluded. Symbol listings identify navigation entry points, not proof of behavioral coverage.

Flow: main/app -> Riverpod controllers -> on-device detector or video scanner -> results/manual review -> SQLite history. Optional Gemini services handle crop review and chat. See REVIEW.md for findings and limits.

| File | Lines | Declared classes/enums |
| --- | ---: | --- |
| [analysis_options.yaml](../analysis_options.yaml) | 28 |  |
| [android/app/build.gradle](../android/app/build.gradle) | 48 |  |
| [android/app/src/debug/AndroidManifest.xml](../android/app/src/debug/AndroidManifest.xml) | 7 |  |
| [android/app/src/main/AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml) | 48 |  |
| [android/app/src/main/kotlin/com/example/mangocounter/MainActivity.kt](../android/app/src/main/kotlin/com/example/mangocounter/MainActivity.kt) | 48 | MainActivity |
| [android/app/src/main/res/drawable/launch_background.xml](../android/app/src/main/res/drawable/launch_background.xml) | 12 |  |
| [android/app/src/main/res/drawable-v21/launch_background.xml](../android/app/src/main/res/drawable-v21/launch_background.xml) | 12 |  |
| [android/app/src/main/res/mipmap-hdpi/ic_launcher.png](../android/app/src/main/res/mipmap-hdpi/ic_launcher.png) | binary/notebook | |
| [android/app/src/main/res/mipmap-mdpi/ic_launcher.png](../android/app/src/main/res/mipmap-mdpi/ic_launcher.png) | binary/notebook | |
| [android/app/src/main/res/mipmap-xhdpi/ic_launcher.png](../android/app/src/main/res/mipmap-xhdpi/ic_launcher.png) | binary/notebook | |
| [android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png](../android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png) | binary/notebook | |
| [android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png](../android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png) | binary/notebook | |
| [android/app/src/main/res/values/styles.xml](../android/app/src/main/res/values/styles.xml) | 18 |  |
| [android/app/src/main/res/values-night/styles.xml](../android/app/src/main/res/values-night/styles.xml) | 18 |  |
| [android/app/src/profile/AndroidManifest.xml](../android/app/src/profile/AndroidManifest.xml) | 7 |  |
| [android/build.gradle](../android/build.gradle) | 52 |  |
| [android/gradle.properties](../android/gradle.properties) | 3 |  |
| [android/gradle/wrapper/gradle-wrapper.properties](../android/gradle/wrapper/gradle-wrapper.properties) | 5 |  |
| [android/settings.gradle](../android/settings.gradle) | 25 |  |
| [assets/models/labels.txt](../assets/models/labels.txt) | 3 |  |
| [assets/models/mango_yolo.tflite](../assets/models/mango_yolo.tflite) | binary/notebook | |
| [lib/app.dart](../lib/app.dart) | 20 | MangoCountApp |
| [lib/core/constants/app_constants.dart](../lib/core/constants/app_constants.dart) | 11 | AppConstants |
| [lib/core/errors/app_exception.dart](../lib/core/errors/app_exception.dart) | 13 | AppException, ModelFormatException |
| [lib/core/theme/app_theme.dart](../lib/core/theme/app_theme.dart) | 198 | AppColors, AppShapes, AppTheme |
| [lib/core/utils/image_utils.dart](../lib/core/utils/image_utils.dart) | 38 | ImageUtils |
| [lib/core/utils/result.dart](../lib/core/utils/result.dart) | 13 | Success, Failure |
| [lib/features/about/presentation/about_screen.dart](../lib/features/about/presentation/about_screen.dart) | 232 | AboutScreen |
| [lib/features/chat/application/chat_controller.dart](../lib/features/chat/application/chat_controller.dart) | 184 | ChatState, ChatController |
| [lib/features/chat/data/chat_service.dart](../lib/features/chat/data/chat_service.dart) | 491 | ChatService |
| [lib/features/chat/domain/chat_message.dart](../lib/features/chat/domain/chat_message.dart) | 51 | ChatRole, ChatMessage |
| [lib/features/chat/domain/scan_chat_context.dart](../lib/features/chat/domain/scan_chat_context.dart) | 52 | ScanChatContext |
| [lib/features/chat/presentation/chat_screen.dart](../lib/features/chat/presentation/chat_screen.dart) | 689 | ChatScreen, _ChatScreenState |
| [lib/features/chat/presentation/widgets/botanical_markdown_text.dart](../lib/features/chat/presentation/widgets/botanical_markdown_text.dart) | 158 | BotanicalMarkdownText |
| [lib/features/detection/application/detection_controller.dart](../lib/features/detection/application/detection_controller.dart) | 59 | DetectionState, DetectionController |
| [lib/features/detection/application/detector_provider.dart](../lib/features/detection/application/detector_provider.dart) | 19 |  |
| [lib/features/detection/data/demo_detector.dart](../lib/features/detection/data/demo_detector.dart) | 73 | DemoDetector |
| [lib/features/detection/data/gemini_assistant_service.dart](../lib/features/detection/data/gemini_assistant_service.dart) | 505 | CropVerdict, AiAssistedDetectionResult, GeminiAssistantService |
| [lib/features/detection/data/image_preprocessor.dart](../lib/features/detection/data/image_preprocessor.dart) | 82 | PreprocessResult, ImagePreprocessor |
| [lib/features/detection/data/inference_tiles.dart](../lib/features/detection/data/inference_tiles.dart) | 23 | InferenceTile |
| [lib/features/detection/data/model_input_encoder.dart](../lib/features/detection/data/model_input_encoder.dart) | 27 | ModelInputEncoder |
| [lib/features/detection/data/tflite_detector.dart](../lib/features/detection/data/tflite_detector.dart) | 436 | _InferenceRequest, _InitRequest, TfliteDetector |
| [lib/features/detection/data/yolo_postprocessor.dart](../lib/features/detection/data/yolo_postprocessor.dart) | 340 | YoloPostprocessor |
| [lib/features/detection/domain/auto_confidence_calculator.dart](../lib/features/detection/domain/auto_confidence_calculator.dart) | 86 | AutoConfidenceCalculator |
| [lib/features/detection/domain/detection.dart](../lib/features/detection/domain/detection.dart) | 85 | Detection |
| [lib/features/detection/domain/detection_result.dart](../lib/features/detection/domain/detection_result.dart) | 34 | DetectionResult |
| [lib/features/detection/domain/detector.dart](../lib/features/detection/domain/detector.dart) | 13 | Detector |
| [lib/features/detection/domain/mango_class.dart](../lib/features/detection/domain/mango_class.dart) | 46 | MangoClass |
| [lib/features/detection/presentation/home_screen.dart](../lib/features/detection/presentation/home_screen.dart) | 1276 | HomeScreen, _HomeScreenState |
| [lib/features/detection/presentation/result_screen.dart](../lib/features/detection/presentation/result_screen.dart) | 1619 | ResultScreen, _ResultScreenState |
| [lib/features/detection/presentation/widgets/analyzing_view.dart](../lib/features/detection/presentation/widgets/analyzing_view.dart) | 390 | AnalyzingView, _AnalyzingViewState, _ViewfinderReticlePainter |
| [lib/features/detection/presentation/widgets/detection_overlay.dart](../lib/features/detection/presentation/widgets/detection_overlay.dart) | 261 | DetectionOverlay, _OpticalBoxPainter |
| [lib/features/history/application/history_controller.dart](../lib/features/history/application/history_controller.dart) | 62 | HistoryController |
| [lib/features/history/data/history_database.dart](../lib/features/history/data/history_database.dart) | 53 | HistoryDatabase |
| [lib/features/history/data/history_repository.dart](../lib/features/history/data/history_repository.dart) | 29 | HistoryRepository |
| [lib/features/history/domain/scan_record.dart](../lib/features/history/domain/scan_record.dart) | 106 | ScanRecord |
| [lib/features/history/presentation/history_detail_screen.dart](../lib/features/history/presentation/history_detail_screen.dart) | 230 | HistoryDetailScreen |
| [lib/features/history/presentation/history_screen.dart](../lib/features/history/presentation/history_screen.dart) | 299 | HistoryScreen |
| [lib/features/settings/application/settings_controller.dart](../lib/features/settings/application/settings_controller.dart) | 142 | SettingsState, SettingsController |
| [lib/features/settings/presentation/settings_screen.dart](../lib/features/settings/presentation/settings_screen.dart) | 276 | SettingsScreen |
| [lib/features/video_scan/application/video_scan_controller.dart](../lib/features/video_scan/application/video_scan_controller.dart) | 135 | VideoScanState, VideoScanController |
| [lib/features/video_scan/data/tree_canopy_validator.dart](../lib/features/video_scan/data/tree_canopy_validator.dart) | 385 | CanopyValidationResult, InvalidTreeVideoException, TreeCanopyValidator |
| [lib/features/video_scan/data/tree_tracker.dart](../lib/features/video_scan/data/tree_tracker.dart) | 268 | _ActiveTrack, TreeTracker |
| [lib/features/video_scan/data/video_sampling.dart](../lib/features/video_scan/data/video_sampling.dart) | 25 | VideoSampling |
| [lib/features/video_scan/data/video_scanner_service.dart](../lib/features/video_scan/data/video_scanner_service.dart) | 208 | VideoScannerService |
| [lib/features/video_scan/domain/tracked_mango.dart](../lib/features/video_scan/domain/tracked_mango.dart) | 50 | TrackedMango |
| [lib/features/video_scan/domain/video_frame_data.dart](../lib/features/video_scan/domain/video_frame_data.dart) | 20 | VideoFrameData |
| [lib/features/video_scan/domain/video_scan_result.dart](../lib/features/video_scan/domain/video_scan_result.dart) | 83 | VideoScanResult |
| [lib/features/video_scan/presentation/video_analyzing_view.dart](../lib/features/video_scan/presentation/video_analyzing_view.dart) | 156 | VideoAnalyzingView |
| [lib/features/video_scan/presentation/video_result_screen.dart](../lib/features/video_scan/presentation/video_result_screen.dart) | 487 | VideoResultScreen, _VideoResultScreenState |
| [lib/main.dart](../lib/main.dart) | 26 |  |
| [pubspec.lock](../pubspec.lock) | 802 |  |
| [pubspec.yaml](../pubspec.yaml) | 110 |  |
| [README.md](../README.md) | 45 |  |
| [test/ai_reconcile_test.dart](../test/ai_reconcile_test.dart) | 146 |  |
| [test/auto_confidence_test.dart](../test/auto_confidence_test.dart) | 114 |  |
| [test/chat_feature_test.dart](../test/chat_feature_test.dart) | 136 |  |
| [test/detection_result_test.dart](../test/detection_result_test.dart) | 30 |  |
| [test/evaluation_test.dart](../test/evaluation_test.dart) | 63 |  |
| [test/gemini_assistant_test.dart](../test/gemini_assistant_test.dart) | 71 |  |
| [test/gemini_crop_reconciliation_test.dart](../test/gemini_crop_reconciliation_test.dart) | 260 |  |
| [test/history_repository_test.dart](../test/history_repository_test.dart) | 79 |  |
| [test/image_preprocessor_test.dart](../test/image_preprocessor_test.dart) | 22 |  |
| [test/inference_regression_test.dart](../test/inference_regression_test.dart) | 139 |  |
| [test/tree_canopy_validator_test.dart](../test/tree_canopy_validator_test.dart) | 201 |  |
| [test/tree_tracker_test.dart](../test/tree_tracker_test.dart) | 229 |  |
| [test/video_scanner_service_test.dart](../test/video_scanner_service_test.dart) | 108 | _Detector, _Canopy |
| [test/widget_test.dart](../test/widget_test.dart) | 27 |  |
| [test/yolo_normalization_test.dart](../test/yolo_normalization_test.dart) | 38 |  |
| [test/yolo_postprocessor_test.dart](../test/yolo_postprocessor_test.dart) | 50 |  |
| [tool/evaluate_detections.dart](../tool/evaluate_detections.dart) | 135 |  |
| [tool/probe_sample_photos.py](../tool/probe_sample_photos.py) | 122 |  |
| [tool/setup_evaluation_runtime.ps1](../tool/setup_evaluation_runtime.ps1) | 21 |  |
| [train_mango_yolov11.ipynb](../train_mango_yolov11.ipynb) | binary/notebook | |
