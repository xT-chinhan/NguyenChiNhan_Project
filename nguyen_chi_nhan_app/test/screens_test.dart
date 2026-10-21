// Dựng từng màn với dữ liệu thật (fixtures lấy từ NguyenChiNhan_WebAPI) và chụp ảnh để so với mockup.
// Chạy: flutter test test/screens_test.dart --update-goldens  -> ảnh ở test/goldens/
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nguyen_chi_nhan_app/core/api.dart';
import 'package:nguyen_chi_nhan_app/core/theme.dart';
import 'package:nguyen_chi_nhan_app/features/account/account_screen.dart';
import 'package:nguyen_chi_nhan_app/features/account/login_history_screen.dart';
import 'package:nguyen_chi_nhan_app/features/auth/login_screen.dart';
import 'package:nguyen_chi_nhan_app/features/auth/otp_screen.dart';
import 'package:nguyen_chi_nhan_app/features/auth/register_screen.dart';
import 'package:nguyen_chi_nhan_app/features/home/role_home.dart';
import 'package:nguyen_chi_nhan_app/features/shop/shop_screen.dart';
import 'package:nguyen_chi_nhan_app/features/staff/product_form_screen.dart';
import 'package:nguyen_chi_nhan_app/features/tools/location_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Map<String, dynamic> fx;

Future<void> _loadFont(String family, List<String> assets) async {
  final l = FontLoader(family);
  for (final a in assets) {
    l.addFont(rootBundle.load(a));
  }
  await l.load();
}

void _session(String role) {
  final s = fx['session_$role'];
  Api.i.session.value = Session(s['token'], s['role'], Map<String, dynamic>.from(s['user']));
}

http.Client _mock() => MockClient((req) async {
      final p = req.url.path.replaceFirst('/api', '') + (req.url.hasQuery ? '?${req.url.query}' : (req.url.toString().endsWith('?') ? '?' : ''));
      final routes = <String, String>{
        '/categories': 'categories',
        '/products?sort=price_asc': 'products_price_asc',
        '/products?sort=newest': 'products_newest',
        '/products/6': 'product_6',
        '/me': 'me',
        '/me/sessions': 'sessions',
        '/tools/noise/levels': 'noise_levels',
        '/dashboard/staff': 'dash_staff',
        '/dashboard/admin': 'dash_admin',
        '/users?': 'users',
        '/users': 'users',
        '/tools/location/resolve': 'location',
      };
      final key = routes[p];
      if (key == null) return http.Response(jsonEncode({'message': 'no fixture $p'}), 404);
      return http.Response.bytes(utf8.encode(jsonEncode(fx[key])), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });

Future<void> shot(WidgetTester t, String name, Widget home, {ThemeData? theme}) async {
  t.view.physicalSize = const Size(780, 1688);
  t.view.devicePixelRatio = 2;
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme ?? AppTheme.light,
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  await t.pumpWidget(const SizedBox());
  t.view.resetPhysicalSize();
}

void main() {
  setUpAll(() async {
    fx = jsonDecode(File('test/fixtures/api.json').readAsStringSync());
    SharedPreferences.setMockInitialValues({});
    await _loadFont('BeVietnamPro', [for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/BeVietnamPro-$w.ttf']);
    await _loadFont('packages/lucide_icons_flutter/Lucide', ['packages/lucide_icons_flutter/assets/lucide.ttf']);
    Api.i.client = _mock();
  });

  testWidgets('01 đăng nhập', (t) async => shot(t, '01-dang-nhap', const LoginScreen()));
  testWidgets('02 đăng ký', (t) async => shot(t, '02-dang-ky', const RegisterScreen()));
  testWidgets('04 OTP đăng nhập', (t) async {
    await shot(t, '04-otp-dang-nhap', const OtpScreen(mode: OtpMode.login, info: {'username': 'baongoc', 'maskedEmail': 'hut•••@gmail.com', 'resendAfter': 42}));
  });
  testWidgets('10 cửa hàng', (t) async {
    _session('User');
    await shot(t, '10-kh-cua-hang', const RoleHome());
  });
  testWidgets('11 chi tiết', (t) async {
    _session('User');
    await shot(t, '11-kh-chi-tiet', const ProductDetailScreen(id: 6));
  });
  testWidgets('13 tài khoản KH', (t) async {
    _session('User');
    await shot(t, '13-kh-tai-khoan', const AccountScreen());
  });
  testWidgets('24 vị trí', (t) async {
    _session('User');
    await shot(t, '24-chia-se-vi-tri', const LocationScreen());
  });
  testWidgets('30 NV tổng quan', (t) async {
    _session('Staff');
    await shot(t, '30-nv-tong-quan', const RoleHome());
  });
  testWidgets('32 NV sửa SP', (t) async {
    _session('Staff');
    await shot(t, '32-nv-sua-san-pham', ProductFormScreen(product: fx['product_6']));
  });
  testWidgets('40 Admin tổng quan', (t) async {
    _session('Admin');
    await shot(t, '40-ad-tong-quan', const RoleHome());
  });
  testWidgets('47 Admin tài khoản', (t) async {
    _session('Admin');
    await shot(t, '47-ad-tai-khoan', const AccountScreen());
  });
  testWidgets('51 lịch sử đăng nhập', (t) async {
    _session('User');
    await shot(t, '51-lich-su-dang-nhap', const LoginHistoryScreen());
  });
  testWidgets('52 đã khóa', (t) async {
    await shot(t, '52-da-khoa', const LockedScreen(result: {'revokedSessions': 3, 'resetCodeSent': true, 'adminsNotified': 1, 'maskedEmail': 'hut•••@gmail.com', 'username': 'baongoc'}));
  });
  testWidgets('dark mode cửa hàng', (t) async {
    _session('User');
    await shot(t, '90-dark-cua-hang', const RoleHome(), theme: AppTheme.dark);
  });
}
