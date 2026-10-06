import 'validation_error.dart';

class AppValidator {
  AppValidator._();

  /// =========================
  /// GENERAL
  /// =========================
  static ValidationError? required(String v) {
    if (v.trim().isEmpty) return ValidationError.empty;
    return null;
  }

  static ValidationError? minLength(String v, int min) {
    if (v.length < min) return ValidationError.tooShort;
    return null;
  }

  static ValidationError? maxLength(String v, int max) {
    if (v.length > max) return ValidationError.tooLong;
    return null;
  }

  /// =========================
  /// EMAIL
  /// =========================
  static ValidationError? email(String v) {
    if (v.isEmpty) return ValidationError.empty;
    final regex =
    RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!regex.hasMatch(v)) return ValidationError.invalidEmail;
    return null;
  }

  /// =========================
  /// PASSWORD (FULL)
  /// =========================
  static ValidationError? password(String v) {
    if (v.isEmpty) return ValidationError.empty;
    if (v.length < 8) return ValidationError.tooShort;

    return null;
  }

  /// =========================
  /// CONFIRM PASSWORD
  /// =========================
  static ValidationError? confirm(
      String v, String original) {
    if (v.isEmpty) return ValidationError.empty;
    if (v != original) return ValidationError.notMatch;
    return null;
  }

  /// =========================
  /// PHONE
  /// =========================
  static ValidationError? phone(String v) {
    if (v.isEmpty) return ValidationError.empty;
    if (!RegExp(r'^\+?\d{8,15}$').hasMatch(v)) {
      return ValidationError.invalidPhone;
    }
    return null;
  }

  /// =========================
  /// USERNAME
  /// =========================
  static ValidationError? username(String v) {
    if (v.isEmpty) return ValidationError.empty;
    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$')
        .hasMatch(v)) {
      return ValidationError.invalidUsername;
    }
    return null;
  }

  /// =========================
  /// NAME
  /// =========================
  static ValidationError? name(String v) {
    if (v.isEmpty) return ValidationError.empty;
    if (!RegExp(r'^[a-zA-Z\u0600-\u06FF ]{2,}$')
        .hasMatch(v)) {
      return ValidationError.invalidName;
    }
    return null;
  }

  /// =========================
  /// NUMBER
  /// =========================
  static ValidationError? number(String v,
      {int? min, int? max}) {
    if (v.isEmpty) return ValidationError.empty;
    final n = int.tryParse(v);
    if (n == null) return ValidationError.notNumber;
    if (min != null && n < min) {
      return ValidationError.outOfRange;
    }
    if (max != null && n > max) {
      return ValidationError.outOfRange;
    }
    return null;
  }

  /// =========================
  /// URL
  /// =========================
  static ValidationError? url(String v) {
    if (v.isEmpty) return ValidationError.empty;
    final regex = RegExp(
        r'^(https?:\/\/)?([\w\-])+\.{1}([a-zA-Z]{2,63})([\/\w\-\.]*)*\/?$');
    if (!regex.hasMatch(v)) return ValidationError.invalidUrl;
    return null;
  }
}
