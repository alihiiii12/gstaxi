/// نتيجة محاولة قبول طلب فوري.
class ImmediateAcceptResult {
  const ImmediateAcceptResult({
    required this.ok,
    this.message = '',
    this.takenByOther = false,
  });

  final bool ok;
  final String message;
  final bool takenByOther;
}
