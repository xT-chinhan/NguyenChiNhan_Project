import 'package:flutter/material.dart';

enum CategoryType {
  temperature,
  length,
  weight,
  speed,
  volume,
}

enum AlertLevel {
  info,
  success,
  warning,
  critical,
}

class SmartAlert {
  final String title;
  final String message;
  final AlertLevel level;
  final IconData icon;

  SmartAlert({
    required this.title,
    required this.message,
    required this.level,
    required this.icon,
  });

  Color get color {
    switch (level) {
      case AlertLevel.info:
        return const Color(0xFF3B82F6);
      case AlertLevel.success:
        return const Color(0xFF10B981);
      case AlertLevel.warning:
        return const Color(0xFFF59E0B);
      case AlertLevel.critical:
        return const Color(0xFFEF4444);
    }
  }

  Color get backgroundColor {
    switch (level) {
      case AlertLevel.info:
        return const Color(0xFFEFF6FF);
      case AlertLevel.success:
        return const Color(0xFFECFDF5);
      case AlertLevel.warning:
        return const Color(0xFFFFFBEB);
      case AlertLevel.critical:
        return const Color(0xFFFEF2F2);
    }
  }
}

class UnitDefinition {
  final String id;
  final String name;
  final String symbol;

  const UnitDefinition({
    required this.id,
    required this.name,
    required this.symbol,
  });
}

class UnitCategory {
  final CategoryType type;
  final String name;
  final IconData icon;
  final Color color;
  final List<UnitDefinition> units;

  const UnitCategory({
    required this.type,
    required this.name,
    required this.icon,
    required this.color,
    required this.units,
  });

  static const List<UnitCategory> all = [
    UnitCategory(
      type: CategoryType.temperature,
      name: 'Nhiệt độ',
      icon: Icons.thermostat_rounded,
      color: Color(0xFFF97316),
      units: [
        UnitDefinition(id: 'c', name: 'Độ C (Celsius)', symbol: '°C'),
        UnitDefinition(id: 'f', name: 'Độ F (Fahrenheit)', symbol: '°F'),
        UnitDefinition(id: 'k', name: 'Kelvin', symbol: 'K'),
        UnitDefinition(id: 'r', name: 'Rankine', symbol: '°R'),
      ],
    ),
    UnitCategory(
      type: CategoryType.length,
      name: 'Chiều dài',
      icon: Icons.straighten_rounded,
      color: Color(0xFF3B82F6),
      units: [
        UnitDefinition(id: 'm', name: 'Mét', symbol: 'm'),
        UnitDefinition(id: 'km', name: 'Kilômét', symbol: 'km'),
        UnitDefinition(id: 'cm', name: 'Centimét', symbol: 'cm'),
        UnitDefinition(id: 'mm', name: 'Milimét', symbol: 'mm'),
        UnitDefinition(id: 'inch', name: 'Inch', symbol: 'in'),
        UnitDefinition(id: 'ft', name: 'Foot (bước)', symbol: 'ft'),
        UnitDefinition(id: 'yd', name: 'Yard', symbol: 'yd'),
        UnitDefinition(id: 'mi', name: 'Dặm (Mile)', symbol: 'mi'),
      ],
    ),
    UnitCategory(
      type: CategoryType.weight,
      name: 'Khối lượng',
      icon: Icons.scale_rounded,
      color: Color(0xFF8B5CF6),
      units: [
        UnitDefinition(id: 'kg', name: 'Kilôgam', symbol: 'kg'),
        UnitDefinition(id: 'g', name: 'Gam', symbol: 'g'),
        UnitDefinition(id: 'mg', name: 'Miligam', symbol: 'mg'),
        UnitDefinition(id: 'lb', name: 'Pound', symbol: 'lb'),
        UnitDefinition(id: 'oz', name: 'Ounce', symbol: 'oz'),
        UnitDefinition(id: 'ton', name: 'Tấn', symbol: 't'),
      ],
    ),
    UnitCategory(
      type: CategoryType.speed,
      name: 'Tốc độ',
      icon: Icons.speed_rounded,
      color: Color(0xFF06B6D4),
      units: [
        UnitDefinition(id: 'kmh', name: 'Km / Giờ', symbol: 'km/h'),
        UnitDefinition(id: 'ms', name: 'Mét / Giây', symbol: 'm/s'),
        UnitDefinition(id: 'mph', name: 'Dặm / Giờ', symbol: 'mph'),
        UnitDefinition(id: 'knot', name: 'Hải lý / Giờ', symbol: 'kn'),
      ],
    ),
    UnitCategory(
      type: CategoryType.volume,
      name: 'Thể tích',
      icon: Icons.water_drop_rounded,
      color: Color(0xFF10B981),
      units: [
        UnitDefinition(id: 'l', name: 'Lít', symbol: 'L'),
        UnitDefinition(id: 'ml', name: 'Mililít', symbol: 'mL'),
        UnitDefinition(id: 'm3', name: 'Mét khối', symbol: 'm³'),
        UnitDefinition(id: 'gal', name: 'Gallon (Mỹ)', symbol: 'gal'),
        UnitDefinition(id: 'floz', name: 'Fluid Ounce', symbol: 'fl oz'),
      ],
    ),
  ];

