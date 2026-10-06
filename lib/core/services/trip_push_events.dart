/// تصنيف أحداث الرحلة القادمة من FCM/الإشعارات — Push أولاً ثم استطلاع احتياطي.
enum TripPushEventKind {
  /// طلب فوري جديد للسائق.
  immediateOffer,

  /// قبول / حجز (Reserved).
  accepted,

  /// وصل السائق.
  arrived,

  /// بدأت الرحلة (Running).
  started,

  /// انتهت الرحلة.
  finished,

  /// إلغاء / رفض / إزالة.
  cancelled,

  /// حجز مسبق / جاهزية راكب.
  scheduled,

  /// حدث رحلة عام يحتاج مزامنة.
  tripUpdate,

  /// غير معروف — لا نتجاهله إن وُجد request_id.
  unknown,
}

class TripPushEvent {
  const TripPushEvent({
    required this.kind,
    required this.rawKind,
    this.requestId,
    this.data = const {},
  });

  final TripPushEventKind kind;
  final String rawKind;
  final int? requestId;
  final Map<String, dynamic> data;

  bool get isDriverRelevant =>
      kind == TripPushEventKind.immediateOffer ||
      kind == TripPushEventKind.accepted ||
      kind == TripPushEventKind.arrived ||
      kind == TripPushEventKind.started ||
      kind == TripPushEventKind.finished ||
      kind == TripPushEventKind.cancelled ||
      kind == TripPushEventKind.scheduled ||
      kind == TripPushEventKind.tripUpdate ||
      (kind == TripPushEventKind.unknown && requestId != null);

  bool get isCustomerRelevant =>
      kind == TripPushEventKind.accepted ||
      kind == TripPushEventKind.arrived ||
      kind == TripPushEventKind.started ||
      kind == TripPushEventKind.finished ||
      kind == TripPushEventKind.cancelled ||
      kind == TripPushEventKind.scheduled ||
      kind == TripPushEventKind.tripUpdate ||
      (kind == TripPushEventKind.unknown && requestId != null);

  /// يستخرج الحدث من payload FCM أو صف إشعار السيرفر.
  static TripPushEvent parse(Map<String, dynamic> data) {
    final raw = (data['kind'] ?? data['type'] ?? data['event'] ?? '')
        .toString()
        .trim();
    final lower = raw.toLowerCase().replaceAll('-', '_');
    final rid = _readRequestId(data);

    TripPushEventKind kind;
    if (_matches(lower, const [
      'immediate',
      'new_immediate',
      'immediate_request',
      'new_immediate_request',
      'immediate_offer',
      'broadcast',
      'pending_offer',
    ])) {
      kind = TripPushEventKind.immediateOffer;
    } else if (_matches(lower, const [
      'accepted',
      'reserved',
      'driver_accept',
      'driver_accepted',
      'trip_accepted',
      'request_accepted',
    ])) {
      kind = TripPushEventKind.accepted;
    } else if (_matches(lower, const [
      'arrived',
      'driver_arrived',
      'arrival',
    ])) {
      kind = TripPushEventKind.arrived;
    } else if (_matches(lower, const [
      'started',
      'start',
      'running',
      'trip_started',
      'began',
      'trip_running',
    ])) {
      kind = TripPushEventKind.started;
    } else if (_matches(lower, const [
      'finished',
      'complete',
      'completed',
      'trip_finished',
      'trip_complete',
    ])) {
      kind = TripPushEventKind.finished;
    } else if (_matches(lower, const [
      'cancel',
      'cancelled',
      'canceled',
      'removed',
      'declined',
      'rejected',
      'taken_by_other',
    ])) {
      kind = TripPushEventKind.cancelled;
    } else if (_matches(lower, const [
      'sched',
      'scheduled',
      'passenger_ready',
    ])) {
      kind = TripPushEventKind.scheduled;
    } else if (_matches(lower, const [
      'trip',
      'request',
      'status',
      'update',
    ])) {
      kind = TripPushEventKind.tripUpdate;
    } else if (rid != null) {
      kind = TripPushEventKind.tripUpdate;
    } else {
      kind = TripPushEventKind.unknown;
    }

    return TripPushEvent(
      kind: kind,
      rawKind: raw,
      requestId: rid,
      data: data,
    );
  }

  static int? _readRequestId(Map<String, dynamic> data) {
    for (final k in const [
      'request_id',
      'requestId',
      'trip_id',
      'tripId',
      'id',
    ]) {
      final v = data[k];
      if (v == null) continue;
      final id = v is int ? v : int.tryParse(v.toString());
      if (id != null && id > 0) return id;
    }
    return null;
  }

  static bool _matches(String lower, List<String> needles) {
    if (lower.isEmpty) return false;
    for (final n in needles) {
      if (lower == n || lower.contains(n)) return true;
    }
    return false;
  }
}
