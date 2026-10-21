class LapRecord {
  final int lapNumber;
  final Duration lapTime;
  final Duration totalTime;

  LapRecord({
    required this.lapNumber,
    required this.lapTime,
    required this.totalTime,
  });

  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final milliseconds = (duration.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    final hours = duration.inHours;

    if (hours > 0) {
      final hoursStr = hours.toString().padLeft(2, '0');
      return '$hoursStr:$minutes:$seconds.$milliseconds';
    }
    return '$minutes:$seconds.$milliseconds';
  }

  String get formattedLapTime => formatDuration(lapTime);
  String get formattedTotalTime => formatDuration(totalTime);
}
