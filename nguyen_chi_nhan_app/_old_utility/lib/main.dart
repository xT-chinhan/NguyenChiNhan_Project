import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app_shell.dart';
import 'services/audio_alarm_service.dart';
import 'theme/app_theme.dart';
import 'shop/screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    // ignore: avoid_print
    print("Could not load .env file: $e");
  }
  await AudioAlarmService.instance.init();
  runApp(const SmartUtilityApp());
}

class SmartUtilityApp extends StatelessWidget {
  const SmartUtilityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => MaterialApp(
        title: 'NguyenChiNhan App',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        // Đăng nhập trước -> phân quyền: Admin -> AdminScreen, User -> Hub tiện ích
        home: const LoginScreen(),
      ),
    );
  }
}
