/// سياق شاشة OTP المشتركة.
enum AuthOtpPurpose {
  register,
  resetPassword,
}

extension AuthOtpPurposeX on AuthOtpPurpose {
  String get apiPurpose =>
      this == AuthOtpPurpose.register ? 'register' : 'reset_password';

  String get title =>
      this == AuthOtpPurpose.register ? 'تحقق من الكود' : 'تحقق من الكود';

  String subtitleForPhone(String phoneDisplay) =>
      'أدخل الرمز المكون من 4 أرقام المرسل برسالة نصية إلى\n$phoneDisplay';
}
