import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

/// Mẫu đo: (dB trung bình, dB cao nhất) của một khung âm thanh
typedef NoiseSample = (double mean, double max);

/// Đo dB bằng micro trình duyệt (getUserMedia + AnalyserNode). Cùng công thức noise_meter: 20·log10(32768·biên độ).
class NoiseSource {
  /// Safari chỉ cho mở âm thanh sau khi người dùng bấm
  static const needsTap = true;

  web.AudioContext? _ctx;
  web.MediaStream? _stream;
  Timer? _timer;

  Future<String?> start(void Function(NoiseSample) onSample) async {
    try {
      // Tạo + resume AudioContext ngay trong lần bấm (yêu cầu của Safari)
      final ctx = web.AudioContext();
      _ctx = ctx;
      ctx.resume();
      final stream = await web.window.navigator.mediaDevices.getUserMedia(web.MediaStreamConstraints(audio: true.toJS)).toDart;
      _stream = stream;
      final analyser = ctx.createAnalyser()..fftSize = 2048;
      ctx.createMediaStreamSource(stream).connect(analyser);
      final buf = JSFloat32Array.withLength(analyser.fftSize);
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        analyser.getFloatTimeDomainData(buf);
        final data = buf.toDart;
        var sum = 0.0;
        for (final v in data) {
          sum += v * v;
        }
        final rms = sqrt(sum / data.length);
        if (rms <= 0) return;
        // Mức của khung = RMS (đỉnh sóng tức thời làm "Cao nhất" vọt lên ~90 dB)
        final db = min(20 * log(rms * 32768) / ln10, 130.0);
        if (db.isFinite && db >= 0) onSample((db, db));
      });
      return null;
    } catch (_) {
      await stop();
      return 'Chưa mở được micro. Cho phép Safari dùng micro rồi bấm Bắt đầu đo.';
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final tracks = _stream?.getTracks().toDart ?? const [];
    for (final t in tracks) {
      t.stop();
    }
    _stream = null;
    await _ctx?.close().toDart;
    _ctx = null;
  }
}
