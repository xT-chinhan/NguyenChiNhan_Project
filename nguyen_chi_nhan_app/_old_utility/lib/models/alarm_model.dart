import 'package:flutter/material.dart';

class AlarmModel {
  final String id;
  TimeOfDay time;
  String label;
  bool isEnabled;
  String soundName;
  List<int> repeatDays; // 1 = Monday, 7 = Sunday, empty = once
  bool isSnoozed;

  AlarmModel({
    required this.id,
    required this.time,
    this.label = 'Báo thức',
    this.isEnabled = true,
    this.soundName = 'Chuông cổ điển',
    List<int>? repeatDays,
    this.isSnoozed = false,
  }) : repeatDays = repeatDays ?? [];

  String get formattedTime {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get period => time.hour >= 12 ? 'PM' : 'AM';

  String get repeatText {
    if (repeatDays.isEmpty) return 'Một lần';
    if (repeatDays.length == 7) return 'Mỗi ngày';
    if (repeatDays.length == 5 && !repeatDays.contains(6) && !repeatDays.contains(7)) {
      return 'Thứ 2 - Thứ 6';
    }
    const dayNames = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return repeatDays.map((d) => dayNames[d - 1]).join(', ');
  }

  AlarmModel copyWith({
    String? id,
    TimeOfDay? time,
    String? label,
    bool? isEnabled,
    String? soundName,
    List<int>? repeatDays,
    bool? isSnoozed,
  }) {
    return AlarmModel(
      id: id ?? this.id,
      time: time ?? this.time,
      label: label ?? this.label,
      isEnabled: isEnabled ?? this.isEnabled,
      soundName: soundName ?? this.soundName,
      repeatDays: repeatDays ?? List.from(this.repeatDays),
      isSnoozed: isSnoozed ?? this.isSnoozed,
    );
  }
}
