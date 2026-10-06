import '../constants/app_strings.dart';
import 'ar.dart';
import 'en.dart';
import 'fr.dart';

class TranslationAssert {
  TranslationAssert._();

  static void check() {
    final allKeys = _collectAppStringKeys();

    _checkLang('AR', ar, allKeys);
    _checkLang('EN', en, allKeys);
    _checkLang('FR', fr, allKeys);
  }

  // =========================
  // Helpers
  // =========================

  static Set<String> _collectAppStringKeys() {
    return {
      AppStrings.appName,
      AppStrings.ok,
      AppStrings.cancel,
      AppStrings.save,
      AppStrings.edit,
      AppStrings.delete,
      AppStrings.loading,
      AppStrings.retry,

      AppStrings.login,
      AppStrings.logout,
      AppStrings.register,
      AppStrings.email,
      AppStrings.password,
      AppStrings.forgotPassword,

      AppStrings.profile,
      AppStrings.editProfile,
      AppStrings.name,
      AppStrings.phone,

      AppStrings.home,
      AppStrings.search,
      AppStrings.seeAll,
      AppStrings.newArrival,

      AppStrings.cart,
      AppStrings.addCart,
      AppStrings.total,

      AppStrings.welcomeUser,
      AppStrings.itemsCount,
      AppStrings.priceCurrency,

      AppStrings.errorGeneric,
      AppStrings.noData,

      AppStrings.errorEmpty,
      AppStrings.errorTooShort,
      AppStrings.errorTooLong,
      AppStrings.errorInvalidEmail,

      AppStrings.errorWeakPassword,
      AppStrings.errorNoUpper,
      AppStrings.errorNoLower,
      AppStrings.errorNoNumber,
      AppStrings.errorNoSpecial,

      AppStrings.errorNotMatch,
      AppStrings.errorInvalidPhone,
      AppStrings.errorInvalidCountryCode,
      AppStrings.errorInvalidUsername,
      AppStrings.errorUsernameTaken,
      AppStrings.errorInvalidName,

      AppStrings.errorNotNumber,
      AppStrings.errorNegativeNumber,
      AppStrings.errorOutOfRange,
      AppStrings.errorInvalidUrl,
    };
  }

  static void _checkLang(
      String lang,
      Map<String, String> map,
      Set<String> keys,
      ) {
    for (final key in keys) {
      assert(
      map.containsKey(key),
      '❌ Missing translation key "$key" in $lang',
      );
    }
  }
}
