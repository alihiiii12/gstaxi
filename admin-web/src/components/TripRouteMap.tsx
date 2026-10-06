import { useMemo, useState } from 'react';
import {
  APP_ROUTE_COLOR,
  AppStyleMap,
  type AppMapLine,
  type AppMapMarker,
} from './AppStyleMap';
import type { LatLngTuple } from '../util/requestRouteMap';

const DEFAULT_CENTER: LatLngTuple = [33.5138, 36.2765];

export type TripMapPoint = {
  position: LatLngTuple;
  title: string;
  detail?: string;
  kind?: 'pickup' | 'dest' | 'accept' | 'actual_start' | 'actual_end' | 'driver';
};

type Props = {
  height?: number;
  loading?: boolean;
  error?: string;
  statusHint?: string;
  pickup: LatLngTuple | null;
  dest: LatLngTuple | null;
  routePoints: LatLngTuple[];
  actualRoutePoints?: LatLngTuple[];
  acceptToPickupRoute?: LatLngTuple[];
  pickupLabel?: string;
  destLabel?: string;
  driverLive?: LatLngTuple | null;
  driverLabel?: string;
  extraPoints?: TripMapPoint[];
  legend?: string;
};

function emojiForKind(kind?: TripMapPoint['kind']): string {
  switch (kind) {
    case 'dest':
      return '🚩';
    case 'accept':
      return '📍';
    case 'actual_start':
      return '▶️';
    case 'actual_end':
      return '⏹️';
    case 'driver':
      return '🚕';
    case 'pickup':
    default:
      return '🟢';
  }
}

/** خريطة مسار رحلة بنفس ستايل التطبيق (MapLibre). */
export function TripRouteMap({
  height = 280,
  loading = false,
  error = '',
  statusHint = '',
  pickup,
  dest,
  routePoints,
  actualRoutePoints = [],
  acceptToPickupRoute = [],
  pickupLabel = '',
  destLabel = '',
  driverLive = null,
  driverLabel = 'موقع السائق الآن',
  extraPoints = [],
  legend = '',
}: Props) {
  const [night, setNight] = useState(false);

  const fitPoints = useMemo(() => {
    const pts = [
      ...routePoints,
      ...actualRoutePoints,
      ...acceptToPickupRoute,
    ];
    if (pickup) pts.push(pickup);
    if (dest) pts.push(dest);
    if (driverLive) pts.push(driverLive);
    for (const p of extraPoints) pts.push(p.position);
    return pts;
  }, [
    routePoints,
    actualRoutePoints,
    acceptToPickupRoute,
    pickup,
    dest,
    driverLive,
    extraPoints,
  ]);

  const lines = useMemo(() => {
    const out: AppMapLine[] = [];
    if (routePoints.length >= 2) {
      out.push({
        id: 'planned',
        positions: routePoints,
        color: APP_ROUTE_COLOR,
        width: 5,
        casing: true,
      });
    }
    if (actualRoutePoints.length >= 2) {
      out.push({
        id: 'actual',
        positions: actualRoutePoints,
        color: '#dc2626',
        width: 5,
        casing: true,
      });
    }
    if (acceptToPickupRoute.length >= 2) {
      out.push({
        id: 'accept',
        positions: acceptToPickupRoute,
        color: '#ca8a04',
        width: 4,
        dashArray: [1.2, 1.2],
        casing: false,
      });
    }
    return out;
  }, [routePoints, actualRoutePoints, acceptToPickupRoute]);

  const markers = useMemo(() => {
    const out: AppMapMarker[] = [];
    if (pickup) {
      out.push({
        id: 'pickup',
        position: pickup,
        emoji: '🟢',
        title: 'انطلاق',
        detail: pickupLabel || undefined,
      });
    }
    if (dest) {
      out.push({
        id: 'dest',
        position: dest,
        emoji: '🚩',
        title: 'وجهة',
        detail: destLabel || undefined,
      });
    }
    extraPoints.forEach((p, i) => {
      out.push({
        id: `xp-${i}`,
        position: p.position,
        emoji: emojiForKind(p.kind),
        title: p.title,
        detail: p.detail,
      });
    });
    if (driverLive) {
      out.push({
        id: 'driver',
        position: driverLive,
        emoji: '🚕',
        title: driverLabel,
        size: 24,
      });
    }
    return out;
  }, [
    pickup,
    dest,
    pickupLabel,
    destLabel,
    extraPoints,
    driverLive,
    driverLabel,
  ]);

  const hasAnything =
    pickup ||
    dest ||
    routePoints.length > 0 ||
    actualRoutePoints.length > 0 ||
    driverLive ||
    extraPoints.length > 0;

  const fitToken = useMemo(
    () =>
      `${routePoints.length}-${actualRoutePoints.length}-${pickup?.join(',') ?? ''}-${dest?.join(',') ?? ''}`,
    [routePoints.length, actualRoutePoints.length, pickup, dest],
  );

  return (
    <div>
      {loading && (
        <p className="text-muted" style={{ fontSize: 13, marginBottom: 8 }}>
          جاري تحميل المسار على الخريطة…
        </p>
      )}
      {error && !loading && (
        <p className="text-err" style={{ marginBottom: 8 }}>
          {error}
        </p>
      )}
      {statusHint && !loading && !error && (
        <p className="text-muted" style={{ fontSize: 13, marginBottom: 8 }}>
          {statusHint}
        </p>
      )}
      {(legend || hasAnything) && !loading && (
        <div
          className="row-between wrap"
          style={{ gap: 8, marginBottom: 8, alignItems: 'center' }}
        >
          {legend ? (
            <p className="text-muted" style={{ fontSize: 12, margin: 0 }}>
              {legend}
            </p>
          ) : (
            <span />
          )}
          {hasAnything && (
            <button
              type="button"
              className="btn-ghost"
              style={{ fontSize: 12, padding: '4px 10px' }}
              onClick={() => setNight((v) => !v)}
            >
              {night ? 'وضع نهار' : 'وضع ليل'}
            </button>
          )}
        </div>
      )}
      {!hasAnything && !loading && !error && (
        <p className="text-muted">لا تتوفر إحداثيات لعرض المسار على الخريطة.</p>
      )}
      {hasAnything && (
        <div className="map-wrap" style={{ marginTop: 4 }}>
          <AppStyleMap
            height={height}
            center={fitPoints[0] ?? DEFAULT_CENTER}
            zoom={13}
            pitch={48}
            night={night}
            lines={lines}
            markers={markers}
            fitPoints={fitPoints}
            fitToken={fitToken}
            followPos={driverLive}
          />
        </div>
      )}
    </div>
  );
}
