import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SystemClockService {
  static final SystemClockService instance = SystemClockService._internal();
  SystemClockService._internal();

  static const MethodChannel _channel = MethodChannel('com.app.smartutility/system_alarm');

  /// Tùy chọn: Đặt báo thức bằng đồng hồ thật của máy (Android System Clock)
  final ValueNotifier<bool> useSystemClockNotifier = ValueNotifier<bool>(true);

  Future<bool> setSystemAlarm({
    required int hour,
    required int minute,
    String message = 'Báo thức từ Smart Utility',
    bool skipUi = false,
  }) async {
    try {
      final success = await _channel.invokeMethod<bool>('setSystemAlarm', {
        'hour': hour,
        'minute': minute,
        'message': message,
        'skipUi': skipUi,
      });
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to set system alarm: ${e.message}');
      return false;
    }
  }

  Future<bool> openSystemClock() async {
    try {
      final success = await _channel.invokeMethod<bool>('openSystemClock');
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to open system clock: ${e.message}');
      return false;
    }
  }
}
