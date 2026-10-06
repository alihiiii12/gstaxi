/** يطابق lib/core/utils/category_trip_fare_client.dart */

export function parseMoneyField(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === 'number' && !Number.isNaN(v)) return v;
  const n = parseFloat(String(v).replace(/,/g, '').trim());
  return Number.isNaN(n) ? null : n;
}

export function categoryTripFareKmMinutesOnly(
  carType: Record<string, unknown>,
  km: number,
  durationMinutes: number | null,
): number | null {
  if (km <= 0) return null;
  const kmP = parseMoneyField(carType.KMPrice ?? carType.km_price);
  const minP = parseMoneyField(carType.timePrice ?? carType.time_price);
  let fare = 0;
  if (kmP != null && kmP > 0) fare += km * kmP;
  if (
    minP != null &&
    minP > 0 &&
    durationMinutes != null &&
    durationMinutes > 0
  ) {
    fare += durationMinutes * minP;
  }
  return fare > 0 ? fare : null;
}

function carTypeFromRow(r: Record<string, unknown>): Record<string, unknown> | null {
  const ct = r.carType ?? r.car_type ?? r.transType ?? r.trans_type;
  if (ct && typeof ct === 'object') return ct as Record<string, unknown>;
  return null;
}

function tripKm(r: Record<string, unknown>): number | null {
  const keys = [
    'estimatedTripKm',
    'estimated_trip_km',
    'trip_distance_km',
    'distance_km',
    'road_distance_km',
  ];
  for (const k of keys) {
    const n = parseMoneyField(r[k]);
    if (n != null && n > 0) return n;
  }
  return null;
}

function tripMinutes(r: Record<string, unknown>): number | null {
  const keys = [
    'estimatedDurationMinutes',
    'estimated_duration_minutes',
    'duration_minutes',
  ];
  for (const k of keys) {
    const n = parseMoneyField(r[k]);
    if (n != null && n > 0) return n;
  }
  return null;
}

function isFreeMeterRow(r: Record<string, unknown>): boolean {
  const bk = String(r.billing_kind ?? r.billingKind ?? '')
    .trim()
    .toLowerCase();
  return bk === 'free_meter';
}

/** نفس السعر على بطاقة الزبون (مقرب) — طلب التطبيق فقط، لا العداد الحر. */
export function requestCategoryFareLirasRounded(
  r: Record<string, unknown>,
): number | null {
  if (isFreeMeterRow(r)) return null;

  for (const k of [
    'customerQuotedFare',
    'customer_quoted_fare',
    'quotedFare',
    'quoted_fare',
  ]) {
    const n = parseMoneyField(r[k]);
    if (n != null && n > 0) return Math.round(n);
  }
  const ct = carTypeFromRow(r);
  const km = tripKm(r);
  if (ct && km != null) {
    const fare = categoryTripFareKmMinutesOnly(ct, km, tripMinutes(r));
    const zm = parseMoneyField(r.zone_multiplier);
    if (fare != null && fare > 0) return Math.round(fare * (zm != null && zm > 0 ? zm : 1));
  }
  const pred = parseMoneyField(
    r.predectedCost ?? r.predected_cost ?? r.predictedCost,
  );
  if (pred != null && pred > 0) return Math.round(pred);
  return null;
}
