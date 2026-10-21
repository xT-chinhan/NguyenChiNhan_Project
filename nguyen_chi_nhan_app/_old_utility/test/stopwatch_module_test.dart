import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_chi_nhan_app/models/lap_record.dart';
import 'package:nguyen_chi_nhan_app/services/stopwatch_service.dart';
import 'package:nguyen_chi_nhan_app/screens/stopwatch/stopwatch_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Module 4: LapRecord Model Unit Tests', () {
    test('Formats duration correctly without hours', () {
      const dur = Duration(minutes: 1, seconds: 23, milliseconds: 456);
      expect(LapRecord.formatDuration(dur), '01:23.45');
    });

    test('Formats duration correctly with hours', () {
      const dur = Duration(hours: 2, minutes: 15, seconds: 30, milliseconds: 80);
      expect(LapRecord.formatDuration(dur), '02:15:30.08');
    });

    test('Formats zero duration correctly', () {
      expect(LapRecord.formatDuration(Duration.zero), '00:00.00');
    });
  });

  group('Module 4: StopwatchService Unit Tests', () {
    final sw = StopwatchService.instance;

    setUp(() {
      sw.reset();
    });

    test('Start, pause, and reset transition states accurately', () {
      expect(sw.isRunning, false);
      expect(sw.elapsed, Duration.zero);

      sw.start();
      expect(sw.isRunning, true);

      sw.pause();
      expect(sw.isRunning, false);

      sw.reset();
      expect(sw.isRunning, false);
      expect(sw.elapsed, Duration.zero);
      expect(sw.laps.isEmpty, true);
    });

    test('Calculates fastest and slowest laps accurately', () {
      // Manually set laps in lapsNotifier for deterministic test
      final lap1 = LapRecord(
        lapNumber: 1,
        lapTime: const Duration(seconds: 15),
        totalTime: const Duration(seconds: 15),
      );
      final lap2 = LapRecord(
        lapNumber: 2,
        lapTime: const Duration(seconds: 10), // fastest
        totalTime: const Duration(seconds: 25),
      );
      final lap3 = LapRecord(
        lapNumber: 3,
        lapTime: const Duration(seconds: 20), // slowest
        totalTime: const Duration(seconds: 45),
      );

      sw.lapsNotifier.value = [lap3, lap2, lap1];

      expect(sw.fastestLapNumber, 2);
      expect(sw.slowestLapNumber, 3);
    });

    test('Returns null for fastest and slowest when fewer than 2 laps', () {
      final lap1 = LapRecord(
        lapNumber: 1,
        lapTime: const Duration(seconds: 10),
        totalTime: const Duration(seconds: 10),
      );
      sw.lapsNotifier.value = [lap1];

      expect(sw.fastestLapNumber, isNull);
      expect(sw.slowestLapNumber, isNull);
    });

    test('Returns null when all laps have identical time', () {
      final lap1 = LapRecord(
        lapNumber: 1,
        lapTime: const Duration(seconds: 10),
        totalTime: const Duration(seconds: 10),
      );
      final lap2 = LapRecord(
        lapNumber: 2,
        lapTime: const Duration(seconds: 10),
        totalTime: const Duration(seconds: 20),
      );
      sw.lapsNotifier.value = [lap2, lap1];

      expect(sw.fastestLapNumber, isNull);
      expect(sw.slowestLapNumber, isNull);
    });
  });

  group('Module 4: StopwatchScreen UI Widget Tests', () {
    final sw = StopwatchService.instance;

    setUp(() {
      sw.reset();
    });

    testWidgets('Renders initial stopwatch state with 00:00.00 and Bắt đầu button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: StopwatchScreen(),
        ),
      );

      expect(find.text('Đồng Hồ Bấm Giờ'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('.00'), findsOneWidget);
      expect(find.text('SẴN SÀNG'), findsOneWidget);
      expect(find.text('Bắt đầu'), findsOneWidget);
      expect(find.text('Vòng (Lap)'), findsOneWidget);
    });

    testWidgets('Toggles control buttons between Bắt đầu, Tạm dừng, Tiếp tục, Đặt lại', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: StopwatchScreen(),
        ),
      );

      // 1. Initial: Start button
      expect(find.text('Bắt đầu'), findsOneWidget);

      // 2. Click Start -> switches to Pause (Tạm dừng)
      await tester.tap(find.text('Bắt đầu'));
      await tester.pump();

      expect(sw.isRunning, true);
      expect(find.text('Tạm dừng'), findsOneWidget);
      expect(find.text('ĐANG CHẠY'), findsOneWidget);

      // 3. Click Pause -> switches to Resume (Tiếp tục) and Reset (Đặt lại)
      await tester.tap(find.text('Tạm dừng'));
      await tester.pump();

      expect(sw.isRunning, false);
      expect(find.text('Tiếp tục'), findsOneWidget);
      expect(find.text('Đặt lại'), findsOneWidget);

      // 4. Click Reset -> back to initial state
      await tester.tap(find.text('Đặt lại'));
      await tester.pump();

      expect(sw.elapsed, Duration.zero);
      expect(find.text('Bắt đầu'), findsOneWidget);
    });

    testWidgets('Displays fastest lap in green and slowest lap in red in laps table', (tester) async {
      // Pre-populate laps
      final lap1 = LapRecord(
        lapNumber: 1,
        lapTime: const Duration(seconds: 15),
        totalTime: const Duration(seconds: 15),
      );
      final lap2 = LapRecord(
        lapNumber: 2,
        lapTime: const Duration(seconds: 8), // Fastest
        totalTime: const Duration(seconds: 23),
      );
      final lap3 = LapRecord(
        lapNumber: 3,
        lapTime: const Duration(seconds: 25), // Slowest
        totalTime: const Duration(seconds: 48),
      );

      sw.lapsNotifier.value = [lap3, lap2, lap1];

      await tester.pumpWidget(
        const MaterialApp(
          home: StopwatchScreen(),
        ),
      );

      await tester.pump();

      expect(find.text('Lịch Sử Vòng (Laps)'), findsOneWidget);
      expect(find.text('3 vòng'), findsOneWidget);
      expect(find.text('Nhanh nhất'), findsOneWidget);
      expect(find.text('Chậm nhất'), findsOneWidget);
      expect(find.text('#01'), findsOneWidget);
      expect(find.text('#02'), findsOneWidget);
      expect(find.text('#03'), findsOneWidget);
    });
  });
}
