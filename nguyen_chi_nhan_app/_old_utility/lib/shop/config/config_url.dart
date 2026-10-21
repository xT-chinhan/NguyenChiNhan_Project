import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config_URL {
  static String get baseUrl {
    final url = dotenv.env['BASE_URL'];
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print("BASE_URL is not set in the .env file. Using default URL.");
      return "http://localhost:5000/api/";
    }
    return url;
  }
}
