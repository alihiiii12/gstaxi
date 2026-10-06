import 'dart:convert';

class SuccessModel {
  String message;
  String success;
  int statusCode;

  SuccessModel({
    required this.message,
    required this.success,
    required this.statusCode,
  });

  factory SuccessModel.fromRawJson(String str) => SuccessModel.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());

  factory SuccessModel.fromJson(Map<String, dynamic> json) => SuccessModel(
    message: json["message"],
    success: json["success"],
    statusCode: json["status_code"],
  );

  Map<String, dynamic> toJson() => {
    "message": message,
    "success": success,
    "status_code": statusCode,
  };
}
