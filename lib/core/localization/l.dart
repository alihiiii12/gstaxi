import 'package:get/get.dart';
import '../constants/app_strings.dart';
import '../utils/validation_error.dart';

class L {
  L._();

  // =========================
  // GENERAL
  // =========================
  static String get appName => AppStrings.appName.tr;
  static String get ok => AppStrings.ok.tr;
  static String get cancel => AppStrings.cancel.tr;
  static String get save => AppStrings.save.tr;
  static String get edit => AppStrings.edit.tr;
  static String get delete => AppStrings.delete.tr;
  static String get loading => AppStrings.loading.tr;
  static String get retry => AppStrings.retry.tr;

  // =========================
  // AUTH
  // =========================
  static String get login => AppStrings.login.tr;
  static String get logout => AppStrings.logout.tr;
  static String get register => AppStrings.register.tr;
  static String get email => AppStrings.email.tr;
  static String get password => AppStrings.password.tr;
  static String get forgotPassword => AppStrings.forgotPassword.tr;

  // =========================
  // PROFILE
  // =========================
  static String get profile => AppStrings.profile.tr;
  static String get editProfile => AppStrings.editProfile.tr;
  static String get name => AppStrings.name.tr;
  static String get phone => AppStrings.phone.tr;

  // =========================
  // HOME
  // =========================
  static String get home => AppStrings.home.tr;
  static String get search => AppStrings.search.tr;
  static String get seeAll => AppStrings.seeAll.tr;
  static String get newArrival => AppStrings.newArrival.tr;

  // =========================
  // CART
  // =========================
  static String get cart => AppStrings.cart.tr;
  static String get addCart => AppStrings.addCart.tr;
  static String get total => AppStrings.total.tr;

  // =========================
  // MESSAGES (PARAMETERS)
  // =========================
  static String welcomeUser(String name) =>
      _replace(AppStrings.welcomeUser, {'name': name});

  static String itemsCount(int count) =>
      _replace(AppStrings.itemsCount, {'count': count.toString()});

  static String priceCurrency(dynamic price, String currency) =>
      _replace(AppStrings.priceCurrency, {
        'price': price.toString(),
        'currency': currency,
      });

  // =========================
  // ERRORS (GENERIC)
  // =========================
  static String get errorGeneric => AppStrings.errorGeneric.tr;
  static String get noData => AppStrings.noData.tr;

  // =========================
  // VALIDATION ERRORS
  // =========================
  static String validation(ValidationError error) {
    switch (error) {
      case ValidationError.empty:
        return AppStrings.errorEmpty.tr;

      case ValidationError.tooShort:
        return AppStrings.errorTooShort.tr;

      case ValidationError.tooLong:
        return AppStrings.errorTooLong.tr;

      case ValidationError.invalidEmail:
        return AppStrings.errorInvalidEmail.tr;


      case ValidationError.notMatch:
        return AppStrings.errorNotMatch.tr;

      case ValidationError.invalidPhone:
        return AppStrings.errorInvalidPhone.tr;

      case ValidationError.invalidCountryCode:
        return AppStrings.errorInvalidCountryCode.tr;

      case ValidationError.invalidUsername:
        return AppStrings.errorInvalidUsername.tr;

      case ValidationError.usernameTaken:
        return AppStrings.errorUsernameTaken.tr;

      case ValidationError.invalidName:
        return AppStrings.errorInvalidName.tr;

      case ValidationError.notNumber:
        return AppStrings.errorNotNumber.tr;

      case ValidationError.negativeNumber:
        return AppStrings.errorNegativeNumber.tr;

      case ValidationError.outOfRange:
        return AppStrings.errorOutOfRange.tr;

      case ValidationError.invalidUrl:
        return AppStrings.errorInvalidUrl.tr;
    }
  }

  // =========================
  // CORE ENGINE
  // =========================
  static String _replace(String key, Map<String, String> params) {
    String text = key.tr;

    assert(
    params.keys.every((k) => text.contains('@$k')),
    '❌ Missing parameter @$params in key: $key',
    );

    params.forEach((k, v) {
      text = text.replaceAll('@$k', v);
    });

    return text;
  }
}
