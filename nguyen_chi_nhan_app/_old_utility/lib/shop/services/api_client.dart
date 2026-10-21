import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/config_url.dart';

class ApiClient {
  final String baseUrl;

  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? Config_URL.baseUrl;

  Future<Map<String, String>> _buildHeaders(
    Map<String, String>? headers, {
    bool includeAuth = true,
  }) async {
    final Map<String, String> finalHeaders = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (includeAuth) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('jwt_token');
      if (token != null && token.isNotEmpty) {
        finalHeaders['Authorization'] = 'Bearer $token';
      }
    }

    if (headers != null) {
      finalHeaders.addAll(headers);
    }

    return finalHeaders;
  }

  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool includeAuth = true,
  }) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final builtHeaders = await _buildHeaders(headers, includeAuth: includeAuth);
    return http.get(url, headers: builtHeaders);
  }

  Future<http.Response> post(
    String endpoint, {
    Map<String, String>? headers,
    dynamic body,
    bool includeAuth = true,
  }) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final builtHeaders = await _buildHeaders(headers, includeAuth: includeAuth);
    return http.post(
      url,
      headers: builtHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> put(
    String endpoint, {
    Map<String, String>? headers,
    dynamic body,
    bool includeAuth = true,
  }) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final builtHeaders = await _buildHeaders(headers, includeAuth: includeAuth);
    return http.put(
      url,
      headers: builtHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> delete(
    String endpoint, {
    Map<String, String>? headers,
    bool includeAuth = true,
  }) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final builtHeaders = await _buildHeaders(headers, includeAuth: includeAuth);
    return http.delete(url, headers: builtHeaders);
  }
}
