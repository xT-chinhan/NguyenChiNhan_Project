import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_chi_nhan_app/models/alarm_model.dart';
import 'package:nguyen_chi_nhan_app/services/alarm_manager.dart';
import 'package:nguyen_chi_nhan_app/screens/alarm/widgets/alarm_ring_dialog.dart';
import 'package:nguyen_chi_nhan_app/screens/alarm/alarm_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Module 3: AlarmModel Unit Tests', () {
    test('Formats time with leading zeros and period', () {
      final alarmMorning = AlarmModel(
        id: 'a1',
        time: const TimeOfDay(hour: 7, minute: 5),
        label: 'Dậy sớm',
      );
      expect(alarmMorning.formattedTime, '07:05');
      expect(alarmMorning.period, 'AM');

      final alarmEvening = AlarmModel(
        id: 'a2',
        time: const TimeOfDay(hour: 19, minute: 45),
        label: 'Tối',
      );
      expect(alarmEvening.formattedTime, '19:45');
      expect(alarmEvening.period, 'PM');
    });

    test('Formats repeatText correctly for different schedules', () {
      final once = AlarmModel(id: '1', time: const TimeOfDay(hour: 6, minute: 0), repeatDays: []);
      expect(once.repeatText, 'Một lần');

      final everyday = AlarmModel(
        id: '2',
        time: const TimeOfDay(hour: 6, minute: 0),
        repeatDays: [1, 2, 3, 4, 5, 6, 7],
      );
      expect(everyday.repeatText, 'Mỗi ngày');

      final weekdays = AlarmModel(
        id: '3',
        time: const TimeOfDay(hour: 6, minute: 0),
        repeatDays: [1, 2, 3, 4, 5],
      );
      expect(weekdays.repeatText, 'Thứ 2 - Thứ 6');

      final custom = AlarmModel(
        id: '4',
        time: const TimeOfDay(hour: 6, minute: 0),
        repeatDays: [1, 3, 5],
      );
      expect(custom.repeatText, 'T2, T4, T6');
    });

    test('copyWith duplicates and overrides fields', () {
      final initial = AlarmModel(
        id: '10',
        time: const TimeOfDay(hour: 8, minute: 0),
        label: 'Họp',
        isEnabled: true,
      );
      final modified = initial.copyWith(isEnabled: false, label: 'Họp dời');
      expect(modified.id, '10');
      expect(modified.isEnabled, false);
      expect(modified.label, 'Họp dời');
      expect(modified.time, const TimeOfDay(hour: 8, minute: 0));
    });
  });

  group('Module 3: AlarmManager Logic Tests', () {
    final manager = AlarmManager.instance;

    test('Adds a new alarm with specific TimePicker parameters', () {
      final initialCount = manager.alarmsNotifier.value.length;
      manager.addAlarm(
        time: const TimeOfDay(hour: 6, minute: 15),
        label: 'Tập thể dục',
        repeatDays: [1, 2, 3],
      );

      final alarms = manager.alarmsNotifier.value;
      expect(alarms.length, initialCount + 1);
      final added = alarms.last;
      expect(added.time.hour, 6);
      expect(added.time.minute, 15);
      expect(added.label, 'Tập thể dục');
      expect(added.repeatDays, [1, 2, 3]);
      expect(added.isEnabled, true);
    });

    test('Toggles alarm on and off', () {
      final alarms = manager.alarmsNotifier.value;
      final target = alarms.first;
      final originalState = target.isEnabled;

      manager.toggleAlarm(target.id, !originalState);
      final updated = manager.alarmsNotifier.value.firstWhere((a) => a.id == target.id);
      expect(updated.isEnabled, !originalState);

      // Restore
      manager.toggleAlarm(target.id, originalState);
    });

    test('Deletes an alarm', () {
      manager.addAlarm(
        time: const TimeOfDay(hour: 12, minute: 0),
        label: 'Ăn trưa để xóa',
      );
      final added = manager.alarmsNotifier.value.last;
      final countBefore = manager.alarmsNotifier.value.length;

      manager.deleteAlarm(added.id);
      expect(manager.alarmsNotifier.value.length, countBefore - 1);
      expect(manager.alarmsNotifier.value.any((a) => a.id == added.id), false);
    });

    test('Test trigger alarm activates ringingAlarmNotifier', () {
      final target = manager.alarmsNotifier.value.first;
      manager.testTriggerAlarm(target);
      expect(manager.ringingAlarmNotifier.value, isNotNull);
      expect(manager.ringingAlarmNotifier.value?.id, target.id);

      manager.dismissRinging();
      expect(manager.ringingAlarmNotifier.value, isNull);
    });

    test('Snooze creates a snoozed alarm 5 minutes later and resets ringing', () {
      final target = manager.alarmsNotifier.value.first;
      manager.testTriggerAlarm(target);

      final countBefore = manager.alarmsNotifier.value.length;
      manager.snoozeRinging(minutes: 5);

      expect(manager.ringingAlarmNotifier.value, isNull);
      expect(manager.alarmsNotifier.value.length, countBefore + 1);
      final snoozed = manager.alarmsNotifier.value.first;
      expect(snoozed.isSnoozed, true);
      expect(snoozed.label, contains('Báo lại 5 phút'));
    });
  });

  group('Module 3: AlarmRingDialog Widget Tests', () {
    testWidgets('Renders alarm ring dialog with Snooze and Dismiss buttons', (tester) async {
      final testAlarm = AlarmModel(
        id: 'ring_1',
        time: const TimeOfDay(hour: 6, minute: 30),
        label: 'Chuông báo thức buổi sáng',
        isEnabled: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlarmRingDialog(alarm: testAlarm),
          ),
        ),
      );

      expect(find.text('BÁO THỨC ĐANG REO!'), findsOneWidget);
      expect(find.text('06:30'), findsOneWidget);
      expect(find.text('Chuông báo thức buổi sáng'), findsOneWidget);
      expect(find.text('Báo lại (5p)'), findsOneWidget);
      expect(find.text('Tắt chuông'), findsOneWidget);
    });
  });

  group('Module 3: AlarmScreen UI Widget Tests', () {
    testWidgets('Renders AlarmScreen with real-time clock and alarm list', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AlarmScreen(),
        ),
      );

      await tester.pump();

      expect(find.text('Đồng Hồ Báo Thức'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Thêm Báo Thức'), findsOneWidget);
      expect(find.textContaining('Danh Sách Báo Thức'), findsOneWidget);
    });
  });
}
