import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/lap_record.dart';
import 'audio_alarm_service.dart';

class StopwatchService {
  static final StopwatchService instance = StopwatchService._internal();
  StopwatchService._internal();

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;

  final ValueNotifier<Duration> elapsedNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<LapRecord>> lapsNotifier = ValueNotifier<List<LapRecord>>([]);

  Duration get elapsed => elapsedNotifier.value;
  bool get isRunning => isRunningNotifier.value;
  List<LapRecord> get laps => lapsNotifier.value;

  Duration _lastLapTotalTime = Duration.zero;

  void start() {
    if (_stopwatch.isRunning) return;
    _stopwatch.start();
    isRunningNotifier.value = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      elapsedNotifier.value = _stopwatch.elapsed;
    });
  }

  void pause() {
    if (!_stopwatch.isRunning) return;
    _stopwatch.stop();
    _timer?.cancel();
    isRunningNotifier.value = false;
    elapsedNotifier.value = _stopwatch.elapsed;
  }

  void reset() {
    _stopwatch.stop();
    _stopwatch.reset();
    _timer?.cancel();
    _lastLapTotalTime = Duration.zero;
    isRunningNotifier.value = false;
    elapsedNotifier.value = Duration.zero;
    lapsNotifier.value = [];
  }

  void recordLap() {
    if (!_stopwatch.isRunning && elapsed == Duration.zero) return;

    final currentTotal = _stopwatch.elapsed;
    final lapDuration = currentTotal - _lastLapTotalTime;
    _lastLapTotalTime = currentTotal;

    final newLap = LapRecord(
      lapNumber: lapsNotifier.value.length + 1,
      lapTime: lapDuration,
      totalTime: currentTotal,
    );

    lapsNotifier.value = [newLap, ...lapsNotifier.value];
    AudioAlarmService.instance.playBeep();
  }

  int? get fastestLapNumber {
    final list = lapsNotifier.value;
    if (list.length < 2) return null;
    LapRecord minRecord = list.first;
    for (final l in list) {
      if (l.lapTime < minRecord.lapTime) {
        minRecord = l;
      }
    }
    if (list.every((l) => l.lapTime == minRecord.lapTime)) return null;
    return minRecord.lapNumber;
  }

  int? get slowestLapNumber {
    final list = lapsNotifier.value;
    if (list.length < 2) return null;
    LapRecord maxRecord = list.first;
    for (final l in list) {
      if (l.lapTime > maxRecord.lapTime) {
        maxRecord = l;
      }
    }
    if (list.every((l) => l.lapTime == maxRecord.lapTime)) return null;
    return maxRecord.lapNumber;
  }
}
