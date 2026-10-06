import 'formatters.dart';
import 'driver_order_display.dart';

/// حالات الطلب ونصوص العرض للزبون.
class CustomerTripStatusHelpers {
  CustomerTripStatusHelpers._();

  static String completedTripSurveyDetailPrefix() => '[اكتملت الرحلة] ';

  static String normTripStatus(Map<String, dynamic> r) {
    final v = r['status'];
    final raw = v?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    final lower = raw.toLowerCase().replaceAll('_', '');
    const canon = {
      'pending': 'Pending',
      'reserved': 'Reserved',
      'driverarrived': 'DriverArrived',
      'awaitingdestination': 'AwaitingDestination',
      'running': 'Running',
      'finished': 'Finished',
      'removed': 'Removed',
    };
    return canon[lower] ?? raw;
  }

  static bool requestIsImmediate(Map<String, dynamic> r) {
    final t = (r['type'] ?? r['Type'] ?? '').toString().toLowerCase();
    return t.contains('immediate');
  }

  static bool requestIsScheduled(Map<String, dynamic> r) =>
      !requestIsImmediate(r);

  /// عنوان شريط الرحلة النشطة للراكب (يخفي حالة DriverArrived الداخلية).
  static String customerActiveTripTitle(Map<String, dynamic> r) {
    final st = normTripStatus(r);
    switch (st) {
      case 'Pending':
        return 'بانتظار قبول السائق';
      case 'Reserved':
        return 'السائق في الطريق إليك';
      case 'DriverArrived':
        return 'وصل السائق إليك';
      case 'AwaitingDestination':
        return 'بانتظار تحديد الوجهة';
      case 'Running':
        return 'الرحلة جارية';
      default:
        return 'تم تعيين سائق لرحلتك';
    }
  }

  static String customerRequestStatusLabel(Map<String, dynamic> r) {
    final st = normTripStatus(r);
    final sched = requestIsScheduled(r);
    if (sched && st == 'Pending') {
      return 'قيد الانتظار — بانتظار قبول أحد السائقين';
    }
    if (sched && st == 'Reserved') {
      if (!scheduledTripLiveOnMap(r)) {
        final when = AppFormatters.requestCardDateTimeDisplay(
          (r['requestDate'] ?? r['request_date'] ?? '').toString(),
        );
        return when != '—'
            ? 'حجز مقبول — الموعد $when (بانتظار وقت الرحلة)'
            : 'حجز مقبول — بانتظار وقت الرحلة';
      }
      return 'تم قبول الحجز — السائق في الطريق';
    }
    const map = {
      'Pending': 'بانتظار قبول السائق',
      'Reserved': 'تم القبول — السائق في الطريق',
      'DriverArrived': 'وصل السائق — بانتظار بدء الرحلة',
      'AwaitingDestination': 'بانتظار تحديد الوجهة',
      'Running': 'الرحلة جارية',
      'Finished': 'انتهت الرحلة',
      'Removed': 'ملغاة',
    };
    return map[st] ?? st;
  }

  static int? driverIdFromTrip(Map<String, dynamic> t) {
    var d = int.tryParse(
          t['driverId']?.toString() ?? t['driver_id']?.toString() ?? '') ??
        0;
    if (d > 0) return d;
    final hist = t['history'];
    if (hist is Map) {
      final hm = Map<String, dynamic>.from(hist);
      d = int.tryParse(
            hm['driverId']?.toString() ?? hm['driver_id']?.toString() ?? '') ??
          0;
      if (d > 0) return d;
      final drv = hm['driver'];
      if (drv is Map) {
        final id = int.tryParse(drv['id']?.toString() ?? '') ?? 0;
        if (id > 0) return id;
      }
    }
    final dr = t['driver'];
    if (dr is Map) {
      final id = int.tryParse(dr['id']?.toString() ?? '') ?? 0;
      if (id > 0) return id;
    }
    return null;
  }

  static bool isActiveStatus(String st) =>
      st == 'Pending' ||
      st == 'Reserved' ||
      st == 'DriverArrived' ||
      st == 'AwaitingDestination' ||
      st == 'Running';

  static bool shouldShowAsMapActiveTrip(Map<String, dynamic> r) {
    final st = normTripStatus(r);
    if (!isActiveStatus(st)) return false;
    if (requestIsScheduled(r) && st == 'Pending') return false;
    if (requestIsScheduled(r) &&
        st == 'Reserved' &&
        !scheduledTripLiveOnMap(r)) {
      return false;
    }
    return true;
  }
}
