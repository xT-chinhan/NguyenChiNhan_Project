import 'package:flutter/material.dart';
import 'screens/main_screen.dart';

/// Theme toàn app (dùng chung cho Login/Admin/Hub tiện ích)
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.light);

/// Hub tiện ích sau khi đăng nhập (giữ nút đổi theme sáng/tối)
class UtilityHome extends StatelessWidget {
  const UtilityHome({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => MainScreen(
        isDarkMode: mode == ThemeMode.dark,
        onToggleTheme: () => themeModeNotifier.value =
            mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
      ),
    );
  }
}
