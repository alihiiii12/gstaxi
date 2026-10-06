import 'dart:convert';


import 'package:dartz/dartz.dart';
import 'package:http/http.dart' as http;

import '../constants/error_model.dart';
import '../services/storage_service.dart';
import 'api_endpoints.dart';
import 'api_exceptions.dart';

class ApiClient {
  // static Future<Map<String, dynamic>> post(
  //     String endpoint, {
  //       Map<String, dynamic>? body,
  //     }) async {
  //   final response = await
  //
  //   http.post(
  //     Uri.parse(ApiEndpoints.baseUrl + endpoint),
  //     headers: {
  //       'Accept': 'application/json',
  //       'Content-Type': 'application/json',
  //       if (StorageService.token != null)
  //         'Authorization': 'Bearer ${StorageService.token}',
  //     },
  //     body: jsonEncode(body),
  //   );
  //
  //   final data = jsonDecode(response.body);
  //
  //   if (response.statusCode >= 200 && response.statusCode < 300) {
  //     return data;
  //   }
  //
  //   throw ApiException(
  //     message: data['message'] ?? 'Something went wrong',
  //     statusCode: response.statusCode,
  //   );
  // }
  static Future<Either<ErrorModel, T>> post<T>(
      String endpoint, {
        Map<String, dynamic>? body,
        required T Function(dynamic json) fromJson,
      }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.baseUrl + endpoint),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          if (StorageService.token != null)
            'Authorization': 'Bearer ${StorageService.token}',
        },
        body: jsonEncode(body),
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        return Right(fromJson(decoded));
      }

      return Left(ErrorModel.fromJson(decoded));
    } catch (e) {
      return Left(
        ErrorModel(
          message: e.toString(),
          statusCode: -1,
          success: '',
          errors: [],
        ),
      );
    }
  }

 static Future<Either<ErrorModel, T>> get<T>(
      String endpoint, {
      String search= "",
      String page = "1",
        required T Function(dynamic json) fromJson,
      }) async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.baseUrl + endpoint+"?search=$search&page=$page"),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          if (StorageService.token != null)
            'Authorization': 'Bearer ${StorageService.token}',
        },
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return Right(fromJson(decoded));
      }

      return Left(
        ErrorModel.fromJson(
          decoded,
        ),
      );
    } catch (e) {
      return Left(
        ErrorModel(
          message: e.toString(),
          statusCode: -1, success: '', errors: [],
        ),
      );
    }
  }

}
