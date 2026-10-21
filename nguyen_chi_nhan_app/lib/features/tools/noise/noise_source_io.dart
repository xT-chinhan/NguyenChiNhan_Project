import 'dart:async';
import 'dart:math';

import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

/// Mẫu đo: (dB trung bình, dB cao nhất) của một khung âm thanh
typedef NoiseSample = (double mean, double max);

class NoiseSource {
  /// Bản web cần người dùng bấm nút mới mở micro được
  static const needsTap = false;

  StreamSubscription<NoiseReading>? _sub;

  Future<String?> start(void Function(NoiseSample) onSample) async {
    final st = await Permission.microphone.request();
    if (!st.isGranted) return 'Cần quyền micro để đo tiếng ồn.';
    _sub = NoiseMeter().noise.listen((r) {
      final v = r.meanDecibel;
      if (v.isNaN || v.isInfinite || v < 0) return;
      onSample((v, r.maxDecibel.isFinite ? min(r.maxDecibel, 130) : v));
    });
    return null;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
