export function recordFromJsonMaybe(v: unknown): Record<string, unknown> | undefined {
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    return v as Record<string, unknown>;
  }
  if (typeof v === 'string') {
    const t = v.trim();
    if (!t) return undefined;
    try {
      const p = JSON.parse(t) as unknown;
      if (p && typeof p === 'object' && !Array.isArray(p)) {
        return p as Record<string, unknown>;
      }
    } catch {
      return undefined;
    }
  }
  return undefined;
}

/** قراءة history ككائن (نص JSON أو كائن). */
function requestHistoryMap(
  r: Record<string, unknown>,
): Record<string, unknown> | undefined {
  return (
    recordFromJsonMaybe(r.history) ?? recordFromJsonMaybe(r.History) ?? undefined
  );
}

function numish(v: unknown): number {
  if (typeof v === 'number' && !Number.isNaN(v)) return v;
  const n = parseFloat(String(v ?? '').replace(/,/g, ''));
  return Number.isNaN(n) ? 0 : n;
}

/** تسمية مسار الرحلة: تطبيق vs عداد حر (مع دعم حقول صريحة من الخادم). */
export function tripPathLabelArabic(r: Record<string, unknown>): string {
  const raw = String(
    r.billingKind ??
      r.billing_kind ??
      r.requestBilling ??
      r.request_billing ??
      r.tripSource ??
      r.trip_source ??
      '',
  ).trim()
    .toLowerCase();
  if (raw.includes('free_meter') || raw.includes('freemeter') || raw === 'taximeter') {
    return 'رحلة عداد حر';
  }
  if (
    raw.includes('app') ||
    raw.includes('application') ||
    raw === 'store_request' ||
    raw === 'app_request'
  ) {
    return 'رحلة طلب عبر التطبيق';
  }

  const fm = r.isFreeMeterTrip ?? r.free_meter_trip ?? r.isTaximeter ?? r.is_taximeter;
  if (fm === true || fm === 1 || String(fm).toLowerCase() === 'true') {
    return 'رحلة عداد حر';
  }

  const fromApp = r.fromApp ?? r.from_app ?? r.isAppRequest ?? r.is_app_request;
  if (fromApp === false || fromApp === 0 || String(fromApp).toLowerCase() === 'false') {
    return 'رحلة عداد حر';
  }

  const uid = r.userId ?? r.user_id;
  const hasCustomer =
    uid != null && String(uid).trim() !== '' && parseInt(String(uid), 10) > 0;
  if (hasCustomer) {
    return 'رحلة طلب عبر التطبيق';
  }

  return 'غير محدد — راجع الحقول billing_kind أو userId في الـ API';
}

/** شرح مالي/تشغيلي لرحلة العداد الحر مقابل طلب التطبيق. */
export function tripFinancialDetailArabic(r: Record<string, unknown>): string {
  const path = tripPathLabelArabic(r);
  if (path.includes('تطبيق')) {
    return 'تُسعَّر وتُسجَّل عبر مسار طلب التطبيق (فئة السيارة، الوجهة، التكلفة النهائية في سجل الطلب).';
  }

  const counts = r.freeMeterCountsForRevenue ?? r.free_meter_counts_for_revenue;
  if (counts === false || String(counts).toLowerCase() === 'false') {
    return 'عداد حر: توقف على السعر الافتتاحي فقط دون حركة كافية — لا تُحسب كرحلة حركة بالعداد في الإيراد حسب السياسة.';
  }

  const hist = requestHistoryMap(r);
  const dist = numish(
    hist?.distanceTraveledKm ??
      hist?.distance_traveled_km ??
      hist?.distanceTraveled ??
      hist?.distance_traveled ??
      hist?.distanceKm ??
      hist?.distance_km ??
      r.distanceTraveledKm ??
      r.distance_traveled_km ??
      r.distanceTraveled ??
      r.distance_traveled,
  );

  const movedExplicit = r.freeMeterHadMovement ?? r.free_meter_had_movement;
  if (movedExplicit === true || movedExplicit === 1) {
    return 'عداد حر: وُجدت حركة مسجّلة — تُحسب كرحلة عداد حر (كم/دقيقة حسب إعدادات العداد).';
  }
  if (movedExplicit === false || movedExplicit === 0) {
    return 'عداد حر: لم تُسجَّل حركة كافية — يبقى على السعر الافتتاحي ولا يُحسب كمشي بالعداد.';
  }

  if (dist > 0.001) {
    return `عداد حر: مسافة مسجّلة تقريباً ${dist.toFixed(3)} كم — تُحسب كرحلة بعداد الحر.`;
  }

  if (String(r.status ?? '') === 'Finished') {
    return 'إن كانت رحلة عداد حر: انتهت دون مسافة مسجّلة — غالباً توقف على السعر الافتتاحي فقط (لا تُحسب كحركة).';
  }

  return 'رحلة عداد حر: انتظر بيانات الحركة/المسافة من الخادم أو راجع تفاصيل السائق.';
}
