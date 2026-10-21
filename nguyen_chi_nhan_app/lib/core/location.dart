import 'package:geolocator/geolocator.dart';

/// Một lần lấy GPS: app chỉ đọc cảm biến rồi gửi API, API mới quyết định hợp lệ hay không
class GeoFix {
  final double lat, lng, accuracy;
  final bool isMocked;
  const GeoFix(this.lat, this.lng, this.accuracy, {this.isMocked = false});
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'accuracy': accuracy, 'isMocked': isMocked};
}

/// GPS tắt / chưa cho quyền
class LocationProblem implements Exception {
  final String message;
  final bool serviceOff;
  const LocationProblem(this.message, {this.serviceOff = false});
  @override
  String toString() => message;
}

/// Giờ máy (thay khi test để ảnh chụp không phụ thuộc giờ thật)
DateTime Function() deviceNow = DateTime.now;

class Locator {
  /// Thay khi test (không có GPS thật)
  static Future<GeoFix> Function()? override;

  static Future<GeoFix> current() async {
    if (override != null) return override!();
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationProblem('Bật Vị trí (GPS) trên điện thoại để chấm công tại cửa hàng.', serviceOff: true);
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      throw const LocationProblem('Cho phép app dùng vị trí để chấm công tại cửa hàng.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
    return GeoFix(pos.latitude, pos.longitude, pos.accuracy, isMocked: pos.isMocked);
  }

  /// Mở cài đặt để bật GPS hoặc cấp quyền
  static Future<void> openSettings({bool serviceOff = false}) =>
      serviceOff ? Geolocator.openLocationSettings() : Geolocator.openAppSettings();
}
