import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class MlkitTranslationService {
  static final MlkitTranslationService instance = MlkitTranslationService._internal();
  MlkitTranslationService._internal();

  final OnDeviceTranslatorModelManager _modelManager = OnDeviceTranslatorModelManager();
  OnDeviceTranslator? _currentTranslator;
  TranslateLanguage _currentSource = TranslateLanguage.vietnamese;
  TranslateLanguage _currentTarget = TranslateLanguage.english;

  final ValueNotifier<bool> isTranslatingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> translationErrorNotifier = ValueNotifier<String?>(null);

  TranslateLanguage get sourceLanguage => _currentSource;
  TranslateLanguage get targetLanguage => _currentTarget;

  void setLanguagePair({
    required TranslateLanguage source,
    required TranslateLanguage target,
  }) {
    if (_currentSource != source || _currentTarget != target) {
      _currentSource = source;
      _currentTarget = target;
      _currentTranslator?.close();
      _currentTranslator = null;
    }
  }

  void swapLanguages() {
    final temp = _currentSource;
    _currentSource = _currentTarget;
    _currentTarget = temp;
    _currentTranslator?.close();
    _currentTranslator = null;
  }

  Future<bool> ensureModelsDownloaded() async {
    try {
      final sourceDownloaded = await _modelManager.isModelDownloaded(_currentSource.bcpCode);
      if (!sourceDownloaded) {
        debugPrint('Downloading model for ${_currentSource.bcpCode}...');
        await _modelManager.downloadModel(_currentSource.bcpCode);
      }

      final targetDownloaded = await _modelManager.isModelDownloaded(_currentTarget.bcpCode);
      if (!targetDownloaded) {
        debugPrint('Downloading model for ${_currentTarget.bcpCode}...');
        await _modelManager.downloadModel(_currentTarget.bcpCode);
      }
      return true;
    } catch (e) {
      debugPrint('Model download check: $e');
      return false;
    }
  }

  Future<String> translate(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';

    // Normalize multiple spaces and extra empty lines
    final cleaned = trimmed.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    isTranslatingNotifier.value = true;
    translationErrorNotifier.value = null;

    try {
      _currentTranslator ??= OnDeviceTranslator(
        sourceLanguage: _currentSource,
        targetLanguage: _currentTarget,
      );

      final result = await _currentTranslator!.translateText(cleaned);
      isTranslatingNotifier.value = false;
      return result;
    } catch (e) {
      debugPrint('ML Kit translation error: $e');
      // If model not yet downloaded, try downloading and translating once more
      try {
        await ensureModelsDownloaded();
        _currentTranslator?.close();
        _currentTranslator = OnDeviceTranslator(
          sourceLanguage: _currentSource,
          targetLanguage: _currentTarget,
        );
        final result = await _currentTranslator!.translateText(cleaned);
        isTranslatingNotifier.value = false;
        return result;
      } catch (retryError) {
        isTranslatingNotifier.value = false;
        translationErrorNotifier.value = 'Lỗi dịch thuật: $retryError';
        return 'Lỗi dịch: $retryError';
      }
    }
  }

  void dispose() {
    _currentTranslator?.close();
  }
}
