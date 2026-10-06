import 'dart:convert';

class ErrorModel {
  String message;
  String success;
  int statusCode;
  List<String> errors;
  String? code;
  String? downloadUrl;

  ErrorModel({
    required this.message,
    required this.success,
    required this.statusCode,
    required this.errors,
    this.code,
    this.downloadUrl,
  });

  factory ErrorModel.fromRawJson(String str) => ErrorModel.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());
  factory ErrorModel.fromJson(Map<String, dynamic> json) => ErrorModel(
    message: json["message"] ?? "حدث خطأ غير معروف",
    success: json["success"]?.toString() ?? "false",
    statusCode: json["status_code"] ?? 0,
    code: json["code"]?.toString(),
    downloadUrl: json["download_url"]?.toString(),
    // Laravel عادة يرجع errors كـ Map<String, List<String>>
    // بينما أحياناً قد تكون List أو String.
    errors: () {
      final raw = json["errors"];
      if (raw == null) return <String>[];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      if (raw is Map) {
        final out = <String>[];
        raw.forEach((key, value) {
          if (value is List) {
            for (final v in value) {
              out.add(v.toString());
            }
          } else if (value != null) {
            out.add(value.toString());
          } else {
            out.add(key.toString());
          }
        });
        return out;
      }
      return <String>[raw.toString()];
    }(),
  );

  Map<String, dynamic> toJson() => {"message": message, "success": success, "status_code": statusCode, "errors": List<dynamic>.from(errors.map((x) => x))};
}