  static double convert({
    required CategoryType category,
    required String fromUnit,
    required String toUnit,
    required double value,
  }) {
    if (fromUnit == toUnit) return value;

    switch (category) {
      case CategoryType.temperature:
        return _convertTemperature(fromUnit, toUnit, value);
      case CategoryType.length:
        return _convertLength(fromUnit, toUnit, value);
      case CategoryType.weight:
        return _convertWeight(fromUnit, toUnit, value);
      case CategoryType.speed:
        return _convertSpeed(fromUnit, toUnit, value);
      case CategoryType.volume:
        return _convertVolume(fromUnit, toUnit, value);
    }
  }

  static double _convertTemperature(String from, String to, double v) {
    // Convert to Celsius first
    double c;
    switch (from) {
      case 'c': c = v; break;
      case 'f': c = (v - 32) * 5 / 9; break;
      case 'k': c = v - 273.15; break;
      case 'r': c = (v - 491.67) * 5 / 9; break;
      default: c = v;
    }

    // Convert from Celsius to Target
    switch (to) {
      case 'c': return c;
      case 'f': return (c * 9 / 5) + 32;
      case 'k': return c + 273.15;
      case 'r': return (c + 273.15) * 9 / 5;
      default: return c;
    }
  }

  // Length in base: meters (m)
  static final Map<String, double> _lengthToBase = {
    'm': 1.0,
    'km': 1000.0,
    'cm': 0.01,
    'mm': 0.001,
    'inch': 0.0254,
    'ft': 0.3048,
    'yd': 0.9144,
    'mi': 1609.344,
  };

  static double _convertLength(String from, String to, double v) {
    final base = v * (_lengthToBase[from] ?? 1.0);
    return base / (_lengthToBase[to] ?? 1.0);
  }

  // Weight in base: kilograms (kg)
  static final Map<String, double> _weightToBase = {
    'kg': 1.0,
    'g': 0.001,
    'mg': 0.000001,
    'lb': 0.45359237,
    'oz': 0.028349523125,
    'ton': 1000.0,
  };

  static double _convertWeight(String from, String to, double v) {
    final base = v * (_weightToBase[from] ?? 1.0);
    return base / (_weightToBase[to] ?? 1.0);
  }

  // Speed in base: km/h
  static final Map<String, double> _speedToBase = {
    'kmh': 1.0,
    'ms': 3.6,
    'mph': 1.609344,
    'knot': 1.852,
  };

  static double _convertSpeed(String from, String to, double v) {
    final base = v * (_speedToBase[from] ?? 1.0);
    return base / (_speedToBase[to] ?? 1.0);
  }

  // Volume in base: liters (L)
  static final Map<String, double> _volumeToBase = {
    'l': 1.0,
    'ml': 0.001,
    'm3': 1000.0,
    'gal': 3.785411784,
    'floz': 0.0295735295625,
  };

  static double _convertVolume(String from, String to, double v) {
    final base = v * (_volumeToBase[from] ?? 1.0);
    return base / (_volumeToBase[to] ?? 1.0);
  }

