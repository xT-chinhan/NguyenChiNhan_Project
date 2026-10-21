import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import '../../../services/mlkit_translation_service.dart';

class RealtimeCameraView extends StatefulWidget {
  const RealtimeCameraView({super.key});

  @override
  State<RealtimeCameraView> createState() => _RealtimeCameraViewState();
}

class _RealtimeCameraViewState extends State<RealtimeCameraView>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInit = false;
  bool _isBusy = false;
  bool _isPaused = false;
  bool _isTorchOn = false;

  String _detectedText = '';
  String _translatedText = '';
  String _statusMessage = 'Đang khởi động ML Kit...';

  // Language pair state
  TranslateLanguage _sourceLang = TranslateLanguage.english;
  TranslateLanguage _targetLang = TranslateLanguage.vietnamese;

  final List<Map<String, dynamic>> _supportedLanguages = [
    {'lang': TranslateLanguage.english, 'name': 'Tiếng Anh', 'flag': '🇺🇸'},
    {'lang': TranslateLanguage.vietnamese, 'name': 'Tiếng Việt', 'flag': '🇻🇳'},
    {'lang': TranslateLanguage.french, 'name': 'Tiếng Pháp', 'flag': '🇫🇷'},
    {'lang': TranslateLanguage.japanese, 'name': 'Tiếng Nhật', 'flag': '🇯🇵'},
    {'lang': TranslateLanguage.korean, 'name': 'Tiếng Hàn', 'flag': '🇰🇷'},
    {'lang': TranslateLanguage.chinese, 'name': 'Tiếng Trung', 'flag': '🇨🇳'},
  ];

  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  late AnimationController _scanLineController;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _initCameraAndModels();
  }

  Future<void> _initCameraAndModels() async {
    // 1. Sync languages to service
    MlkitTranslationService.instance.setLanguagePair(
      source: _sourceLang,
      target: _targetLang,
    );

    // 2. Ensure models downloaded
    _checkModels();

    // 3. Initialize Camera
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _controller = CameraController(
          _cameras![0],
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        await _controller!.initialize();
        if (mounted) {
          setState(() {
            _isInit = true;
            _statusMessage = 'Sẵn sàng quét văn bản';
          });
          _startContinuousScanning();
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'Không thể kết nối Camera: $e';
        });
      }
    }
  }

  Future<void> _checkModels() async {
    final ok = await MlkitTranslationService.instance.ensureModelsDownloaded();
    if (mounted && !ok) {
      setState(() {
        _statusMessage = 'Đang tải gói ngôn ngữ offline...';
      });
    }
  }

  void _startContinuousScanning() async {
    while (mounted && _controller != null && _controller!.value.isInitialized) {
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted) break;
      if (!_isPaused && !_isBusy) {
        await _captureAndProcessFrame();
      }
    }
  }

  /// Clean raw OCR noise: discard single letters, pure symbols, and numbers
  String _filterAndCleanOcrText(RecognizedText recognized) {
    final validLines = <String>[];

    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        // Skip short noise (< 3 characters) or lines with only punctuation/symbols
        if (text.length < 3) continue;
        if (RegExp(r'^[\d\s\-_.,:;/\\|!@#$%^&*()+=~`<>?]+$').hasMatch(text)) {
          continue;
        }
        validLines.add(text);
      }
    }

    if (validLines.isEmpty) return '';
    return validLines.join('\n');
  }

  Future<void> _captureAndProcessFrame() async {
    if (_controller == null || !_controller!.value.isInitialized || _isBusy) return;
    _isBusy = true;

    try {
      final xfile = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(xfile.path);
      final recognized = await _textRecognizer.processImage(inputImage);

      // Clean up temporary photo file
      try {
        await File(xfile.path).delete();
      } catch (_) {}

      final cleanedText = _filterAndCleanOcrText(recognized);

      if (cleanedText.isNotEmpty && cleanedText != _detectedText && mounted) {
        setState(() {
          _detectedText = cleanedText;
          _statusMessage = 'Đã nhận diện (${cleanedText.split('\n').length} dòng), đang dịch...';
        });

        final trans = await MlkitTranslationService.instance.translate(cleanedText);
        if (mounted) {
          setState(() {
            _translatedText = trans;
            _statusMessage = 'Dịch thành công (Google ML Kit On-Device)';
          });
        }
      } else if (cleanedText.isEmpty && _detectedText.isEmpty && mounted) {
        setState(() {
          _statusMessage = 'Đang quét văn bản trước ống kính...';
        });
      }
    } catch (e) {
      debugPrint('Realtime frame processing error: $e');
    } finally {
      _isBusy = false;
    }
  }

  void _swapLanguages() {
    setState(() {
      final temp = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = temp;
      _detectedText = '';
      _translatedText = '';
    });
    MlkitTranslationService.instance.setLanguagePair(
      source: _sourceLang,
      target: _targetLang,
    );
    _checkModels();
    _showToast('Đã đổi chiều dịch: ${_getLanguageName(_sourceLang)} ➔ ${_getLanguageName(_targetLang)}');
  }

  void _onSourceChanged(TranslateLanguage? val) {
    if (val != null && val != _sourceLang) {
      setState(() {
        _sourceLang = val;
        _detectedText = '';
        _translatedText = '';
      });
      MlkitTranslationService.instance.setLanguagePair(
        source: _sourceLang,
        target: _targetLang,
      );
      _checkModels();
    }
  }

  void _onTargetChanged(TranslateLanguage? val) {
    if (val != null && val != _targetLang) {
      setState(() {
        _targetLang = val;
        _detectedText = '';
        _translatedText = '';
      });
      MlkitTranslationService.instance.setLanguagePair(
        source: _sourceLang,
        target: _targetLang,
      );
      _checkModels();
    }
  }

  String _getLanguageName(TranslateLanguage lang) {
    final item = _supportedLanguages.firstWhere(
      (m) => m['lang'] == lang,
      orElse: () => {'name': lang.bcpCode, 'flag': '🌐'},
    );
    return '${item['flag']} ${item['name']}';
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
    });
    _showToast(_isPaused ? 'Đã tạm dừng quét (Giữ khung hình)' : 'Đang tiếp tục quét liên tục');
  }

  void _toggleTorch() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      _isTorchOn = !_isTorchOn;
      await _controller!.setFlashMode(_isTorchOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (e) {
      debugPrint('Flash toggle error: $e');
    }
  }

  void _copyTranslation() {
    if (_translatedText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _translatedText));
      _showToast('Đã sao chép bản dịch vào bộ nhớ tạm!');
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit || _controller == null || !_controller!.value.isInitialized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final boxWidth = size.width * 0.86;
    const boxHeight = 180.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera Viewport
        CameraPreview(_controller!),

        // Semi-transparent Dimmed Overlay outside Target Box
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withAlpha(90),
            BlendMode.srcOut,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Align(
                alignment: const Alignment(0, -0.2),
                child: Container(
                  width: boxWidth,
                  height: boxHeight,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Viewfinder Target Frame with Animated Scanner Line
        Align(
          alignment: const Alignment(0, -0.2),
          child: SizedBox(
            width: boxWidth,
            height: boxHeight,
            child: Stack(
              children: [
                // Border frame
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _isPaused ? Colors.orangeAccent : Colors.greenAccent,
                      width: 2.5,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),

                // Viewfinder Instruction Pill
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isPaused ? Colors.orangeAccent : Colors.greenAccent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isPaused ? Icons.pause_circle_filled_rounded : Icons.radar_rounded,
                          size: 14,
                          color: _isPaused ? Colors.orangeAccent : Colors.greenAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isPaused ? 'ĐÃ TẠM DỪNG QUÉT' : 'HƯỚNG CAMERA VÀO VĂN BẢN',
                          style: TextStyle(
                            color: _isPaused ? Colors.orangeAccent : Colors.greenAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Animated Laser Scan Line
                if (!_isPaused)
                  AnimatedBuilder(
                    animation: _scanLineController,
                    builder: (context, _) {
                      return Positioned(
                        top: 20 + (_scanLineController.value * (boxHeight - 40)),
                        left: 8,
                        right: 8,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.greenAccent.withAlpha(200),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                            gradient: const LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.greenAccent,
                                Colors.white,
                                Colors.greenAccent,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),

        // TOP BAR: Language Selector & Quick Controls
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(200),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24, width: 1),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  // Source Language Dropdown
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<TranslateLanguage>(
                        value: _sourceLang,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E293B),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
                        items: _supportedLanguages.map((item) {
                          return DropdownMenuItem<TranslateLanguage>(
                            value: item['lang'] as TranslateLanguage,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${item['flag']} ${item['name']}',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: _onSourceChanged,
                      ),
                    ),
                  ),

                  // Swap Language Button (1-Tap Fast Toggle)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.swap_horiz_rounded, color: Colors.greenAccent, size: 22),
                      tooltip: 'Đổi chiều dịch nhanh',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: _swapLanguages,
                    ),
                  ),

                  // Target Language Dropdown
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<TranslateLanguage>(
                        value: _targetLang,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E293B),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
                        items: _supportedLanguages.map((item) {
                          return DropdownMenuItem<TranslateLanguage>(
                            value: item['lang'] as TranslateLanguage,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${item['flag']} ${item['name']}',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: _onTargetChanged,
                      ),
                    ),
                  ),

                  // Flash Torch Button
                  IconButton(
                    icon: Icon(
                      _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      color: _isTorchOn ? Colors.amberAccent : Colors.white70,
                      size: 20,
                    ),
                    tooltip: 'Bật/Tắt đèn pin',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: _toggleTorch,
                  ),
                ],
              ),
            ),
          ),
        ),

        // BOTTOM BAR: Translation Results Card with Controls
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: SafeArea(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 280),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(225),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isPaused ? Colors.orangeAccent.withAlpha(180) : Colors.greenAccent.withAlpha(180),
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black87, blurRadius: 16, offset: Offset(0, 6)),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Status Row
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: _isPaused ? Colors.orangeAccent : Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage,
                            style: TextStyle(
                              color: _isPaused ? Colors.orangeAccent : Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_isBusy)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
                          ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Detected Original Text
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '📝 Văn bản gốc (${_getLanguageName(_sourceLang)}):',
                                style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _detectedText.isEmpty
                                ? 'Đang chờ chữ xuất hiện trong khung ngắm...'
                                : _detectedText,
                            style: TextStyle(
                              color: _detectedText.isEmpty ? Colors.white38 : Colors.white70,
                              fontSize: 12.5,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Translated Result
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.greenAccent.withAlpha(80)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '🌐 Bản dịch (${_getLanguageName(_targetLang)}):',
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              if (_translatedText.isNotEmpty)
                                GestureDetector(
                                  onTap: _copyTranslation,
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.copy_rounded, color: Colors.greenAccent, size: 14),
                                      SizedBox(width: 4),
                                      Text('Sao chép', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _translatedText.isEmpty
                                ? 'Kết quả dịch on-device sẽ hiển thị tại đây...'
                                : _translatedText,
                            style: TextStyle(
                              color: _translatedText.isEmpty ? Colors.white38 : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Quick Action Buttons Row (Pause/Resume & Capture Now)
                    Row(
                      children: [
                        // Toggle Pause / Resume Button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _togglePause,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isPaused ? Colors.orangeAccent.shade700 : Colors.blueGrey.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 18),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _isPaused ? 'Tiếp Tục Quét' : 'Tạm Dừng (Giữ Khung)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Force Scan Now Button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isBusy ? null : _captureAndProcessFrame,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Quét Lại Ngay',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
