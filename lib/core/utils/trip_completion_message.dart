/// نص ملخص إنهاء الرحلة للسائق والزبون — يعتمد سعر العداد لا التقديري.
String buildTripCompletionMessage({
  Map<String, dynamic>? tripRow,
  Map<String, dynamic>? apiData,
  String? apiFinalCost,
  /// تكلفة العداد المحلية عند الإنهاء (أولوية على السعر التقديري).
  num? meterFinalCost,
}) {
  String firstStr(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return '';
    for (final k in keys) {
      final v = m[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }

  final dataMap = apiData;
  final meterFromArg = meterFinalCost != null
      ? meterFinalCost.round().toString()
      : '';
  final fcFromData = firstStr(dataMap, const ['finalCost', 'final_cost']);
  final fromApiArg = (apiFinalCost ?? '').trim();

  // أولوية: عداد محلي → finalCost من السيرفر → لا تستخدم السعر التقديري كأساسي.
  final finalCost = meterFromArg.isNotEmpty
      ? meterFromArg
      : (fcFromData.isNotEmpty
          ? fcFromData
          : fromApiArg);

  final km = firstStr(dataMap, const [
    'distanceTraveledKm',
    'distance_traveled_km',
  ]);
  final waitMin = firstStr(dataMap, const [
    'billedWaitingMinutes',
    'billed_waiting_minutes',
  ]);
  final elapsed = firstStr(dataMap, const [
    'meterElapsedSeconds',
    'meter_elapsed_seconds',
  ]);

  final details = <String>[];
  if (km.isNotEmpty) details.add('المسافة: $km كم');
  if (waitMin.isNotEmpty) details.add('وقوف محسوب: $waitMin د');
  if (elapsed.isNotEmpty) {
    final sec = int.tryParse(elapsed) ?? 0;
    final m = sec ~/ 60;
    final s = sec % 60;
    details.add(
      'الزمن: ${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
    );
  }
  final detailsBlock = details.isEmpty ? '' : '\n${details.join('\n')}';

  final dc = firstStr(tripRow, const ['discountCode', 'discount_code']);
  if (dc.isNotEmpty && finalCost.isNotEmpty) {
    return 'تكلفة العداد:\n$finalCost ل.س\n(كوبون $dc)$detailsBlock';
  }
  if (finalCost.isNotEmpty) {
    return 'تكلفة العداد:\n$finalCost ل.س$detailsBlock';
  }
  return 'شكراً لاستخدامكم التطبيق.';
}
