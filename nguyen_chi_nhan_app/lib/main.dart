import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/role_home.dart';
import 'widgets/ui.dart';

/// Chí Nhân Store · Đồ án Lập trình di động · Nguyễn Chí Nhân
/// App chỉ là giao diện: mọi nghiệp vụ nằm ở NguyenChiNhan_WebAPI.
final navKey = GlobalKey<NavigatorState>();
final themeMode = ValueNotifier(ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.i.init();
  final prefs = await SharedPreferences.getInstance();
  themeMode.value = (prefs.getBool('dark') ?? false) ? ThemeMode.dark : ThemeMode.light;
  Api.i.onSessionExpired = () {
    final ctx = navKey.currentContext;
    navKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    if (ctx != null && ctx.mounted) toast(ctx, 'Phiên đăng nhập đã kết thúc, mời đăng nhập lại.');
  };
  runApp(const ChiNhanApp());
}

Future<void> setDark(bool dark) async {
  themeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
  (await SharedPreferences.getInstance()).setBool('dark', dark);
}

class ChiNhanApp extends StatelessWidget {
  const ChiNhanApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: themeMode,
        builder: (_, mode, _) => MaterialApp(
          title: 'Chí Nhân Store',
          debugShowCheckedModeBanner: false,
          navigatorKey: navKey,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Api.i.session.value == null ? const LoginScreen() : const RoleHome(),
        ),
      );
}
