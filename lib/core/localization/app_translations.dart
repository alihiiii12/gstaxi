import 'package:get/get.dart';
import 'ar.dart';
import 'en.dart';
import 'fr.dart';

class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'ar': ar,
    'en': en,
    'fr': fr,
  };
}
