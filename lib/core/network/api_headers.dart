import '../services/storage_service.dart';

class ApiHeaders {
  static Future<Map<String, String>> headers() async {
    final token = StorageService.token;
    final currency = StorageService.currency ?? 'USD';
    final lang = StorageService.language ?? 'ar';

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Accept-Language': lang,
      'X-Currency': currency,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}
