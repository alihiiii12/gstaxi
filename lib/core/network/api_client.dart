// import 'dart:convert';
//
// import 'package:http/http.dart' as http;
//
// import '../services/storage_service.dart';
// import 'api_endpoints.dart';
// import 'api_exceptions.dart';
//
// class ApiClient {
//   static Future<Map<String, String>> post(String endpoint, {Map<String, dynamic>? body}) async {
//     final response = await http.post(Uri.parse(ApiEndpoints.baseUrl + endpoint), headers: {'Accept': 'application/json', 'Content-Type': 'application/json', if (StorageService.token != null) 'Authorization': 'Bearer ${StorageService.token}'}, body: jsonEncode(body));
//
//     final data = jsonDecode(response.body);
//
//     if (response.statusCode >= 200 && response.statusCode < 300) {
//       return data;
//     }
//
//     throw ApiException(message: data['message'] ?? 'Something went wrong', statusCode: response.statusCode);
//   }
// }
