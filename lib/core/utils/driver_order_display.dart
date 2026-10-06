import 'package:get_storage/get_storage.dart';

import 'formatters.dart';

/// يطابق منطق الزبون في `customer_home_screen` لتطبيع الحالة.
String normTripStatusForOrder(Map<String, dynamic> r) {
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

bool requestIsImmediate(Map<String, dynamic> r) {
  final t = (r['type'] ?? r['Type'] ?? '').toString().toLowerCase();
  return t.contains('immediate');
}

bool requestIsScheduled(Map<String, dynamic> r) => !requestIsImmediate(r);

/// نص الحالة في قائمة طلبات السائق (مشابه لـ«طلباتي» عند الراكب).
String driverOrderListStatusLabel(Map<String, dynamic> r) {
  final st = normTripStatusForOrder(r);
  final sched = requestIsScheduled(r);
  if (sched && st == 'Pending') {
    final did = int.tryParse(
      r['driverId']?.toString() ?? r['driver_id']?.toString() ?? '',
    );
    final box = GetStorage();
    final me = int.tryParse(box.read('driver_id')?.toString() ?? '') ?? 0;
    if (did != null && did > 0 && me > 0 && did == me) {
      return 'بانتظار قبولك (حجز مسبق)';
    }
    return 'مفتوح — بانتظار قبول أحد السائقين';
  }
  if (sched && st == 'Reserved') {
    if (scheduledDriverMayOperateTrip(r)) {
      return 'حجز مسبق — في الطريق للراكب';
    }
    if (scheduledGoWindowOpen(r)) {
      return 'حجز مسبق — حان وقت الانطلاق للراكب';
    }
    final when = formatScheduledRequestDate(r);
    if (when != null) {
      return 'تم قبول الطلب — الموعد: $when';
    }
    return 'تم قبول الطلب — بانتظار وقت الرحلة';
  }
  const map = {
    'Pending': 'بانتظار قبولك',
    'Reserved': 'تم القبول — في الطريق للراكب',
    'DriverArrived': 'وصلت للراكب',
    'AwaitingDestination': 'بانتظار تحديد الوجهة من الراكب',
    'Running': 'الرحلة جارية',
    'Finished': 'انتهت الرحلة',
    'Removed': 'ملغاة',
  };
  return map[st] ?? (st.isEmpty ? '—' : st);
}

/// اسم الراكب من الطلب (user.firstName + lastName).
String passengerNameFromRequest(Map<String, dynamic> request) {
  final user = request['user'];
  if (user is Map) {
    final m = Map<String, dynamic>.from(user);
    final name = '${m['firstName'] ?? ''} ${m['lastName'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
  }
  for (final k in ['customerName', 'customer_name', 'passengerName']) {
    final v = request[k]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return 'راكب';
}

/// رقم هاتف الراكب الذي أنشأ الطلب.
String? passengerPhoneFromRequest(Map<String, dynamic> request) {
  final user = request['user'];
  if (user is Map) {
    final m = Map<String, dynamic>.from(user);
    for (final k in ['number', 'phone', 'mobile']) {
      final v = m[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
  }
  for (final k in [
    'customerPhone',
    'customer_phone',
    'passengerPhone',
    'passenger_phone',
    'userNumber',
    'user_number',
  ]) {
    final v = request[k]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

/// هل دخل السائق مرحلة التنفيذ (بعد إشعار جاهزية الراكب و«ابدأ الرحلة»)؟
bool scheduledDriverMayOperateTrip(Map<String, dynamic> r) {
  if (!requestIsScheduled(r)) return true;
  final st = normTripStatusForOrder(r);
  if (st == 'Running' ||
      st == 'DriverArrived' ||
      st == 'AwaitingDestination') {
    return true;
  }
  if (st != 'Reserved') return false;
  final started = r['sched_driver_started_at'] ?? r['schedDriverStartedAt'];
  if (started == null) return false;
  final s = started.toString().trim();
  return s.isNotEmpty && s.toLowerCase() != 'null';
}

bool scheduledInWaitingPhase(Map<String, dynamic> r) {
  return requestIsScheduled(r) &&
      normTripStatusForOrder(r) == 'Reserved' &&
      !scheduledDriverMayOperateTrip(r);
}

/// نافذة «انطلق للراكب» تُفتح قبل موعد الحجز المسبق بهذه المدة (مطابق للسيرفر).
const int kScheduledGoWindowMinutes = 30;

/// حجز مسبق مقبول دخل نافذة الانطلاق (≤ 30 د قبل الموعد) ولم ينطلق السائق بعد.
bool scheduledGoWindowOpen(Map<String, dynamic> r) {
  if (!scheduledInWaitingPhase(r)) return false;
  final flag = r['sched_go_window_open'];
  if (flag == true || flag?.toString() == '1' || flag?.toString() == 'true') {
    return true;
  }
  final ms = int.tryParse('${r['request_date_ms'] ?? ''}') ?? 0;
  if (ms <= 0) return false;
  final opensAt = ms - kScheduledGoWindowMinutes * 60 * 1000;
  return DateTime.now().millisecondsSinceEpoch >= opensAt;
}

/// السائق يمكنه إلغاء الطلب بعد القبول قبل بدء الرحلة (Reserved / وصلت / بانتظار الوجهة).
bool driverMayCancelEnRoute(Map<String, dynamic> r) {
  final st = normTripStatusForOrder(r);
  if (scheduledInWaitingPhase(r)) return false;
  if (requestIsImmediate(r)) {
    return st == 'Reserved' ||
        st == 'DriverArrived' ||
        st == 'AwaitingDestination';
  }
  return st == 'Reserved';
}

/// الحجز المسبق لا يُعرض كرحلة حية على الخريطة (سائق/راكب) إلا بعد «ابدأ الرحلة».
bool scheduledTripLiveOnMap(Map<String, dynamic> r) {
  if (!requestIsScheduled(r)) return true;
  final st = normTripStatusForOrder(r);
  if (st == 'Pending') return false;
  if (st == 'Reserved') return scheduledDriverMayOperateTrip(r);
  return true;
}

String? formatScheduledRequestDate(Map<String, dynamic> r) {
  final raw = r['requestDate'] ?? r['request_date'];
  if (raw == null) return null;
  final compact = AppFormatters.scheduledTripDateTimeCompact(raw.toString());
  return compact == '—' ? null : compact;
}

bool driverOrderCanShowAccept(Map<String, dynamic> r) {
  if (normTripStatusForOrder(r) != 'Pending') return false;
  final box = GetStorage();
  final me = int.tryParse(box.read('driver_id')?.toString() ?? '') ?? 0;
  final assigned = int.tryParse(
    r['driverId']?.toString() ?? r['driver_id']?.toString() ?? '',
  );
  if (requestIsScheduled(r)) {
    if (assigned != null && assigned > 0 && me > 0 && assigned != me) {
      return false;
    }
  }
  return true;
}

DateTime? _coerceDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.replaceFirst(RegExp(r'\s+'), 'T')) ??
      DateTime.tryParse(s);
}

/// للفرز: الأحدث أولاً (تاريخ الإنشاء ثم موعد الرحلة للمسبق).
int compareDriverOrdersRecentFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
  final da = _coerceDate(a['created_at'] ?? a['createdAt']) ??
      _coerceDate(a['request_date'] ?? a['requestDate']);
  final db = _coerceDate(b['created_at'] ?? b['createdAt']) ??
      _coerceDate(b['request_date'] ?? b['requestDate']);
  if (da != null && db != null) return db.compareTo(da);
  if (da != null) return -1;
  if (db != null) return 1;
  final ia = int.tryParse(a['id']?.toString() ?? '') ?? 0;
  final ib = int.tryParse(b['id']?.toString() ?? '') ?? 0;
  return ib.compareTo(ia);
}
