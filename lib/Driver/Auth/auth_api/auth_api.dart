import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/error_model.dart';
import '../../../core/constants/shared_pref.dart';
import '../../../core/constants/success_model.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/http_timeouts.dart';
import '../../../core/utils/device_session_id.dart';
import '../../../core/utils/syrian_phone.dart';
import '../../../core/services/app_update_gate.dart';
import '../model/user_model.dart';



class AuthApi {
  static String _num(String raw) => SyrianPhone.normalize(raw);

  static Future<Either<ErrorModel, UserResponseModel>> login({
    required String number,
    required String password,
    String? fcmToken,
  }) async {
    var url = Uri.parse(ApiEndpoints.login);

    try {
      final clientHeaders = await AppUpdateGate.authClientHeaders();
      var response = await http
          .post(
        url,
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'ar',
          'Content-Type': 'application/json',
          ...clientHeaders,
        },
        body: json.encode({
          'number': _num(number),
          'password': password,
          'device_id': DeviceSessionId.get(),
          'app_build': clientHeaders['X-App-Build'],
          if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
        }),
      )
          .timeout(HttpTimeouts.auth);

      var decodedData = json.decode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (decodedData is! Map) {
          return Left(ErrorModel(
            message: 'رد غير متوقع من الخادم',
            success: 'false',
            statusCode: response.statusCode,
            errors: const [],
          ));
        }
        try {
          return Right(
            UserResponseModel.fromJson(
              Map<String, dynamic>.from(decodedData),
            ),
          );
        } catch (e) {
          return Left(ErrorModel(
            message: 'تعذر قراءة بيانات الدخول',
            success: 'false',
            statusCode: response.statusCode,
            errors: [e.toString()],
          ));
        }
      } else {
        final err = ErrorModel.fromJson(
          decodedData is Map
              ? Map<String, dynamic>.from(decodedData)
              : <String, dynamic>{'message': response.body},
        );
        err.statusCode = response.statusCode;
        return Left(err);
      }
    } catch (e) {
      final hint = e.toString();
      final isTimeout = hint.contains('TimeoutException');
      return Left(ErrorModel(
          message: isTimeout
              ? 'انتهت مهلة الاتصال بالخادم — حاول مجدداً'
              : 'تعذر الاتصال بالخادم — تحقق من الإنترنت',
          success: "false",
          statusCode: 500,
          errors: [hint]
      ));
    }
  }
  static Future<http.Response> updatepassword({required String password, required String token}) async {
    final authToken = token.isNotEmpty
        ? token
        : (await ApiEndpoints.getToken() ?? '');

    final url = Uri.parse(ApiEndpoints.updatepassword);

    return http.post(
      url,
      headers: {
        'Authorization': 'Bearer $authToken',
        'Accept': 'application/json',
      },
      body: {
        'password': password,
      },
    );
  }

  static Map<String, dynamic> _decodeMap(http.Response response) {
    try {
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return {'message': response.body, 'state': false, 'success': false};
    }
  }

  static Future<Either<ErrorModel, Map<String, dynamic>>> registerCustomer({
    required String fullName,
    required String number,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(ApiEndpoints.registerCustomer),
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'ar',
        },
        body: {
          'fullName': fullName,
          'number': _num(number),
          'password': password,
          'password_confirmation': passwordConfirmation,
        },
      );
      final map = _decodeMap(res);
      final ok = (res.statusCode == 200 || res.statusCode == 201) &&
          (map['state'] == true || map['success'] == true);
      if (ok) return Right(map);
      return Left(ErrorModel.fromJson(map));
    } catch (e) {
      return Left(ErrorModel(
        message: 'خطأ في الاتصال بالسيرفر',
        success: 'false',
        statusCode: 500,
        errors: [e.toString()],
      ));
    }
  }

  static Future<Either<ErrorModel, Map<String, dynamic>>> resendOtp({
    required String number,
    required String purpose,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(ApiEndpoints.resendCode),
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'ar',
        },
        body: {'number': _num(number), 'purpose': purpose},
      );
      final map = _decodeMap(res);
      final ok = res.statusCode >= 200 &&
          res.statusCode < 300 &&
          (map['state'] == true || map['success'] == true);
      if (ok) return Right(map);
      return Left(ErrorModel.fromJson(map));
    } catch (e) {
      return Left(ErrorModel(
        message: 'خطأ في الاتصال',
        success: 'false',
        statusCode: 500,
        errors: [e.toString()],
      ));
    }
  }

  static Future<Either<ErrorModel, UserResponseModel>> confirmAccount({
    required String number,
    required String code,
    String? fcmToken,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(ApiEndpoints.confirmAccount),
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'ar',
        },
        body: {
          'number': _num(number),
          'code': code,
          'device_id': DeviceSessionId.get(),
          if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
        },
      );
      final map = _decodeMap(res);
      final ok = res.statusCode >= 200 &&
          res.statusCode < 300 &&
          (map['state'] == true || map['success'] == true);
      if (ok) return Right(UserResponseModel.fromJson(map));
      final err = ErrorModel.fromJson(map);
      err.statusCode = res.statusCode;
      return Left(err);
    } catch (e) {
      return Left(ErrorModel(
        message: 'خطأ في الاتصال',
        success: 'false',
        statusCode: 500,
        errors: [e.toString()],
      ));
    }
  }

  static Future<Either<ErrorModel, Map<String, dynamic>>> forgotPassword({
    required String number,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(ApiEndpoints.forgetPassword),
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'ar',
        },
        body: {'number': _num(number)},
      );
      final map = _decodeMap(res);
      final ok = res.statusCode >= 200 &&
          res.statusCode < 300 &&
          (map['state'] == true || map['success'] == true);
      if (ok) return Right(map);
      return Left(ErrorModel.fromJson(map));
    } catch (e) {
      return Left(ErrorModel(
        message: 'خطأ في الاتصال',
        success: 'false',
        statusCode: 500,
        errors: [e.toString()],
      ));
    }
  }

  static Future<Either<ErrorModel, Map<String, dynamic>>> confirmForgetOtp({
    required String number,
    required String code,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(ApiEndpoints.confirmForget),
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'ar',
        },
        body: {'number': _num(number), 'code': code},
      );
      final map = _decodeMap(res);
      final ok = res.statusCode >= 200 &&
          res.statusCode < 300 &&
          (map['state'] == true || map['success'] == true);
      if (ok) return Right(map);
      return Left(ErrorModel.fromJson(map));
    } catch (e) {
      return Left(ErrorModel(
        message: 'خطأ في الاتصال',
        success: 'false',
        statusCode: 500,
        errors: [e.toString()],
      ));
    }
  }

  static Future<Either<ErrorModel, Map<String, dynamic>>> resetPasswordAfterOtp({
    required String number,
    required String resetToken,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(ApiEndpoints.forgetPasswordReset),
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'ar',
        },
        body: {
          'number': _num(number),
          'reset_token': resetToken,
          'password': password,
          'password_confirmation': passwordConfirmation,
        },
      );
      final map = _decodeMap(res);
      final ok = res.statusCode >= 200 &&
          res.statusCode < 300 &&
          (map['state'] == true || map['success'] == true);
      if (ok) return Right(map);
      return Left(ErrorModel.fromJson(map));
    } catch (e) {
      return Left(ErrorModel(
        message: 'خطأ في الاتصال',
        success: 'false',
        statusCode: 500,
        errors: [e.toString()],
      ));
    }
  }

  static Future<http.Response> logoutRequest() async {
    final url = Uri.parse(ApiEndpoints.logout);
    final headers = await ApiEndpoints.headers();
    return http.post(url, headers: headers);
  }
}
