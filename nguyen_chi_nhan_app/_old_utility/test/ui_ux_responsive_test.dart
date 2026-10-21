import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_chi_nhan_app/models/alarm_model.dart';
import 'package:nguyen_chi_nhan_app/screens/main_screen.dart';
import 'package:nguyen_chi_nhan_app/screens/alarm/widgets/alarm_ring_dialog.dart';
import 'package:nguyen_chi_nhan_app/services/alarm_manager.dart';
import 'package:nguyen_chi_nhan_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Agent 2 UI/UX Responsive & Aesthetics Verification (412x915)', () {
    const mobileScreenSize = Size(412, 915);

    setUp(() {
      AlarmManager.instance.stopClockCheck();
    });

    setUp(() {
      AlarmManager.instance.stopClockCheck();
    });

    tearDown(() {
      AlarmManager.instance.stopClockCheck();
    });

    testWidgets('Verify 5-tab NavigationBar & Layout at 412x915 in Light Theme', (tester) async {
      tester.view.physicalSize = mobileScreenSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MainScreen(
            onToggleTheme: () {},
            isDarkMode: false,
          ),
        ),
      );
      await tester.pump();

      // Check App Bar & Theme
      expect(find.text('Quy Đổi Đơn Vị'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);

      // Verify all 5 navigation destinations fit within 412dp width
      expect(find.text('Đổi Đơn Vị'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Báo Thức'), findsOneWidget);
      expect(find.text('Bấm Giờ'), findsOneWidget);
      expect(find.text('Voice AI'), findsOneWidget);

      // Switch to Tab 1 (YouTube)
      await tester.tap(find.text('YouTube'));
      await tester.pump();
      expect(find.text('YouTube Player'), findsOneWidget);

      // Switch to Tab 2 (Báo Thức)
      await tester.tap(find.text('Báo Thức'));
      await tester.pump();
      expect(find.text('Đồng Hồ Báo Thức'), findsWidgets);

      // Switch to Tab 3 (Bấm Giờ)
      await tester.tap(find.text('Bấm Giờ'));
      await tester.pump();
      expect(find.text('Đồng Hồ Bấm Giờ'), findsWidgets);

      // Switch to Tab 4 (Voice AI)
      await tester.tap(find.text('Voice AI'));
      await tester.pump();
      expect(find.text('Trợ Lý Giọng Nói'), findsWidgets);

      // Cleanly unmount to cancel clock timers
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Verify 5-tab NavigationBar & Layout at 412x915 in Dark Theme', (tester) async {
      tester.view.physicalSize = mobileScreenSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MainScreen(
            onToggleTheme: () {},
            isDarkMode: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Đổi Đơn Vị'), findsOneWidget);
      expect(find.text('Voice AI'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Verify Alarm Ring Dialog UI with vibrating bell and Snooze/Dismiss', (tester) async {
      tester.view.physicalSize = mobileScreenSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final alarm = AlarmModel(
        id: 'test_alarm_1',
        time: const TimeOfDay(hour: 6, minute: 30),
        label: 'Thức dậy chạy bộ',
        isEnabled: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AlarmRingDialog(alarm: alarm),
          ),
        ),
      );
      await tester.pump();

      // Check ringing dialog elements
      expect(find.text('BÁO THỨC ĐANG REO!'), findsOneWidget);
      expect(find.text('06:30'), findsOneWidget);
      expect(find.text('Thức dậy chạy bộ'), findsOneWidget);
      expect(find.text('Báo lại (5p)'), findsOneWidget);
      expect(find.text('Tắt chuông'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);

      // Bell animation advances without error
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('BÁO THỨC ĐANG REO!'), findsOneWidget);
    });
  });
}
