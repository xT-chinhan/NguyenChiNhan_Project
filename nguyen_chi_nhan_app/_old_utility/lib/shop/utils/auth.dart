import 'dart:convert';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

class Auth {
  static final AuthService _authService = AuthService();
  static final ApiClient _apiClient = ApiClient();

  // Đăng nhập
  static Future<Map<String, dynamic>> login(
    String username,
    String password,
  ) async {
    final result = await _authService.login(username, password);
    return result;
  }

  // Đăng ký tài khoản mới
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String initials,
    required String role,
  }) async {
    final Map<String, dynamic> body = {
      "username": username,
      "email": email,
      "password": password,
      "initials": initials,
      "role": role,
    };

    try {
      final response = await _apiClient.post(
        'Authenticate/register',
        body: body,
        includeAuth: false,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': (data['status'] ?? data['Status'] ?? true) == true,
          'message': data['message'] ?? data['Message'] ?? 'Đăng ký thành công',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ??
              data['Message'] ??
              'Đăng ký thất bại (${response.statusCode})',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Lỗi kết nối: ${e.toString()}',
      };
    }
  }

  // Đăng xuất: xóa token và role khỏi SharedPreferences
  static Future<void> logout() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_role');
  }

  // Lấy token hiện tại từ SharedPreferences
  static Future<String?> getToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  // Lấy role hiện tại từ SharedPreferences
  static Future<String?> getRole() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role');
  }

  // Kiểm tra token có tồn tại và còn hạn hay không
  static Future<bool> isLoggedIn() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('jwt_token');
    if (token == null || token.isEmpty) return false;
    try {
      return !JwtDecoder.isExpired(token);
    } catch (_) {
      return false;
    }
  }
}
