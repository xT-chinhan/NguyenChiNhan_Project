import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// Đọc chữ trên máy (ML Kit), bỏ dòng nhiễu
Future<String> recognizeFile(TextRecognizer r, String path) async {
  final res = await r.processImage(InputImage.fromFilePath(path));
  final lines = <String>[];
  for (final b in res.blocks) {
    for (final l in b.lines) {
      final t = l.text.trim();
      if (t.length < 3 || RegExp(r'^[\d\s\-_.,:;/\\|!@#$%^&*()+=~`<>?]+$').hasMatch(t)) continue;
      lines.add(t);
    }
  }
  return lines.join('\n');
}

/// 20 f · Dịch realtime: camera đọc chữ mỗi 1,4 giây, gửi API dịch, phủ bản dịch lên khung hình
class TranslateCameraScreen extends StatefulWidget {
  const TranslateCameraScreen({super.key});
  @override
  State<TranslateCameraScreen> createState() => _TranslateCameraScreenState();
}

class _TranslateCameraScreenState extends State<TranslateCameraScreen> with WidgetsBindingObserver {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  CameraController? _cam;
  String? _camError;
  int _dir = 0; // 0: Anh -> Việt, 1: Việt -> Anh
  bool _busy = false;
  bool _torch = false;
  bool _alive = true;
  String _lastText = '';
  List<(String, String)> _pairs = []; // (dịch, gốc)
  String _status = 'Đang mở camera…';

  (String, String) get _langs => _dir == 0 ? ('en', 'vi') : ('vi', 'en');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    _alive = false;
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    _recognizer.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.inactive) {
      _cam?.dispose();
      _cam = null;
    } else if (s == AppLifecycleState.resumed && _cam == null) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final ctl = CameraController(back, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await ctl.initialize();
      if (!mounted) {
        await ctl.dispose();
        return;
      }
      setState(() {
        _cam = ctl;
        _status = 'Hướng camera vào chữ';
      });
      _loop();
    } on CameraException catch (e) {
      setState(() => _camError = e.code == 'CameraAccessDenied' ? 'Bạn chưa cho phép dùng camera.' : 'Không mở được camera: ${e.description}');
    } catch (e) {
      setState(() => _camError = 'Không mở được camera.');
    }
  }

  Future<void> _loop() async {
    while (_alive && mounted && _cam != null) {
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!_busy) await _scanFrame();
    }
  }

  Future<void> _scanFrame() async {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized || cam.value.isTakingPicture) return;
    _busy = true;
    try {
      final shot = await cam.takePicture();
      final text = await recognizeFile(_recognizer, shot.path);
      File(shot.path).delete().ignore();
      if (text.isEmpty || text == _lastText) return;
      _lastText = text;
      final (src, tgt) = _langs;
      final r = await Api.i.post('/tools/translate', {'text': text, 'source': src, 'target': tgt});
      final tr = (r['translated'] as String).split('\n');
      final orig = text.split('\n');
      if (mounted) {
        setState(() {
          _pairs = [for (var i = 0; i < tr.length; i++) (tr[i], i < orig.length ? orig[i] : '')];
          _status = 'Đã dịch ${tr.length} dòng';
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _status = e.message);
    } catch (_) {
      // khung hình lỗi: bỏ qua, quét lại vòng sau
    } finally {
      _busy = false;
    }
  }

  Future<void> _captureAndOpen({bool gallery = false}) async {
    String? path;
    if (gallery) {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
      path = x?.path;
    } else {
      final cam = _cam;
      if (cam == null) return;
      while (_busy) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      _busy = true;
      try {
        path = (await cam.takePicture()).path;
      } finally {
        _busy = false;
      }
    }
    if (path == null || !mounted) return;
    final (src, tgt) = _langs;
    Navigator.push(context, MaterialPageRoute(builder: (_) => TranslateResultScreen(imagePath: path!, source: src, target: tgt, recognizer: _recognizer)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cam = _cam;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF1B1A18),
        body: Stack(children: [
          Positioned.fill(
            child: cam != null && cam.value.isInitialized
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(width: cam.value.previewSize!.height, height: cam.value.previewSize!.width, child: CameraPreview(cam)),
                  )
                : Center(child: Text(_camError ?? _status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70))),
          ),
          // Bản dịch phủ lên khung hình
          if (_pairs.isNotEmpty)
            Positioned(
              left: 40,
              right: 40,
              top: MediaQuery.of(context).size.height * .22,
              child: Transform.rotate(
                angle: -0.02,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final p in _pairs.take(6))
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .96), borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 8, offset: Offset(0, 2))]),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.$1, style: const TextStyle(color: Color(0xFF111111), fontSize: 14, fontWeight: FontWeight.w600, height: 1.35)),
                        if (p.$2.isNotEmpty) Text(p.$2.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFA9A8A3), fontSize: 11)),
                      ]),
                    ),
                ]),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _Glass(onTap: () => Navigator.pop(context), child: const Icon(LucideIcons.x, size: 18, color: Colors.white)),
                _Glass(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF3DDC84), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(_status, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ]),
                ),
                _Glass(
                  onTap: cam == null
                      ? null
                      : () async {
                          _torch = !_torch;
                          await cam.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
                          setState(() {});
                        },
                  child: Icon(_torch ? LucideIcons.zapOff : LucideIcons.zap, size: 18, color: Colors.white),
                ),
              ]),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(color: c.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 36, height: 5, decoration: BoxDecoration(color: c.containerHigh, borderRadius: BorderRadius.circular(3))),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: Segmented(
                      items: const ['Anh → Việt', 'Việt → Anh'],
                      index: _dir,
                      onChanged: (i) => setState(() {
                        _dir = i;
                        _lastText = '';
                        _pairs = [];
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleBtn(LucideIcons.arrowLeftRight, filled: false, onTap: () => setState(() {
                        _dir = 1 - _dir;
                        _lastText = '';
                        _pairs = [];
                      })),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Btn.secondary('Chọn ảnh', icon: LucideIcons.image, onTap: () => _captureAndOpen(gallery: true))),
                  const SizedBox(width: 10),
                  Expanded(child: Btn('Chụp & dịch', icon: LucideIcons.camera, onTap: cam == null ? null : _captureAndOpen)),
                ]),
                const SizedBox(height: 12),
                Text('Đọc chữ trên máy · dịch bằng NguyenChiNhan_WebAPI', style: T.bodyS.copyWith(color: c.muted)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Glass({required this.child, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0x8C111111), borderRadius: BorderRadius.circular(999)),
          child: child,
        ),
      );
}

