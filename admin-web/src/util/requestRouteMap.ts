import { API } from '../api/endpoints';
import { fetchJsonAuth, postJson } from '../api/http';
import { pickupDestLabelsFromRequest } from './requestDetailFields';

export type LatLngTuple = [number, number];

export function latLngFromLocationField(raw: unknown): LatLngTuple | null {
  if (!raw || typeof raw !== 'object') return null;
  const m = raw as Record<string, unknown>;
  const lat = Number(m.latitude ?? m.lat);
  const lng = Number(m.longitude ?? m.lng ?? m.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return [lat, lng];
}

/** انطلاق ووجهة من صف طلب (قائمة أو تفاصيل). */
export function pickupDestFromRequest(
  r: Record<string, unknown>,
): { pickup: LatLngTuple | null; dest: LatLngTuple | null } {
  const start = r.start_location ?? r.startLocation;
  const destRaw = r.dest_location ?? r.destLocation;
  return {
    pickup: latLngFromLocationField(start),
    dest: latLngFromLocationField(destRaw),
  };
}

/** `[[lng,lat], ...]` من OSRM / Laravel */
export function parseRoutePointsGeoJson(raw: unknown): LatLngTuple[] {
  if (!Array.isArray(raw) || raw.length === 0) return [];
  const out: LatLngTuple[] = [];
  for (const e of raw) {
    if (!Array.isArray(e) || e.length < 2) continue;
    const a = e[0];
    const b = e[1];
    if (typeof a !== 'number' || typeof b !== 'number') continue;
    out.push([b, a]);
  }
  return out;
}

/** مسار على الطرق عبر نفس API التطبيق. */
export async function fetchDrivingRoutePoints(
  from: LatLngTuple,
  to: LatLngTuple,
): Promise<LatLngTuple[] | null> {
  try {
    const { res, data } = await postJson<Record<string, unknown>>(
      API.drivingSummary,
      {
        from_lat: from[0],
        from_lng: from[1],
        to_lat: to[0],
        to_lng: to[1],
      },
    );
    if (!res.ok || data.success !== true) return null;
    const d = data.data;
    if (!d || typeof d !== 'object') return null;
    const pts = parseRoutePointsGeoJson(
      (d as Record<string, unknown>).route_points,
    );
    return pts.length >= 2 ? pts : null;
  } catch {
    return null;
  }
}

export async function fetchRequestDetail(
  requestId: number,
): Promise<Record<string, unknown> | null> {
  try {
    const { res, data: j } = await fetchJsonAuth(API.adminRequestDetail(requestId));
    if (!res.ok || j.success !== true) return null;
    const d = j.data;
    if (d && typeof d === 'object') return d as Record<string, unknown>;
    return null;
  } catch {
    return null;
  }
}

/** يبني نقاط العرض: مسار الطرق أو خط مستقيم بين الانطلاق والوجهة. */
export async function buildTripRouteOverlay(
  request: Record<string, unknown>,
): Promise<{
  pickup: LatLngTuple | null;
  dest: LatLngTuple | null;
  routePoints: LatLngTuple[];
  actualRoutePoints: LatLngTuple[];
  acceptToPickupRoute: LatLngTuple[];
  pickupLabel: string;
  destLabel: string;
  driverLive: LatLngTuple | null;
  extraPoints: {
    position: LatLngTuple;
    title: string;
    detail?: string;
    kind?: 'pickup' | 'dest' | 'accept' | 'actual_start' | 'actual_end' | 'driver';
  }[];
  analytics: Record<string, unknown> | null;
}> {
  let { pickup, dest } = pickupDestFromRequest(request);
  let labelSource: Record<string, unknown> = request;
  let analytics =
    (request.trip_analytics as Record<string, unknown> | undefined) ?? null;

  if (!pickup || !dest || !analytics) {
    const id = parseInt(String(request.id ?? 0), 10);
    if (id > 0) {
      const full = await fetchRequestDetail(id);
      if (full) {
        labelSource = full;
        const pd = pickupDestFromRequest(full);
        pickup = pickup ?? pd.pickup;
        dest = dest ?? pd.dest;
        analytics =
          (full.trip_analytics as Record<string, unknown> | undefined) ??
          analytics;
      }
    }
  }

  let routePoints: LatLngTuple[] = [];
  if (pickup && dest) {
    const road = await fetchDrivingRoutePoints(pickup, dest);
    routePoints = road ?? [pickup, dest];
  } else if (pickup) {
    routePoints = [pickup];
  } else if (dest) {
    routePoints = [dest];
  }

  const { pickup: pickupLabel, dest: destLabel } =
    pickupDestLabelsFromRequest(labelSource);

  let driverLive: LatLngTuple | null = null;
  const live =
    (labelSource.driver_live as Record<string, unknown> | undefined) ??
    (request.driver_live as Record<string, unknown> | undefined);
  if (live) {
    const lat = Number(live.latitude ?? live.lat);
    const lng = Number(live.longitude ?? live.lng ?? live.lon);
    if (Number.isFinite(lat) && Number.isFinite(lng)) {
      driverLive = [lat, lng];
    }
  }

  const actualRoutePoints: LatLngTuple[] = [];
  const rawActual = analytics?.actual_route_points;
  if (Array.isArray(rawActual)) {
    for (const e of rawActual) {
      if (!Array.isArray(e) || e.length < 2) continue;
      const lng = Number(e[0]);
      const lat = Number(e[1]);
      if (Number.isFinite(lat) && Number.isFinite(lng)) {
        actualRoutePoints.push([lat, lng]);
      }
    }
  }

  const extraPoints: {
    position: LatLngTuple;
    title: string;
    detail?: string;
    kind?: 'pickup' | 'dest' | 'accept' | 'actual_start' | 'actual_end' | 'driver';
  }[] = [];

  const acceptPt = latLngFromLocationField(analytics?.accept_point);
  if (acceptPt) {
    extraPoints.push({
      position: acceptPt,
      title: 'نقطة قبول الطلب',
      detail: analytics?.accepted_at
        ? `وقت القبول: ${formatIsoAr(String(analytics.accepted_at))}`
        : undefined,
      kind: 'accept',
    });
  }

  const actualStart = latLngFromLocationField(analytics?.actual_start_point);
  if (actualStart) {
    extraPoints.push({
      position: actualStart,
      title: 'بداية الرحلة الفعلية',
      detail: analytics?.trip_started_at
        ? `وقت البداية: ${formatIsoAr(String(analytics.trip_started_at))}`
        : undefined,
      kind: 'actual_start',
    });
  }

  const actualEnd = latLngFromLocationField(analytics?.actual_end_point);
  if (actualEnd) {
    extraPoints.push({
      position: actualEnd,
      title: 'نهاية الرحلة الفعلية',
      detail: analytics?.trip_ended_at
        ? `وقت النهاية: ${formatIsoAr(String(analytics.trip_ended_at))}`
        : undefined,
      kind: 'actual_end',
    });
  }

  let acceptToPickupRoute: LatLngTuple[] = [];
  if (acceptPt && pickup) {
    const road = await fetchDrivingRoutePoints(acceptPt, pickup);
    acceptToPickupRoute = road ?? [acceptPt, pickup];
  }

  return {
    pickup,
    dest,
    routePoints,
    actualRoutePoints,
    acceptToPickupRoute,
    pickupLabel,
    destLabel,
    driverLive,
    extraPoints,
    analytics,
  };
}

function formatIsoAr(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString('ar-SY');
}

