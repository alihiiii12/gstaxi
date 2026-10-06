import 'customer_trip_status_helpers.dart';
import 'driver_order_display.dart';

/// مرحلة تنفيذ الرحلة — لوحة سفلى مضغوطة (بدون شريط البحث/الفئات).
bool customerInLiveTripPhase(Map<String, dynamic>? trip) {
  if (trip == null) return false;
  final st = CustomerTripStatusHelpers.normTripStatus(trip);
  // قبل القبول أو أثناء انتظار تحديد الوجهة: ليست «رحلة جارية» على الخريطة.
  if (st == 'Pending' || st == 'AwaitingDestination') return false;
  return st == 'DriverArrived' ||
      st == 'Running' ||
      st == 'Reserved';
}

/// إخفاء بحث الوجهة + تفاصيل المسار + بطاقات الفئات.
/// يُخفى بعد قبول السائق/بدء الرحلة؛ يُعرض عند تحديد الوجهة (AwaitingDestination).
bool customerShouldHideBookingComposeOverlay(Map<String, dynamic>? trip) {
  if (trip == null) return false;
  if (!CustomerTripStatusHelpers.shouldShowAsMapActiveTrip(trip)) {
    return false;
  }
  final st = CustomerTripStatusHelpers.normTripStatus(trip);
  if (st == 'Pending' || st == 'AwaitingDestination') return false;
  return st == 'Reserved' ||
      st == 'DriverArrived' ||
      st == 'Running';
}

bool driverShouldHideDestinationSearch({
  required Map<String, dynamic>? assignedRequest,
  required bool freeMeterActive,
  bool navigationActive = false,
}) {
  if (freeMeterActive || navigationActive) return true;
  if (assignedRequest == null) return false;
  final st = normTripStatusForOrder(assignedRequest);
  if (st == 'Running' ||
      st == 'DriverArrived' ||
      st == 'AwaitingDestination') {
    return true;
  }
  if (st == 'Pending' && requestIsImmediate(assignedRequest)) {
    return true;
  }
  if (st == 'Reserved') {
    return true; // أثناء التوجه للراكب أو انتظار الانطلاق — بلا بحث
  }
  return false;
}
