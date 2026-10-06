/// تنسيق أرقام سوريا: محلي 09xxxxxxxx ودولي +9639xxxxxxxx
class SyrianPhone {
  SyrianPhone._();

  static const String countryIso = 'SY';
  static const String dialCode = '+963';

  static String normalize(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('963')) {
      d = '0${d.substring(3)}';
    }
    if (d.startsWith('00963')) {
      d = '0${d.substring(5)}';
    }
    if (d.length == 9 && !d.startsWith('0')) {
      d = '0$d';
    }
    return d;
  }

  static String toE164(String raw) {
    final local = normalize(raw);
    if (local.startsWith('0')) {
      return '$dialCode${local.substring(1)}';
    }
    return '$dialCode$local';
  }

  static String displayLocal(String raw) => normalize(raw);

  static bool isValid(String raw) {
    final n = normalize(raw);
    return RegExp(r'^09\d{8}$').hasMatch(n);
  }
}
