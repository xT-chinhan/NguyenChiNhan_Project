import 'dart:async';
import 'package:flutter/material.dart';
import '../models/alarm_model.dart';
import 'audio_alarm_service.dart';

class AlarmManager {
  static final AlarmManager instance = AlarmManager._internal();
  AlarmManager._internal() {
    _initDefaults();
    _startClockCheck();
  }

  final ValueNotifier<List<AlarmModel>> alarmsNotifier = ValueNotifier<List<AlarmModel>>([]);
  final ValueNotifier<AlarmModel?> ringingAlarmNotifier = ValueNotifier<AlarmModel?>(null);

  List<AlarmModel> get alarms => alarmsNotifier.value;

  Timer? _clockTimer;
  String _lastTriggeredMinuteKey = '';

  void _initDefaults() {
    final now = DateTime.now();
    // Create an alarm 1 minute in the future so user can test easily
    final futureTime = now.add(const Duration(minutes: 2));

    alarmsNotifier.value = [
      AlarmModel(
        id: '1',
        time: TimeOfDay(hour: futureTime.hour, minute: futureTime.minute),
        label: 'Chuông thử nghiệm (2 phút nữa)',
        isEnabled: true,
        repeatDays: [],
      ),
      AlarmModel(
        id: '2',
        time: const TimeOfDay(hour: 7, minute: 0),
        label: 'Thức dậy buổi sáng',
        isEnabled: false,
        repeatDays: [1, 2, 3, 4, 5],
      ),
      AlarmModel(
        id: '3',
        time: const TimeOfDay(hour: 22, minute: 30),
        label: 'Đi ngủ đúng giờ',
        isEnabled: false,
        repeatDays: [1, 2, 3, 4, 5, 6, 7],
      ),
    ];
  }

  void _startClockCheck() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkAlarms();
    });
  }

  void stopClockCheck() {
    _clockTimer?.cancel();
    _clockTimer = null;
  }

  void startClockCheck() {
    _startClockCheck();
  }

  void _checkAlarms() {
    final now = DateTime.now();
    final currentMinuteKey = '${now.year}_${now.month}_${now.day}_${now.hour}_${now.minute}';
    if (_lastTriggeredMinuteKey == currentMinuteKey) return;

    final currentWeekday = now.weekday; // 1 = Monday ... 7 = Sunday

    for (final alarm in alarmsNotifier.value) {
      if (!alarm.isEnabled) continue;

      final matchTime = alarm.time.hour == now.hour && alarm.time.minute == now.minute;
      if (!matchTime) continue;

      // Check repeat day
      final matchDay = alarm.repeatDays.isEmpty || alarm.repeatDays.contains(currentWeekday);
      if (matchDay) {
        _lastTriggeredMinuteKey = currentMinuteKey;
        _triggerAlarm(alarm);
        break;
      }
    }
  }

  void _triggerAlarm(AlarmModel alarm) {
    if (ringingAlarmNotifier.value != null) {
      ringingAlarmNotifier.value = null;
    }
    ringingAlarmNotifier.value = alarm;
    AudioAlarmService.instance.startAlarmSound();
  }

  /// Manually trigger test alarm for demonstration
  void testTriggerAlarm(AlarmModel alarm) {
    if (ringingAlarmNotifier.value != null) {
      dismissRinging();
    }
    _triggerAlarm(alarm);
  }

  void dismissRinging() {
    AudioAlarmService.instance.stopAlarmSound();
    final current = ringingAlarmNotifier.value;
    if (current != null && current.repeatDays.isEmpty) {
      // Disable one-time alarm
      toggleAlarm(current.id, false);
    }
    ringingAlarmNotifier.value = null;
  }

  void snoozeRinging({int minutes = 5}) {
    AudioAlarmService.instance.stopAlarmSound();
    final current = ringingAlarmNotifier.value;
    if (current != null) {
      final now = DateTime.now().add(Duration(minutes: minutes));
      final snoozedAlarm = AlarmModel(
        id: 'snooze_${DateTime.now().millisecondsSinceEpoch}',
        time: TimeOfDay(hour: now.hour, minute: now.minute),
        label: '${current.label} (Báo lại $minutes phút)',
        isEnabled: true,
        isSnoozed: true,
      );
      alarmsNotifier.value = [snoozedAlarm, ...alarmsNotifier.value];
    }
    ringingAlarmNotifier.value = null;
  }

  void addAlarm({
    required TimeOfDay time,
    required String label,
    List<int>? repeatDays,
    String soundName = 'Chuông cổ điển',
  }) {
    final newAlarm = AlarmModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      time: time,
      label: label.isEmpty ? 'Báo thức' : label,
      isEnabled: true,
      soundName: soundName,
      repeatDays: repeatDays ?? [],
    );
    alarmsNotifier.value = [...alarmsNotifier.value, newAlarm];
    AudioAlarmService.instance.playBeep();
  }

  void toggleAlarm(String id, bool isEnabled) {
    alarmsNotifier.value = alarmsNotifier.value.map((a) {
      if (a.id == id) {
        return a.copyWith(isEnabled: isEnabled);
      }
      return a;
    }).toList();
  }

  void deleteAlarm(String id) {
    alarmsNotifier.value = alarmsNotifier.value.where((a) => a.id != id).toList();
  }

  void dispose() {
    _clockTimer?.cancel();
  }
}
