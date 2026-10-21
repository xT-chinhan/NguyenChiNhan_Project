import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OcrResult {
  final File imageFile;
  final String text;
  final List<TextBlock> blocks;

  OcrResult({
    required this.imageFile,
    required this.text,
    required this.blocks,
  });
}

class MlkitOcrService {
  static final MlkitOcrService instance = MlkitOcrService._internal();
  MlkitOcrService._internal();

  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final ValueNotifier<bool> isScanningNotifier = ValueNotifier<bool>(false);

  Future<OcrResult?> scanImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 90,
      );

      if (pickedFile == null) return null;

      isScanningNotifier.value = true;
      final file = File(pickedFile.path);
      final inputImage = InputImage.fromFilePath(file.path);

      final recognizedText = await _textRecognizer.processImage(inputImage);
      isScanningNotifier.value = false;

      return OcrResult(
        imageFile: file,
        text: recognizedText.text,
        blocks: recognizedText.blocks,
      );
    } catch (e) {
      debugPrint('OCR Scanning failed: $e');
      isScanningNotifier.value = false;
      return null;
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
