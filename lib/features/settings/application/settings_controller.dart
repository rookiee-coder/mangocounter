import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  ),
);

class SettingsState {
  final double confThreshold;
  final double iouThreshold;
  final bool showLabels;
  final int maxResolution;
  final String geminiApiKey;
  final String grokApiKey;
  final String openRouterApiKey;
  final String aiProvider; // 'auto', 'gemini', 'grok', 'openrouter'
  final bool autoAiAssist;
  final bool autoConfidence;
  final bool tiledInference;

  SettingsState({
    this.confThreshold = 0.25,
    this.iouThreshold = 0.45,
    this.showLabels = true,
    this.maxResolution = 1920,
    this.geminiApiKey =
        const String.fromEnvironment('GEMINI_API_KEY', defaultValue: ''),
    this.grokApiKey = '',
    this.openRouterApiKey =
        const String.fromEnvironment('OPENROUTER_API_KEY', defaultValue: ''),
    this.aiProvider = 'gemini',
    this.autoAiAssist = true,
    this.autoConfidence = true,
    this.tiledInference = true,
  });

  SettingsState copyWith({
    double? confThreshold,
    double? iouThreshold,
    bool? showLabels,
    int? maxResolution,
    String? geminiApiKey,
    String? grokApiKey,
    String? openRouterApiKey,
    String? aiProvider,
    bool? autoAiAssist,
    bool? autoConfidence,
    bool? tiledInference,
  }) {
    return SettingsState(
      confThreshold: confThreshold ?? this.confThreshold,
      iouThreshold: iouThreshold ?? this.iouThreshold,
      showLabels: showLabels ?? this.showLabels,
      maxResolution: maxResolution ?? this.maxResolution,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      grokApiKey: grokApiKey ?? this.grokApiKey,
      openRouterApiKey: openRouterApiKey ?? this.openRouterApiKey,
      aiProvider: aiProvider ?? this.aiProvider,
      autoAiAssist: autoAiAssist ?? this.autoAiAssist,
      autoConfidence: autoConfidence ?? this.autoConfidence,
      tiledInference: tiledInference ?? this.tiledInference,
    );
  }
}

class SettingsController extends StateNotifier<SettingsState> {
  final SharedPreferences prefs;
  final FlutterSecureStorage secureStorage;
  static const _geminiApiKeyStorageKey = 'geminiApiKey';

  SettingsController(this.prefs, this.secureStorage)
      : super(SettingsState(
          confThreshold: prefs.getDouble('confThreshold') ?? 0.25,
          iouThreshold: prefs.getDouble('iouThreshold') ?? 0.45,
          showLabels: prefs.getBool('showLabels') ?? true,
          maxResolution: prefs.getInt('maxResolution') ?? 1920,
          geminiApiKey:
              const String.fromEnvironment('GEMINI_API_KEY', defaultValue: ''),
          grokApiKey: prefs.getString('grokApiKey') ?? '',
          openRouterApiKey:
              (prefs.getString('openRouterApiKey')?.trim().isNotEmpty ?? false)
                  ? prefs.getString('openRouterApiKey')!
                  : const String.fromEnvironment('OPENROUTER_API_KEY',
                      defaultValue: ''),
          aiProvider: prefs.getString('aiProvider') ?? 'gemini',
          autoAiAssist: prefs.getBool('autoAiAssist') ?? true,
          autoConfidence: prefs.getBool('autoConfidence') ?? true,
          tiledInference: prefs.getBool('tiledInference') ?? true,
        )) {
    _restoreGeminiApiKey();
  }

  Future<void> _restoreGeminiApiKey() async {
    try {
      final secured = await secureStorage.read(key: _geminiApiKeyStorageKey);
      if (secured?.trim().isNotEmpty == true) {
        state = state.copyWith(geminiApiKey: secured!.trim());
        return;
      }

      // One-time migration from previous releases that used plain preferences.
      final legacy = prefs.getString(_geminiApiKeyStorageKey)?.trim();
      if (legacy?.isNotEmpty == true) {
        await secureStorage.write(key: _geminiApiKeyStorageKey, value: legacy);
        await prefs.remove(_geminiApiKeyStorageKey);
        state = state.copyWith(geminiApiKey: legacy!);
      }
    } catch (_) {
      // Keep the app usable with its build-time key when secure storage is
      // temporarily unavailable on a device.
    }
  }

  void updateTiledInference(bool val) {
    state = state.copyWith(tiledInference: val);
    prefs.setBool('tiledInference', val);
  }

  void updateAutoConfidence(bool val) {
    state = state.copyWith(autoConfidence: val);
    prefs.setBool('autoConfidence', val);
  }

  void updateConfThreshold(double val) {
    state = state.copyWith(confThreshold: val);
    prefs.setDouble('confThreshold', val);
  }

  void updateIouThreshold(double val) {
    state = state.copyWith(iouThreshold: val);
    prefs.setDouble('iouThreshold', val);
  }

  void updateShowLabels(bool val) {
    state = state.copyWith(showLabels: val);
    prefs.setBool('showLabels', val);
  }

  void updateMaxResolution(int val) {
    state = state.copyWith(maxResolution: val);
    prefs.setInt('maxResolution', val);
  }

  Future<void> updateGeminiApiKey(String val) async {
    final normalized = val.trim();
    state = state.copyWith(geminiApiKey: normalized);
    if (normalized.isEmpty) {
      await secureStorage.delete(key: _geminiApiKeyStorageKey);
    } else {
      await secureStorage.write(
          key: _geminiApiKeyStorageKey, value: normalized);
    }
    await prefs.remove(_geminiApiKeyStorageKey);
  }

  void updateGrokApiKey(String val) {
    state = state.copyWith(grokApiKey: val);
    prefs.setString('grokApiKey', val);
  }

  void updateOpenRouterApiKey(String val) {
    state = state.copyWith(openRouterApiKey: val);
    prefs.setString('openRouterApiKey', val);
  }

  void updateAiProvider(String val) {
    state = state.copyWith(aiProvider: val);
    prefs.setString('aiProvider', val);
  }

  void updateAutoAiAssist(bool val) {
    state = state.copyWith(autoAiAssist: val);
    prefs.setBool('autoAiAssist', val);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final secureStorage = ref.watch(secureStorageProvider);
  return SettingsController(prefs, secureStorage);
});
