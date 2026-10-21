import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_chi_nhan_app/models/voice_command.dart';
import 'package:nguyen_chi_nhan_app/screens/voice/voice_screen.dart';
import 'package:nguyen_chi_nhan_app/services/voice_service.dart';
import 'package:nguyen_chi_nhan_app/services/stopwatch_service.dart';
import 'package:nguyen_chi_nhan_app/services/alarm_manager.dart';
import 'package:nguyen_chi_nhan_app/services/audio_alarm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AudioAlarmService.instance.isEnabled = false;
    VoiceService.instance.clearHistory();
    StopwatchService.instance.reset();
  });

  tearDown(() {
    StopwatchService.instance.reset();
  });

  group('Module 5: VoiceService Vietnamese NLP & Logic Tests', () {
    test('VoiceService initial state and history management', () {
      final voice = VoiceService.instance;
      expect(voice.isListeningNotifier.value, false);
      expect(voice.spokenWordsNotifier.value, '');
      expect(voice.commandHistoryNotifier.value.isEmpty, true);

      voice.processVoiceCommand('bắt đầu bấm giờ');
      expect(voice.commandHistoryNotifier.value.length, 1);

      voice.clearHistory();
      expect(voice.commandHistoryNotifier.value.isEmpty, true);
    });

    test('Stopwatch voice command variants', () {
      final voice = VoiceService.instance;

      // Start stopwatch
      final resStart = voice.processVoiceCommand('bắt đầu bấm giờ');
      expect(resStart.type, VoiceCommandType.startStopwatch);
      expect(resStart.isSuccess, true);
      expect(StopwatchService.instance.isRunning, true);

      // Record lap
      final resLap = voice.processVoiceCommand('ghi vòng');
      expect(resLap.type, VoiceCommandType.lapStopwatch);
      expect(resLap.isSuccess, true);
      expect(StopwatchService.instance.laps.length, 1);

      // Pause stopwatch
      final resPause = voice.processVoiceCommand('tạm dừng');
      expect(resPause.type, VoiceCommandType.stopStopwatch);
      expect(resPause.isSuccess, true);
      expect(StopwatchService.instance.isRunning, false);

      // Reset stopwatch
      final resReset = voice.processVoiceCommand('đặt lại bấm giờ');
      expect(resReset.type, VoiceCommandType.resetStopwatch);
      expect(resReset.isSuccess, true);
      expect(StopwatchService.instance.elapsed, Duration.zero);
    });

    test('Alarm voice command - Absolute time parsing', () {
      final voice = VoiceService.instance;
      final initialAlarmCount = AlarmManager.instance.alarms.length;

      // 7 giờ 30
      final res1 = voice.processVoiceCommand('đặt báo thức lúc 7 giờ 30');
      expect(res1.type, VoiceCommandType.setAlarm);
      expect(res1.isSuccess, true);
      expect(res1.alarmTime?.hour, 7);
      expect(res1.alarmTime?.minute, 30);
      expect(AlarmManager.instance.alarms.length, initialAlarmCount + 1);

      // 6h sáng
      final res2 = voice.processVoiceCommand('báo thức lúc 6h sáng');
      expect(res2.type, VoiceCommandType.setAlarm);
      expect(res2.isSuccess, true);
      expect(res2.alarmTime?.hour, 6);
      expect(res2.alarmTime?.minute, 0);

      // 8 giờ tối (20:00)
      final res3 = voice.processVoiceCommand('đặt báo thức 8 giờ tối');
      expect(res3.type, VoiceCommandType.setAlarm);
      expect(res3.isSuccess, true);
      expect(res3.alarmTime?.hour, 20);
      expect(res3.alarmTime?.minute, 0);

      // 22h15
      final res4 = voice.processVoiceCommand('đặt báo thức lúc 22h15');
      expect(res4.type, VoiceCommandType.setAlarm);
      expect(res4.isSuccess, true);
      expect(res4.alarmTime?.hour, 22);
      expect(res4.alarmTime?.minute, 15);
    });

    test('Alarm voice command - Relative time parsing (hẹn giờ sau X phút)', () {
      final voice = VoiceService.instance;
      final res = voice.processVoiceCommand('hẹn giờ sau 10 phút');
      expect(res.type, VoiceCommandType.setAlarm);
      expect(res.isSuccess, true);
      expect(res.responseMessage, contains('10 phút'));
    });

    test('Unknown / Fallback voice command parsing', () {
      final voice = VoiceService.instance;
      final res = voice.processVoiceCommand('hôm nay trời đẹp quá');
      expect(res.type, VoiceCommandType.unknown);
      expect(res.isSuccess, false);
      expect(res.responseMessage, contains('Chưa hiểu lệnh'));
    });
  });

  group('Module 5: VoiceScreen UI & Widget Tests', () {
    testWidgets('Renders VoiceScreen UI with Mic button, quick chips and input field', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VoiceScreen(),
        ),
      );

      // AppBar title
      expect(find.text('Trợ Lý Giọng Nói AI'), findsOneWidget);

      // Mic state
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      expect(find.text('Chạm để nói câu lệnh'), findsOneWidget);

      // 1-Tap Quick Action Chips
      expect(find.text('Thử Nhanh Câu Lệnh (1-Tap Test)'), findsOneWidget);
      expect(find.text('Bắt đầu bấm giờ'), findsOneWidget);
      expect(find.text('Tạm dừng bấm giờ'), findsOneWidget);
      expect(find.text('Ghi vòng (Lap)'), findsOneWidget);
      expect(find.text('Đặt lại bấm giờ'), findsOneWidget);
      expect(find.text('Đặt báo thức lúc 7 giờ 30'), findsOneWidget);
      expect(find.text('Báo thức lúc 6h sáng'), findsOneWidget);
      expect(find.text('Hẹn giờ sau 10 phút'), findsOneWidget);
      expect(find.text('Đặt báo thức lúc 22h15'), findsOneWidget);

      // Manual command TextField
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);

      // Command History Title
      expect(find.text('Lịch Sử Nhận Diện & Thực Thi'), findsOneWidget);
      expect(find.text('0 lệnh'), findsOneWidget);
    });

    testWidgets('1-Tap Quick chip executes command and updates history & snackbar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VoiceScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Tap 'Bắt đầu bấm giờ' chip
      final startChip = find.text('Bắt đầu bấm giờ');
      await tester.ensureVisible(startChip);
      await tester.tap(startChip);
      await tester.pump(const Duration(milliseconds: 200));

      // Verify Stopwatch is running
      expect(StopwatchService.instance.isRunning, true);

      // Verify History updated
      expect(find.text('1 lệnh'), findsOneWidget);
      expect(find.text('"Bắt đầu bấm giờ"'), findsOneWidget);
      expect(find.text('Đã bắt đầu đồng hồ bấm giờ!'), findsAtLeastNWidgets(1));

      // Tap 'Ghi vòng (Lap)' chip
      final lapChip = find.text('Ghi vòng (Lap)');
      await tester.ensureVisible(lapChip);
      await tester.tap(lapChip);
      await tester.pump(const Duration(milliseconds: 200));

      expect(StopwatchService.instance.laps.length, 1);
      expect(find.text('2 lệnh'), findsOneWidget);

      StopwatchService.instance.reset();
    });

    testWidgets('Typing custom command in TextField executes and displays in history', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VoiceScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll to & Enter command in TextField
      final textField = find.byType(TextField);
      await tester.ensureVisible(textField);
      await tester.enterText(textField, 'đặt báo thức lúc 7 giờ 30');

      final sendBtn = find.byIcon(Icons.send_rounded);
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pump(const Duration(milliseconds: 200));

      // Verify history
      expect(find.text('1 lệnh'), findsOneWidget);
      expect(find.text('"đặt báo thức lúc 7 giờ 30"'), findsOneWidget);

      // Test Clear History button
      final clearButton = find.byIcon(Icons.delete_outline_rounded);
      expect(clearButton, findsOneWidget);
      await tester.ensureVisible(clearButton);
      await tester.tap(clearButton);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('0 lệnh'), findsOneWidget);
      expect(find.text('Chưa có câu lệnh nào được thực thi.\nHãy bấm mic hoặc chọn 1 câu lệnh mẫu ở trên!'), findsOneWidget);
    });

    testWidgets('Mic button reflects listening state with acoustic wave effect', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VoiceScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Initially not listening
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);

      // Simulate listening state
      VoiceService.instance.isListeningNotifier.value = true;
      await tester.pump(const Duration(milliseconds: 100));

      // Verify active listening text & mic active icon
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.text('ĐANG THU NHẬN SÓNG ÂM GIỌNG NÓI (vi-VN)...'), findsOneWidget);

      // Reset
      VoiceService.instance.isListeningNotifier.value = false;
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    });
  });
}
