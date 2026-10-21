import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_chi_nhan_app/models/unit_category.dart';
import 'package:nguyen_chi_nhan_app/models/voice_command.dart';
import 'package:nguyen_chi_nhan_app/services/voice_service.dart';
import 'package:nguyen_chi_nhan_app/services/stopwatch_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Module 1: Unit Converter & Smart Alerts Tests', () {
    test('Converts Celsius to Fahrenheit correctly', () {
      final f = UnitCategory.convert(
        category: CategoryType.temperature,
        fromUnit: 'c',
        toUnit: 'f',
        value: 100,
      );
      expect(f, closeTo(212.0, 0.01));
    });

    test('Converts Celsius to Kelvin correctly', () {
      final k = UnitCategory.convert(
        category: CategoryType.temperature,
        fromUnit: 'c',
        toUnit: 'k',
        value: 0,
      );
      expect(k, closeTo(273.15, 0.01));
    });

    test('Generates Critical Alert when temperature is below 0 Kelvin', () {
      final alert = UnitCategory.generateSmartAlert(
        category: CategoryType.temperature,
        fromUnit: 'c',
        inputValue: -280,
        toUnit: 'k',
        resultValue: -6.85,
      );
      expect(alert, isNotNull);
      expect(alert!.level, AlertLevel.critical);
      expect(alert.title, contains('tuyệt đối'));
    });

    test('Generates Normal Body Temp Alert at 37°C', () {
      final alert = UnitCategory.generateSmartAlert(
        category: CategoryType.temperature,
        fromUnit: 'c',
        inputValue: 37,
        toUnit: 'f',
        resultValue: 98.6,
      );
      expect(alert, isNotNull);
      expect(alert!.level, AlertLevel.success);
      expect(alert.title, contains('thân nhiệt'));
    });

    test('Generates Boiling Point Alert at 100°C', () {
      final alert = UnitCategory.generateSmartAlert(
        category: CategoryType.temperature,
        fromUnit: 'c',
        inputValue: 100,
        toUnit: 'f',
        resultValue: 212,
      );
      expect(alert, isNotNull);
      expect(alert!.title, contains('Điểm sôi'));
    });
  });

  group('Module 4: Stopwatch Service Tests', () {
    test('Stopwatch start, pause, reset behavior', () {
      final sw = StopwatchService.instance;
      sw.reset();
      expect(sw.isRunning, false);
      expect(sw.elapsed, Duration.zero);

      sw.start();
      expect(sw.isRunning, true);

      sw.pause();
      expect(sw.isRunning, false);

      sw.reset();
      expect(sw.elapsed, Duration.zero);
      expect(sw.laps.isEmpty, true);
    });
  });

  group('Module 5: Voice Vietnamese NLP Parser Tests', () {
    test('Parses "bắt đầu bấm giờ" into startStopwatch', () {
      final res = VoiceService.instance.processVoiceCommand('bắt đầu bấm giờ');
      expect(res.type, VoiceCommandType.startStopwatch);
      expect(res.isSuccess, true);
    });

    test('Parses "đặt báo thức lúc 7 giờ 30" into setAlarm with 07:30', () {
      final res = VoiceService.instance.processVoiceCommand('đặt báo thức lúc 7 giờ 30');
      expect(res.type, VoiceCommandType.setAlarm);
      expect(res.isSuccess, true);
      expect(res.alarmTime?.hour, 7);
      expect(res.alarmTime?.minute, 30);
    });

    test('Parses "hẹn giờ sau 15 phút" relative alarm', () {
      final res = VoiceService.instance.processVoiceCommand('hẹn giờ sau 15 phút');
      expect(res.type, VoiceCommandType.setAlarm);
      expect(res.isSuccess, true);
    });
  });
}