  /// Evaluates the conversion and produces reasonable notifications and insights
  static SmartAlert? generateSmartAlert({
    required CategoryType category,
    required String fromUnit,
    required double inputValue,
    required String toUnit,
    required double resultValue,
  }) {
    if (category == CategoryType.temperature) {
      // Calculate Celsius value for standard checks
      final celsius = _convertTemperature(fromUnit, 'c', inputValue);

      if (celsius < -273.15) {
        return SmartAlert(
          title: 'Cảnh báo: Dưới độ 0 tuyệt đối!',
          message: 'Giá trị ${inputValue.toStringAsFixed(1)}${fromUnit.toUpperCase()} thấp hơn 0 Kelvin (-273.15°C). Đây là giới hạn dưới vật lý tuyệt đối của vũ trụ.',
          level: AlertLevel.critical,
          icon: Icons.ac_unit_rounded,
        );
      } else if ((celsius - (-273.15)).abs() < 0.05) {
        return SmartAlert(
          title: 'Độ 0 tuyệt đối (Absolute Zero)',
          message: 'Tại 0 Kelvin (-273.15°C), toàn bộ chuyển động nhiệt của phân tử và nguyên tử dừng lại hoàn toàn.',
          level: AlertLevel.info,
          icon: Icons.science_rounded,
        );
      } else if ((celsius - 0.0).abs() < 0.1) {
        return SmartAlert(
          title: 'Điểm đóng băng của nước tinh khiết',
          message: '0°C tương đương 32°F hoặc 273.15K tại áp suất khí quyển 1 atm.',
          level: AlertLevel.info,
          icon: Icons.severe_cold_rounded,
        );
      } else if (celsius >= 36.5 && celsius <= 37.5) {
        return SmartAlert(
          title: 'Nhiệt độ thân nhiệt người bình thường',
          message: 'Khoảng 36.5°C - 37.2°C (97.7°F - 99.0°F) là mức thân nhiệt tiêu chuẩn khỏe mạnh của con người.',
          level: AlertLevel.success,
          icon: Icons.favorite_rounded,
        );
      } else if (celsius > 37.5 && celsius <= 38.5) {
        return SmartAlert(
          title: 'Lưu ý: Có dấu hiệu sốt nhẹ',
          message: 'Thân nhiệt từ 37.5°C đến 38.5°C cảnh báo phản ứng miễn dịch hoặc mệt mỏi nhẹ.',
          level: AlertLevel.warning,
          icon: Icons.warning_amber_rounded,
        );
      } else if (celsius > 38.5 && celsius <= 42.0) {
        return SmartAlert(
          title: 'Cảnh báo: Sốt cao nguy hiểm!',
          message: 'Nếu đây là thân nhiệt người (> 38.5°C), cần có biện pháp hạ sốt hoặc tư vấn y tế ngay lập tức.',
          level: AlertLevel.critical,
          icon: Icons.local_hospital_rounded,
        );
      } else if ((celsius - 100.0).abs() < 0.5) {
        return SmartAlert(
          title: 'Điểm sôi của nước tinh khiết',
          message: '100°C tương đương 212°F hoặc 373.15K ở mực nước biển chuẩn.',
          level: AlertLevel.info,
          icon: Icons.water_drop_rounded,
        );
      } else if (celsius > 50.0 && celsius < 100.0) {
        return SmartAlert(
          title: 'Cảnh báo nhiệt độ môi trường cực cao',
          message: 'Nhiệt độ trên 50°C có thể gây bỏng da, sốc nhiệt và nguy hiểm tính mạng trong thời gian ngắn.',
          level: AlertLevel.warning,
          icon: Icons.wb_sunny_rounded,
        );
      }
    } else {
      // Non-temperature categories
      if (inputValue < 0) {
        return SmartAlert(
          title: 'Cảnh báo giá trị âm',
          message: 'Các đại lượng vật lý thực tế như khoảng cách, khối lượng và thể tích không thể mang giá trị âm.',
          level: AlertLevel.warning,
          icon: Icons.error_outline_rounded,
        );
      }

      if (category == CategoryType.speed) {
        final kmh = _convertSpeed(fromUnit, 'kmh', inputValue);
        if (kmh >= 1235) {
          return SmartAlert(
            title: 'Tốc độ siêu thanh (Mach 1+)',
            message: 'Vận tốc $kmh km/h đã vượt qua ranh giới vận tốc âm thanh trong không khí (khoảng 343 m/s).',
            level: AlertLevel.info,
            icon: Icons.flight_takeoff_rounded,
          );
        } else if (kmh > 120 && kmh <= 200) {
          return SmartAlert(
            title: 'Lưu ý tốc độ đường bộ',
            message: 'Vận tốc vượt quá giới hạn tối đa cho phép trên cao tốc tại Việt Nam (thường là 120 km/h).',
            level: AlertLevel.warning,
            icon: Icons.speed_rounded,
          );
        }
      }
    }

    return null;
  }
}
