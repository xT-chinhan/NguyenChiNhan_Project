import 'package:flutter/material.dart';

enum VoiceCommandType {
  startStopwatch,
  stopStopwatch,
  resetStopwatch,
  lapStopwatch,
  setAlarm,
  cancelAlarm,
  unknown,
}

class VoiceCommandResult {
  final VoiceCommandType type;
  final String rawSpokenText;
  final String responseMessage;
  final bool isSuccess;
  final TimeOfDay? alarmTime;
  final DateTime timestamp;

  VoiceCommandResult({
    required this.type,
    required this.rawSpokenText,
    required this.responseMessage,
    required this.isSuccess,
    this.alarmTime,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
