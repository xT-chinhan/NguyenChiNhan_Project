import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_chi_nhan_app/models/unit_category.dart';
import 'package:nguyen_chi_nhan_app/screens/converter/converter_screen.dart';
import 'package:nguyen_chi_nhan_app/screens/youtube/youtube_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Module 1 - UnitCategory Conversions & Smart Alerts', () {
    test('Temperature conversions (C, F, K, R)', () {
      // 0 C = 32 F = 273.15 K = 491.67 R
      expect(UnitCategory.convert(category: CategoryType.temperature, fromUnit: 'c', toUnit: 'f', value: 0), closeTo(32.0, 0.01));
      expect(UnitCategory.convert(category: CategoryType.temperature, fromUnit: 'c', toUnit: 'k', value: 0), closeTo(273.15, 0.01));
      expect(UnitCategory.convert(category: CategoryType.temperature, fromUnit: 'c', toUnit: 'r', value: 0), closeTo(491.67, 0.01));

      // 100 C = 212 F = 373.15 K
      expect(UnitCategory.convert(category: CategoryType.temperature, fromUnit: 'f', toUnit: 'c', value: 212), closeTo(100.0, 0.01));
      expect(UnitCategory.convert(category: CategoryType.temperature, fromUnit: 'k', toUnit: 'c', value: 373.15), closeTo(100.0, 0.01));
    });

    test('Length conversions (m, km, cm, mm, inch, ft, yd, mi)', () {
      // 1 km = 1000 m
      expect(UnitCategory.convert(category: CategoryType.length, fromUnit: 'km', toUnit: 'm', value: 1), closeTo(1000.0, 0.001));
      // 1 inch = 2.54 cm = 0.0254 m
      expect(UnitCategory.convert(category: CategoryType.length, fromUnit: 'inch', toUnit: 'cm', value: 1), closeTo(2.54, 0.001));
      // 1 mi = 1609.344 m
      expect(UnitCategory.convert(category: CategoryType.length, fromUnit: 'mi', toUnit: 'm', value: 1), closeTo(1609.344, 0.001));
      // 1 ft = 12 inch (0.3048 m / 0.0254 m = 12)
      expect(UnitCategory.convert(category: CategoryType.length, fromUnit: 'ft', toUnit: 'inch', value: 1), closeTo(12.0, 0.001));
    });

    test('Weight conversions (kg, g, mg, lb, oz, ton)', () {
      // 1 kg = 1000 g
      expect(UnitCategory.convert(category: CategoryType.weight, fromUnit: 'kg', toUnit: 'g', value: 1), closeTo(1000.0, 0.001));
      // 1 ton = 1000 kg
      expect(UnitCategory.convert(category: CategoryType.weight, fromUnit: 'ton', toUnit: 'kg', value: 1), closeTo(1000.0, 0.001));
      // 1 lb = 0.45359237 kg
      expect(UnitCategory.convert(category: CategoryType.weight, fromUnit: 'lb', toUnit: 'kg', value: 1), closeTo(0.45359, 0.001));
    });

    test('Speed conversions (kmh, ms, mph, knot)', () {
      // 36 km/h = 10 m/s
      expect(UnitCategory.convert(category: CategoryType.speed, fromUnit: 'kmh', toUnit: 'ms', value: 36), closeTo(10.0, 0.01));
      // 1 knot = 1.852 km/h
      expect(UnitCategory.convert(category: CategoryType.speed, fromUnit: 'knot', toUnit: 'kmh', value: 1), closeTo(1.852, 0.001));
    });

    test('Volume conversions (l, ml, m3, gal, floz)', () {
      // 1 m3 = 1000 L
      expect(UnitCategory.convert(category: CategoryType.volume, fromUnit: 'm3', toUnit: 'l', value: 1), closeTo(1000.0, 0.01));
      // 1 gal = 3.78541 L
      expect(UnitCategory.convert(category: CategoryType.volume, fromUnit: 'gal', toUnit: 'l', value: 1), closeTo(3.7854, 0.01));
    });

    test('Smart Alerts for Temperature & Speeds', () {
      // Absolute zero alert
      final absZero = UnitCategory.generateSmartAlert(
        category: CategoryType.temperature,
        fromUnit: 'c',
        inputValue: -273.15,
        toUnit: 'c',
        resultValue: -273.15,
      );
      expect(absZero, isNotNull);
      expect(absZero!.title, contains('Độ 0 tuyệt đối'));

      // Below absolute zero critical alert
      final belowZero = UnitCategory.generateSmartAlert(
        category: CategoryType.temperature,
        fromUnit: 'c',
        inputValue: -280,
        toUnit: 'c',
        resultValue: -280,
      );
      expect(belowZero, isNotNull);
      expect(belowZero!.level, AlertLevel.critical);

      // Freezing point alert
      final freeze = UnitCategory.generateSmartAlert(
        category: CategoryType.temperature,
        fromUnit: 'c',
        inputValue: 0,
        toUnit: 'f',
        resultValue: 32,
      );
      expect(freeze, isNotNull);
      expect(freeze!.title, contains('đóng băng'));

      // Normal body temp
      final normalTemp = UnitCategory.generateSmartAlert(
        category: CategoryType.temperature,
        fromUnit: 'c',
        inputValue: 37.0,
        toUnit: 'f',
        resultValue: 98.6,
      );
      expect(normalTemp, isNotNull);
      expect(normalTemp!.level, AlertLevel.success);

      // Mild fever alert
      final mildFever = UnitCategory.generateSmartAlert(
        category: CategoryType.temperature,
        fromUnit: 'c',
        inputValue: 38.0,
        toUnit: 'c',
        resultValue: 38.0,
      );
      expect(mildFever, isNotNull);
      expect(mildFever!.level, AlertLevel.warning);
      expect(mildFever.title, contains('sốt nhẹ'));

      // High fever alert
      final feverAlert = UnitCategory.generateSmartAlert(
        category: CategoryType.temperature,
        fromUnit: 'c',
        inputValue: 39.0,
        toUnit: 'c',
        resultValue: 39.0,
      );
      expect(feverAlert, isNotNull);
      expect(feverAlert!.level, AlertLevel.critical);
      expect(feverAlert.title, contains('Sốt cao'));

      // Boiling point alert
      final boil = UnitCategory.generateSmartAlert(
        category: CategoryType.temperature,
        fromUnit: 'c',
        inputValue: 100,
        toUnit: 'f',
        resultValue: 212,
      );
      expect(boil, isNotNull);
      expect(boil!.title, contains('Điểm sôi'));

      // Speed mach 1 alert
      final machAlert = UnitCategory.generateSmartAlert(
        category: CategoryType.speed,
        fromUnit: 'kmh',
        inputValue: 1250,
        toUnit: 'kmh',
        resultValue: 1250,
      );
      expect(machAlert, isNotNull);
      expect(machAlert!.title, contains('siêu thanh'));

      // Negative distance alert
      final negAlert = UnitCategory.generateSmartAlert(
        category: CategoryType.length,
        fromUnit: 'm',
        inputValue: -10,
        toUnit: 'm',
        resultValue: -10,
      );
      expect(negAlert, isNotNull);
      expect(negAlert!.level, AlertLevel.warning);
      expect(negAlert.title, contains('giá trị âm'));
    });
  });

  group('Module 1 - ConverterScreen Widget Tests', () {
    testWidgets('Renders ConverterScreen, recalculates on input change', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ConverterScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Quy Đổi & Đo Lường'), findsOneWidget);
      expect(find.text('Nhiệt độ'), findsOneWidget);

      // Default input is 37°C
      expect(find.text('37'), findsWidgets);
      // Result should be 98.6 °F
      expect(find.text('98.6'), findsOneWidget);

      // Enter 100
      final textField = find.byType(TextField);
      await tester.enterText(textField, '100');
      await tester.pumpAndSettle();

      // 100°C = 212°F
      expect(find.text('212'), findsOneWidget);
      expect(find.textContaining('Điểm sôi'), findsOneWidget);
    });

    testWidgets('Swap units works correctly', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ConverterScreen()));
      await tester.pumpAndSettle();

      // Tap swap button
      final swapBtn = find.byTooltip('Đảo chiều chuyển đổi');
      await tester.tap(swapBtn);
      await tester.pumpAndSettle();

      // Input 37 now converted from °F to °C: (37 - 32) * 5 / 9 = 2.778
      expect(find.text('2.778'), findsOneWidget);
    });

    testWidgets('Copy result sets Clipboard data and shows snackbar', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ConverterScreen()));
      await tester.pumpAndSettle();

      final copyBtn = find.text('Sao chép kết quả');
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Đã sao chép:'), findsOneWidget);
    });

    testWidgets('Preset chips update input and recalculate accurately', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ConverterScreen()));
      await tester.pumpAndSettle();

      // Scroll to preset '100' and tap
      final preset100 = find.widgetWithText(ActionChip, '100');
      expect(preset100, findsOneWidget);
      await tester.ensureVisible(preset100);
      await tester.tap(preset100);
      await tester.pumpAndSettle();

      expect(find.text('212'), findsOneWidget);
      expect(find.textContaining('Điểm sôi'), findsOneWidget);

      // Tap preset '37' (normal body temp)
      final preset37 = find.widgetWithText(ActionChip, '37');
      await tester.ensureVisible(preset37);
      await tester.tap(preset37);
      await tester.pumpAndSettle();

      expect(find.text('98.6'), findsOneWidget);
      expect(find.textContaining('thân nhiệt'), findsWidgets);
    });

    testWidgets('Switching categories updates units and values', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ConverterScreen()));
      await tester.pumpAndSettle();

      // Switch to 'Chiều dài'
      final lengthTab = find.text('Chiều dài');
      await tester.tap(lengthTab);
      await tester.pumpAndSettle();

      // Default length is 1000m -> 1km
      expect(find.text('1000'), findsWidgets);
      expect(find.text('1'), findsWidgets);
    });
  });

  group('Module 2 - YouTube Logic & URL Extractor Tests', () {
    test('Extracts video ID from full watch URL', () {
      expect(YoutubeScreen.extractVideoId('https://www.youtube.com/watch?v=l-epqV_Uv1s'), 'l-epqV_Uv1s');
      expect(YoutubeScreen.extractVideoId('https://youtube.com/watch?v=l-epqV_Uv1s'), 'l-epqV_Uv1s');
      expect(YoutubeScreen.extractVideoId('https://m.youtube.com/watch?v=l-epqV_Uv1s'), 'l-epqV_Uv1s');
    });

    test('Extracts video ID from youtu.be short URL', () {
      expect(YoutubeScreen.extractVideoId('https://youtu.be/l-epqV_Uv1s'), 'l-epqV_Uv1s');
      expect(YoutubeScreen.extractVideoId('https://youtu.be/l-epqV_Uv1s?si=randomParam123'), 'l-epqV_Uv1s');
    });

    test('Extracts video ID from shorts URL', () {
      expect(YoutubeScreen.extractVideoId('https://www.youtube.com/shorts/l-epqV_Uv1s'), 'l-epqV_Uv1s');
      expect(YoutubeScreen.extractVideoId('https://youtube.com/shorts/l-epqV_Uv1s'), 'l-epqV_Uv1s');
    });

    test('Extracts video ID from embed URL', () {
      expect(YoutubeScreen.extractVideoId('https://www.youtube.com/embed/l-epqV_Uv1s'), 'l-epqV_Uv1s');
    });

    test('Extracts video ID when query params appear before v', () {
      expect(YoutubeScreen.extractVideoId('https://www.youtube.com/watch?feature=share&v=l-epqV_Uv1s'), 'l-epqV_Uv1s');
      expect(YoutubeScreen.extractVideoId('https://www.youtube.com/watch?time_continue=10&v=l-epqV_Uv1s'), 'l-epqV_Uv1s');
    });

    test('Extracts direct 11-char video ID', () {
      expect(YoutubeScreen.extractVideoId('l-epqV_Uv1s'), 'l-epqV_Uv1s');
      expect(YoutubeScreen.extractVideoId('  b_sQ9bMltGU  '), 'b_sQ9bMltGU');
    });

    test('Extracts video ID without scheme', () {
      expect(YoutubeScreen.extractVideoId('youtube.com/watch?v=l-epqV_Uv1s'), 'l-epqV_Uv1s');
      expect(YoutubeScreen.extractVideoId('youtu.be/l-epqV_Uv1s'), 'l-epqV_Uv1s');
    });

    test('Rejects invalid URLs and non-YouTube strings', () {
      expect(YoutubeScreen.extractVideoId(''), isNull);
      expect(YoutubeScreen.extractVideoId('   '), isNull);
      expect(YoutubeScreen.extractVideoId('https://google.com'), isNull);
      expect(YoutubeScreen.extractVideoId('https://facebook.com/video'), isNull);
      expect(YoutubeScreen.extractVideoId('invalid_id_123'), isNull); // 14 chars != 11
    });

    test('Preset sample videos are valid with complete metadata', () {
      expect(YoutubeScreen.sampleVideos.length, 4);
      for (final sample in YoutubeScreen.sampleVideos) {
        expect(sample['title'], isNotEmpty);
        expect(sample['author'], isNotEmpty);
        final id = sample['id']!;
        expect(id.length, 11);
        expect(YoutubeScreen.extractVideoId(id), id);
      }
    });
  });

  group('Module 2 - YouTube Screen Widget Tests', () {
    testWidgets('Renders YoutubeScreen and displays input & sample videos', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: YoutubeScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Xem Video YouTube'), findsOneWidget);
      expect(find.text('Nhập link YouTube để xem'), findsOneWidget);
      expect(find.text('Video Mẫu Xem Nhanh'), findsOneWidget);

      // Verify sample videos are present
      expect(find.text('Flutter in 100 Seconds'), findsOneWidget);
      expect(find.text('Building Beautiful UIs with Flutter'), findsOneWidget);
      expect(find.text('Lofi Hip Hop Radio - Beats to Relax'), findsOneWidget);
      expect(find.text('Big Buck Bunny (Sample HD)'), findsOneWidget);
    });

    testWidgets('Shows clear error when empty link submitted', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: YoutubeScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // Clear input
      final textField = find.byType(TextField);
      await tester.enterText(textField, '');
      await tester.pump(const Duration(milliseconds: 50));

      // Submit
      final submitBtn = find.text('Xem Video Ngay');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Vui lòng nhập hoặc dán link'), findsWidgets);
    });

    testWidgets('Shows clear error banner when invalid link submitted', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: YoutubeScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'https://invalid-website.com/test');
      await tester.pump(const Duration(milliseconds: 50));

      final submitBtn = find.text('Xem Video Ngay');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Link không hợp lệ!'), findsWidgets);
    });

    testWidgets('Tapping sample video updates link and triggers playback snackbar', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: YoutubeScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // Tap first sample video
      final sampleVideo = find.text('Flutter in 100 Seconds');
      expect(sampleVideo, findsOneWidget);
      await tester.ensureVisible(sampleVideo);
      await tester.tap(sampleVideo);
      await tester.pump(const Duration(milliseconds: 100));

      // SnackBar shows playback confirmation
      expect(find.textContaining('Đang phát: Flutter in 100 Seconds'), findsOneWidget);
      // Input textfield updated with link
      expect(find.text('https://youtu.be/l-epqV_Uv1s'), findsOneWidget);
    });
  });
}
