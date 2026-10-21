import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/lap_record.dart';
import '../../services/stopwatch_service.dart';
import '../../theme/app_theme.dart';

class StopwatchScreen extends StatelessWidget {
  const StopwatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stopwatch = StopwatchService.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đồng Hồ Bấm Giờ'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            const SizedBox(height: 12),

            // Circular Stopwatch Face (Hybrid Kim & Số)
            Center(
              child: ValueListenableBuilder<Duration>(
                valueListenable: stopwatch.elapsedNotifier,
                builder: (context, elapsed, child) {
                  final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
                  final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
                  final hundredths = (elapsed.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
                  final hours = elapsed.inHours;

                  return Container(
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.cardColor,
                      border: Border.all(
                        color: AppTheme.stopwatchColor.withAlpha(80),
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.stopwatchColor.withAlpha(30),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Analog dial with tick marks & sweeping needle (kim quét)
                        CustomPaint(
                          size: const Size(210, 210),
                          painter: _StopwatchDialPainter(
                            elapsed: elapsed,
                            color: AppTheme.stopwatchColor,
                            isDark: theme.brightness == Brightness.dark,
                          ),
                        ),
                        // Digital Clock Display (số điện tử)
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (hours > 0)
                              Text(
                                '${hours.toString().padLeft(2, '0')} giờ',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: theme.hintColor,
                                ),
                              ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '$minutes:$seconds',
                                    style: const TextStyle(
                                      fontSize: 40,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'monospace',
                                      letterSpacing: -1,
                                    ),
                                  ),
                                  Text(
                                    '.$hundredths',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                      color: AppTheme.stopwatchColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            ValueListenableBuilder<bool>(
                              valueListenable: stopwatch.isRunningNotifier,
                              builder: (context, isRunning, _) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isRunning
                                        ? Colors.green.withAlpha(30)
                                        : Colors.grey.withAlpha(30),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isRunning ? 'ĐANG CHẠY' : (elapsed == Duration.zero ? 'SẴN SÀNG' : 'TẠM DỪNG'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isRunning ? Colors.green : Colors.grey,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Controls Bar
            ValueListenableBuilder<bool>(
              valueListenable: stopwatch.isRunningNotifier,
              builder: (context, isRunning, child) {
                return ValueListenableBuilder<Duration>(
                  valueListenable: stopwatch.elapsedNotifier,
                  builder: (context, elapsed, _) {
                    final hasStarted = elapsed > Duration.zero;

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Left Button (Lap or Reset)
                        if (!isRunning && hasStarted)
                          _buildCircleButton(
                            label: 'Đặt lại',
                            icon: Icons.refresh_rounded,
                            color: Colors.grey,
                            onPressed: () => stopwatch.reset(),
                          )
                        else
                          _buildCircleButton(
                            label: 'Vòng (Lap)',
                            icon: Icons.flag_rounded,
                            color: isRunning ? AppTheme.stopwatchColor : Colors.grey.withAlpha(100),
                            onPressed: isRunning ? () => stopwatch.recordLap() : null,
                          ),

                        // Center Big Button (Start / Pause / Resume)
                        if (!isRunning)
                          _buildCircleButton(
                            label: hasStarted ? 'Tiếp tục' : 'Bắt đầu',
                            icon: Icons.play_arrow_rounded,
                            color: Colors.green,
                            isPrimary: true,
                            onPressed: () => stopwatch.start(),
                          )
                        else
                          _buildCircleButton(
                            label: 'Tạm dừng',
                            icon: Icons.pause_rounded,
                            color: Colors.orange,
                            isPrimary: true,
                            onPressed: () => stopwatch.pause(),
                          ),
                      ],
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 16),

            // Lap List Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Lịch Sử Vòng (Laps)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                ValueListenableBuilder<List<LapRecord>>(
                  valueListenable: stopwatch.lapsNotifier,
                  builder: (context, laps, _) {
                    return Text(
                      '${laps.length} vòng',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.stopwatchColor),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Lap Table Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.dividerColor.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 60, child: Text('Vòng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(child: Text('Thời gian vòng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  Text('Tổng cộng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Lap List View
            Expanded(
              child: ValueListenableBuilder<List<LapRecord>>(
                valueListenable: stopwatch.lapsNotifier,
                builder: (context, laps, child) {
                  if (laps.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_outlined, size: 36, color: theme.hintColor.withAlpha(100)),
                            const SizedBox(height: 6),
                            Text(
                              'Chưa có vòng nào được ghi',
                              style: TextStyle(color: theme.hintColor, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bấm nút "Vòng (Lap)" khi đang chạy để ghi thời gian',
                              style: TextStyle(color: theme.hintColor, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final fastestLap = stopwatch.fastestLapNumber;
                  final slowestLap = stopwatch.slowestLapNumber;

                  return ListView.separated(
                    itemCount: laps.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final lap = laps[index];
                      final isFastest = fastestLap != null && lap.lapNumber == fastestLap;
                      final isSlowest = slowestLap != null && lap.lapNumber == slowestLap;

                      Color? rowColor;
                      Widget? badge;

                      if (isFastest) {
                        rowColor = Colors.green.withAlpha(20);
                        badge = Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Nhanh nhất', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        );
                      } else if (isSlowest) {
                        rowColor = Colors.red.withAlpha(20);
                        badge = Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Chậm nhất', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        );
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: rowColor ?? theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isFastest
                                ? Colors.green.withAlpha(100)
                                : (isSlowest ? Colors.redAccent.withAlpha(100) : theme.dividerColor.withAlpha(30)),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 60,
                              child: Text(
                                '#${lap.lapNumber.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                              ),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    lap.formattedLapTime,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'monospace',
                                      color: isFastest ? Colors.green : (isSlowest ? Colors.redAccent : null),
                                    ),
                                  ),
                                  if (badge != null) ...[
                                    const SizedBox(width: 8),
                                    badge,
                                  ],
                                ],
                              ),
                            ),
                            Text(
                              lap.formattedTotalTime,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: theme.hintColor,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool isPrimary = false,
  }) {
    final size = isPrimary ? 80.0 : 70.0;
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                backgroundColor: isPrimary ? color : color.withAlpha(30),
                foregroundColor: isPrimary ? Colors.white : color,
                elevation: isPrimary ? 4 : 0,
              ),
              onPressed: onPressed,
              child: Icon(icon, size: isPrimary ? 36 : 28),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: onPressed != null ? null : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

class _StopwatchDialPainter extends CustomPainter {
  final Duration elapsed;
  final Color color;
  final bool isDark;

  _StopwatchDialPainter({
    required this.elapsed,
    required this.color,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw dial tick marks (60 marks, bold every 5)
    final tickPaint = Paint()..strokeCap = StrokeCap.round;

    for (int i = 0; i < 60; i++) {
      final isMajor = i % 5 == 0;
      final angle = (i * 6) * math.pi / 180.0 - math.pi / 2;
      final tickLength = isMajor ? 10.0 : 5.0;
      final innerR = radius - 8.0 - tickLength;
      final outerR = radius - 8.0;

      tickPaint.color = isMajor
          ? color.withAlpha(isDark ? 200 : 180)
          : (isDark ? Colors.white24 : Colors.black12);
      tickPaint.strokeWidth = isMajor ? 2.5 : 1.2;

      final start = Offset(center.dx + innerR * math.cos(angle), center.dy + innerR * math.sin(angle));
      final end = Offset(center.dx + outerR * math.cos(angle), center.dy + outerR * math.sin(angle));
      canvas.drawLine(start, end, tickPaint);
    }

    // Draw circular progress arc for seconds
    final progressAngle = (elapsed.inMilliseconds % 60000) / 60000.0 * 2 * math.pi;
    final arcPaint = Paint()
      ..color = color.withAlpha(50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 4),
      -math.pi / 2,
      progressAngle,
      false,
      arcPaint,
    );

    // Draw sweeping analog needle (kim quét)
    final needleAngle = progressAngle - math.pi / 2;
    final needleLength = radius - 26.0;

    final needlePaint = Paint()
      ..color = color.withAlpha(190)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final shadowPaint = Paint()
      ..color = color.withAlpha(70)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final tip = Offset(
      center.dx + needleLength * math.cos(needleAngle),
      center.dy + needleLength * math.sin(needleAngle),
    );
    final tail = Offset(
      center.dx - 14 * math.cos(needleAngle),
      center.dy - 14 * math.sin(needleAngle),
    );

    canvas.drawLine(tail, tip, shadowPaint);
    canvas.drawLine(tail, tip, needlePaint);

    // Needle tip dot
    final tipDotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(tip, 3.5, tipDotPaint);

    // Center pivot
    final pivotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 4.0, pivotPaint);
  }

  @override
  bool shouldRepaint(covariant _StopwatchDialPainter oldDelegate) {
    return oldDelegate.elapsed != elapsed || oldDelegate.color != color || oldDelegate.isDark != isDark;
  }
}

