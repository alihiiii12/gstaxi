class AppRegex {
  AppRegex._();

  /// =========================
  /// BASIC
  /// =========================
  static final RegExp email =
  RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  static final RegExp password =
  RegExp(r'^.{8,}$'); // 8 أحرف على الأقل

  static final RegExp strongPassword =
  RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}$');

  static final RegExp phone =
  RegExp(r'^(09\d{8}|(\+9639\d{8}))$');

  static final RegExp username =
  RegExp(r'^[a-zA-Z0-9_]{3,20}$');

  static final RegExp name =
  RegExp(r'^[a-zA-Z\u0600-\u06FF ]{2,}$');

  static final RegExp number =
  RegExp(r'^\d+$');

  static final RegExp decimal =
  RegExp(r'^\d+(\.\d+)?$');

  /// =========================
  /// HELPERS
  /// =========================
  static bool isEmail(String v) => email.hasMatch(v);

  static bool isPassword(String v) => password.hasMatch(v);

  static bool isStrongPassword(String v) =>
      strongPassword.hasMatch(v);

  static bool isPhone(String v) => phone.hasMatch(v);

  static bool isUsername(String v) =>
      username.hasMatch(v);

  static bool isName(String v) => name.hasMatch(v);

  static bool isNumber(String v) => number.hasMatch(v);

  static bool isDecimal(String v) =>
      decimal.hasMatch(v);
}