/// 21 f · Kết quả dịch từ ảnh chụp / ảnh chọn
class TranslateResultScreen extends StatefulWidget {
  final String imagePath;
  final String source, target;
  final TextRecognizer recognizer;
  const TranslateResultScreen({super.key, required this.imagePath, required this.source, required this.target, required this.recognizer});
  @override
  State<TranslateResultScreen> createState() => _TranslateResultScreenState();
}

class _TranslateResultScreenState extends State<TranslateResultScreen> {
  String? _text;
  Map? _res;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final text = await recognizeFile(widget.recognizer, widget.imagePath);
      if (!mounted) return;
      setState(() => _text = text);
      if (text.isEmpty) return;
      final r = await Api.i.post('/tools/translate', {'text': text, 'source': widget.source, 'target': widget.target});
      if (mounted) setState(() => _res = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Không đọc được ảnh này.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = _res;
    return Scaffold(
      appBar: TopBar(back: 'Camera', title: 'Dịch ảnh', actions: [
        if (r != null)
          CircleBtn(LucideIcons.copy, filled: false, onTap: () {
            Clipboard.setData(ClipboardData(text: r['translated']));
            toast(context, 'Đã sao chép bản dịch');
          }),
      ]),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 4, kPad, 16), children: [
              ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.file(File(widget.imagePath), height: 150, fit: BoxFit.cover)),
              const SizedBox(height: 16),
              if (_error != null)
                Note(_error!, icon: LucideIcons.circleAlert)
              else if (_text == null) ...[
                const Skeleton(width: 140, height: 12),
                const SizedBox(height: 10),
                const Skeleton(height: 84, radius: 18),
              ] else if (_text!.isEmpty)
                const EmptyState(icon: LucideIcons.scanText, title: 'Không thấy chữ trong ảnh', text: 'Chụp gần hơn, đủ sáng và giữ máy thẳng.', top: 12)
              else ...[
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Chữ đọc được${r != null ? ' · ${r['sourceName']}' : ''}', style: T.label.copyWith(color: c.muted)),
                  Pill('${_text!.split('\n').length} dòng', icon: LucideIcons.check, tone: Tone.ok),
                ]),
                const SizedBox(height: 8),
                AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Text(_text!, style: T.bodyM)),
                const SizedBox(height: 16),
                Text('Bản dịch${r != null ? ' · ${r['targetName']}' : ''}', style: T.label.copyWith(color: c.muted)),
                const SizedBox(height: 8),
                r == null
                    ? const Skeleton(height: 84, radius: 18)
                    : AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Text(r['translated'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.55)),
                      ),
                if (r != null) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(LucideIcons.scanText, size: 15, color: c.muted),
                    const SizedBox(width: 6),
                    Text('ML Kit đọc chữ · máy chủ dịch · ${r['ms']} ms', style: T.bodyS.copyWith(color: c.muted)),
                  ]),
                ],
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 16),
            child: Btn('Chụp ảnh khác', icon: LucideIcons.camera, onTap: () => Navigator.pop(context)),
          ),
        ]),
      ),
    );
  }
}
