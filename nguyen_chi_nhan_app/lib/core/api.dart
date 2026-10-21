import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Địa chỉ NguyenChiNhan_WebAPI. Đổi khi build: --dart-define=API_URL=http://10.0.2.2:5055
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://nguyenchinhan-webapi.vercel.app');

class ApiException implements Exception {
  final int status;
  final String message;
  final String? code;
  final Map<String, dynamic> data;
  ApiException(this.status, this.message, {this.code, this.data = const {}});
  @override
  String toString() => message;
}

/// Người dùng đang đăng nhập (lưu token + role trong máy)
class Session {
  final String token;
  final String role; // Admin | Staff | User
  final Map<String, dynamic> user;
  const Session(this.token, this.role, this.user);

  String get fullName => user['fullName'] ?? '';
  String get firstName => fullName.trim().split(' ').last;
  String get initials {
    final p = fullName.trim().split(RegExp(r'\s+'));
    if (p.isEmpty || p.first.isEmpty) return '?';
    return p.length == 1 ? p.first[0].toUpperCase() : (p[p.length - 2][0] + p.last[0]).toUpperCase();
  }
}

/// Client gọi API: gắn Bearer token + thông tin thiết bị (dùng cho email cảnh báo đăng nhập)
class Api {
  Api._();
  static final Api i = Api._();

  final session = ValueNotifier<Session?>(null);
  /// Có thể thay bằng MockClient khi test
  http.Client client = http.Client();
  Map<String, String> _device = {};

  /// Gọi khi phiên bị thu hồi (đổi vai trò, “Không phải tôi”…) để app quay về đăng nhập
  VoidCallback? onSessionExpired;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('session');
    if (raw != null) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      session.value = Session(m['token'], m['role'], Map<String, dynamic>.from(m['user']));
    }
    _device = await _deviceHeaders();
  }

  Future<void> saveSession(String token, String role, Map<String, dynamic> user) async {
    session.value = Session(token, role, user);
    final p = await SharedPreferences.getInstance();
    await p.setString('session', jsonEncode({'token': token, 'role': role, 'user': user}));
  }

  Future<void> updateUser(Map<String, dynamic> user) async {
    final s = session.value;
    if (s != null) await saveSession(s.token, s.role, user);
  }

  Future<void> clearSession() async {
    session.value = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('session');
  }

  Future<Map<String, String>> _deviceHeaders() async {
    try {
      final d = DeviceInfoPlugin();
      if (kIsWeb) {
        final w = await d.webBrowserInfo;
        final os = (w.platform ?? '').toLowerCase().contains('iphone') || (w.userAgent ?? '').contains('iPhone') ? 'iPhone' : (w.platform ?? 'Web');
        return {'X-Device-Name': '${w.browserName.name[0].toUpperCase()}${w.browserName.name.substring(1)} · $os', 'X-Device-Platform': 'Web'};
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await d.androidInfo;
        return {'X-Device-Name': '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)} ${a.model}', 'X-Device-Platform': 'Android ${a.version.release}'};
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final a = await d.iosInfo;
        return {'X-Device-Name': a.utsname.machine, 'X-Device-Platform': 'iOS ${a.systemVersion}'};
      }
    } catch (_) {}
    return {'X-Device-Name': 'Flutter ${defaultTargetPlatform.name}', 'X-Device-Platform': defaultTargetPlatform.name};
  }

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body);
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body);
  Future<dynamic> patch(String path, [Object? body]) => _send('PATCH', path, body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$apiUrl/api$path'));
    req.headers.addAll({'Content-Type': 'application/json', 'Accept': 'application/json', ..._device});
    final token = session.value?.token;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    http.Response res;
    try {
      res = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 20)));
    } on TimeoutException {
      throw ApiException(0, 'Máy chủ phản hồi quá lâu. Thử lại nhé.', code: 'NETWORK');
    } catch (_) {
      throw ApiException(0, 'Không kết nối được máy chủ.', code: 'NETWORK');
    }
    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final m = data is Map<String, dynamic> ? data : <String, dynamic>{};
    final e = ApiException(res.statusCode, m['message']?.toString() ?? 'Có lỗi xảy ra (${res.statusCode}).', code: m['code']?.toString(), data: m);
    if (res.statusCode == 401 && token != null && path != '/auth/logout') {
      await clearSession();
      onSessionExpired?.call();
    }
    throw e;
  }
}
