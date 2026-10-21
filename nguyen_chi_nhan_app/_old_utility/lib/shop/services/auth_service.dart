import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/config_url.dart';

class AuthService {
  String get apiUrl => "${Config_URL.baseUrl}Authenticate/login";

  static String extractRole(Map<String, dynamic> decodedToken) {
    final dynamic roleClaim = decodedToken['role'] ??
        decodedToken['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'] ??
        decodedToken['Role'];

    if (roleClaim is List && roleClaim.isNotEmpty) {
      return roleClaim.first.toString();
    }
    if (roleClaim != null) {
      return roleClaim.toString();
    }
    return 'User';
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password": password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bool status = (data['status'] ?? data['Status'] ?? true) == true;

        if (!status) {
          return {
            "success": false,
            "message": data['message'] ?? data['Message'] ?? 'Đăng nhập thất bại',
          };
        }

        final String? token = data['token'] ?? data['Token'];
        if (token == null || token.isEmpty) {
          return {
            "success": false,
            "message": "Không nhận được token xác thực từ server.",
          };
        }

        // Decode token để lấy các thông tin đăng nhập: tên đăng nhập, role...
        final Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
        final String role = extractRole(decodedToken);

        // Lưu token và vai trò vào SharedPreferences
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);
        await prefs.setString('user_role', role);

        return {
          "success": true,
          "token": token,
          "role": role,
          "decodedToken": decodedToken,
          "message": data['message'] ?? data['Message'] ?? 'Đăng nhập thành công',
        };
      } else {
        try {
          final errorData = jsonDecode(response.body);
          final message = errorData['message'] ?? errorData['Message'] ?? 'Đăng nhập thất bại: ${response.statusCode}';
          return {"success": false, "message": message};
        } catch (_) {
          return {"success": false, "message": "Đăng nhập thất bại: ${response.statusCode}"};
        }
      }
    } catch (e) {
      return {"success": false, "message": "Lỗi kết nối mạng: $e"};
    }
  }
}
