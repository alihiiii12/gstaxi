import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import {
  APP_ROUTE_COLOR,
  AppStyleMap,
  type AppMapLine,
  type AppMapMarker,
} from '../components/AppStyleMap';
import { API } from '../api/endpoints';
import { authHeaders, fetchJsonAuth, postJson } from '../api/http';
import { staffHas, useAuth } from '../auth/AuthContext';
import { PageHeader } from '../components/PageHeader';
import { statusArabic } from '../util/adminRequestLabels';
import { pickupDestLabelsFromRequest } from '../util/requestDetailFields';
import {
  buildTripRouteOverlay,
  type LatLngTuple,
} from '../util/requestRouteMap';

const DEFAULT_CENTER: [number, number] = [33.5138, 36.2765];

function driverLiveFromTrip(trip: Record<string, unknown> | null): LatLngTuple | null {
  if (!trip) return null;
  const live = trip.driver_live as Record<string, unknown> | undefined;
  if (live) {
    const lat = Number(live.latitude ?? live.lat);
    const lng = Number(live.longitude ?? live.lng ?? live.lon);
    if (Number.isFinite(lat) && Number.isFinite(lng)) return [lat, lng];
  }
  return null;
}

type SosLiveState = {
  pos: LatLngTuple;
  sosPos: LatLngTuple | null;
  trail: LatLngTuple[];
  updatedAtMs: number | null;
  source: string;
  role: string;
  name: string;
  number: string;
  personId: string;
};

const SOS_LIVE_POLL_MS = 3000;

const SOS_SOURCE_LABEL: Record<string, string> = {
  sos_app: 'تطبيق الطوارئ',
  driver_gps: 'GPS السائق',
  customer_app: 'تطبيق الراكب',
  sos_initial: 'موقع الإرسال',
};

function sameLatLng(a: LatLngTuple | null, b: LatLngTuple | null): boolean {
  if (!a || !b) return a === b;
  return Math.abs(a[0] - b[0]) < 0.000005 && Math.abs(a[1] - b[1]) < 0.000005;
}

function formatAgo(sec: number): string {
  if (sec < 60) return `${sec} ث`;
  const m = Math.floor(sec / 60);
  if (m < 60) return `${m} د`;
  return `${Math.floor(m / 60)} س ${m % 60} د`;
}

function driverDisplayName(m: Record<string, unknown>, fallbackId: number): string {
  const name = String(m.name ?? '').trim();
  if (name) return name;
  const id = m.driver_id ?? m.driverId ?? fallbackId;
  return `سائق #${id}`;
}

type DriverStatus = 'available' | 'to_pickup' | 'on_trip';

const DRIVER_STATUS: Record<DriverStatus, { label: string; color: string }> = {
  available: { label: 'متاح', color: '#16a34a' },
  to_pickup: { label: 'متجه للراكب', color: '#f59e0b' },
  on_trip: { label: 'في رحلة', color: '#dc2626' },
};

const DRIVER_STATUS_ORDER: DriverStatus[] = ['available', 'to_pickup', 'on_trip'];

function driverStatusOf(m: Record<string, unknown>): DriverStatus {
  const s = String(m.status ?? '');
  return s === 'on_trip' || s === 'to_pickup' ? s : 'available';
}

function driverPopupDetail(m: Record<string, unknown>, fallbackId: number): string {
  const id = m.driver_id ?? m.driverId ?? fallbackId;
  const car = String(m.carNumber ?? m.car_number ?? '').trim();
  const phone = String(m.number ?? '').trim();
  const st = driverStatusOf(m);
  const tripId = Number(m.trip_id ?? 0);
  const freeMeter = String(m.billing_kind ?? '') === 'free_meter';
  const parts = [
    `الحالة: ${DRIVER_STATUS[st].label}${st === 'on_trip' && freeMeter ? ' (عداد حر)' : ''}${tripId > 0 ? ` — طلب #${tripId}` : ''}`,
    `معرف السائق: #${id}`,
  ];
  if (car) parts.push(`رقم السيارة: ${car}`);
  if (phone) parts.push(`الهاتف: ${phone}`);
  const seen = m.last_seen_sec;
  if (typeof seen === 'number' && seen >= 0) parts.push(`آخر موقع: قبل ${formatAgo(seen)}`);
  return parts.join(' · ');
}

export function MapPage() {
  const { user } = useAuth();
  const canCancelTrip =
    user != null &&
    staffHas(user.roll, user.permissions, 'requests.write');
  const [searchParams, setSearchParams] = useSearchParams();
  const [data, setData] = useState<Record<string, unknown> | null>(null);
  const [err, setErr] = useState('');
  const [tick, setTick] = useState(0);
  const [cancellingId, setCancellingId] = useState<number | null>(null);

  const [selectedTripId, setSelectedTripId] = useState<number | null>(null);
  const [routeLoading, setRouteLoading] = useState(false);
  const [routeErr, setRouteErr] = useState('');
  const [tripPickup, setTripPickup] = useState<LatLngTuple | null>(null);
  const [tripDest, setTripDest] = useState<LatLngTuple | null>(null);
  const [tripRoutePoints, setTripRoutePoints] = useState<LatLngTuple[]>([]);
  const [tripActualRoute, setTripActualRoute] = useState<LatLngTuple[]>([]);
  const [tripAcceptRoute, setTripAcceptRoute] = useState<LatLngTuple[]>([]);
  const [tripExtraPoints, setTripExtraPoints] = useState<
    {
      position: LatLngTuple;
      title: string;
      detail?: string;
      kind?: string;
    }[]
  >([]);
  const [tripPickupLabel, setTripPickupLabel] = useState('');
  const [tripDestLabel, setTripDestLabel] = useState('');
  const [tripDriverLive, setTripDriverLive] = useState<LatLngTuple | null>(null);
  const [liveWatching, setLiveWatching] = useState(false);
  const [watchEndedMsg, setWatchEndedMsg] = useState('');
  const [fitToken, setFitToken] = useState(0);
  const [mapFullscreen, setMapFullscreen] = useState(false);
  const [mapNight, setMapNight] = useState(false);
  const [hiddenStatuses, setHiddenStatuses] = useState<Set<DriverStatus>>(() => new Set());
  const mapSectionRef = useRef<HTMLDivElement | null>(null);
  const routeFitPointsRef = useRef<LatLngTuple[]>([]);
  const watchingTripIdRef = useRef<number | null>(null);

  const exitTripWatch = useCallback((endedMsg = '') => {
    watchingTripIdRef.current = null;
    setSelectedTripId(null);
    setRouteErr('');
    setTripRoutePoints([]);
    setTripActualRoute([]);
    setTripAcceptRoute([]);
    setTripExtraPoints([]);
    setTripPickup(null);
    setTripDest(null);
    setTripPickupLabel('');
    setTripDestLabel('');
    setTripDriverLive(null);
    setLiveWatching(false);
    setFitToken(0);
    routeFitPointsRef.current = [];
    setWatchEndedMsg(endedMsg);
  }, []);

  const focusSosDriverId = useMemo(() => {
    const raw = searchParams.get('sosDriver') ?? searchParams.get('driverId') ?? '';
    const n = parseInt(String(raw), 10);
    return Number.isFinite(n) && n > 0 ? n : null;
  }, [searchParams]);

  const focusSosKey = useMemo(() => {
    const raw = (searchParams.get('sosKey') ?? '').trim();
    return raw || null;
  }, [searchParams]);

  const sosFollowKey =
    focusSosKey ?? (focusSosDriverId ? String(focusSosDriverId) : null);
  const [sosLive, setSosLive] = useState<SosLiveState | null>(null);
  const [sosLiveEnded, setSosLiveEnded] = useState(false);
  const [sosLiveErr, setSosLiveErr] = useState('');
  const [sosRecenter, setSosRecenter] = useState(0);
  const [nowMs, setNowMs] = useState(() => Date.now());

  useEffect(() => {
    setSosLive(null);
    setSosLiveEnded(false);
    setSosLiveErr('');
    if (!sosFollowKey) return;
    let stopped = false;
    let timer = 0;
    const poll = async () => {
      try {
        const { res, data: j } = await fetchJsonAuth(API.sosLive(sosFollowKey));
        if (stopped) return;
        if (!res.ok || j.success !== true) {
          throw new Error(String(j.message ?? res.statusText));
        }
        const d = (j.data as Record<string, unknown>) ?? {};
        if (d.active !== true) {
          setSosLiveEnded(true);
          setSosLiveErr('');
          return;
        }
        const lat = Number(d.latitude);
        const lng = Number(d.longitude);
        if (Number.isFinite(lat) && Number.isFinite(lng)) {
          const sLat = Number(d.sos_latitude);
          const sLng = Number(d.sos_longitude);
          const trail = (Array.isArray(d.trail) ? d.trail : [])
            .map((p) => (Array.isArray(p) ? [Number(p[0]), Number(p[1])] : null))
            .filter(
              (p): p is LatLngTuple =>
                p != null && Number.isFinite(p[0]) && Number.isFinite(p[1]),
            );
          const updated = d.updated_at ? Date.parse(String(d.updated_at)) : NaN;
          const role = String(d.role ?? 'driver').toLowerCase();
          const next: SosLiveState = {
            pos: [lat, lng],
            sosPos:
              Number.isFinite(sLat) && Number.isFinite(sLng) ? [sLat, sLng] : null,
            trail,
            updatedAtMs: Number.isFinite(updated) ? updated : null,
            source: String(d.source ?? ''),
            role,
            name: String(d.name ?? '').trim(),
            number: String(d.number ?? '').trim(),
            personId: String(
              (role === 'customer' ? d.customerId : d.driverId) ?? '',
            ),
          };
          setSosLive((prev) =>
            prev &&
            sameLatLng(prev.pos, next.pos) &&
            prev.trail.length === next.trail.length &&
            prev.updatedAtMs === next.updatedAtMs
              ? prev
              : { ...next, pos: prev && sameLatLng(prev.pos, next.pos) ? prev.pos : next.pos },
          );
        }
        setSosLiveErr('');
      } catch (e) {
        if (!stopped) setSosLiveErr(String(e));
      }
      if (!stopped) timer = window.setTimeout(() => void poll(), SOS_LIVE_POLL_MS);
    };
    void poll();
    return () => {
      stopped = true;
      window.clearTimeout(timer);
    };
  }, [sosFollowKey]);

  useEffect(() => {
    if (!sosFollowKey || sosLiveEnded) return;
    const id = window.setInterval(() => setNowMs(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, [sosFollowKey, sosLiveEnded]);

  const load = useCallback(async () => {
    setErr('');
    try {
      const { res, data: j } = await fetchJsonAuth(API.adminMapSnapshot);
      if (!res.ok || j.success !== true) {
        throw new Error(String(j.message ?? res.statusText));
      }
      setData((j.data as Record<string, unknown>) ?? {});
    } catch (e) {
      setErr(String(e));
      // لا نمسح البيانات السابقة حتى لا نخرج من متابعة الرحلة عند فشل لقطة مؤقتة
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load, tick]);

  /** لقطة عامة للقائمة — كل 15 ثانية (ليست متابعة مباشرة للرحلة) */
  useEffect(() => {
    const id = window.setInterval(() => setTick((n) => n + 1), 15000);
    return () => window.clearInterval(id);
  }, []);

  /**
   * متابعة مباشرة عبر بث السيرفر (SSE) — بدون إعادة تحميل الخريطة كل ثانية/ثانيتين.
   * الموقع يتحرك فقط عند تغيّر موقع السائق أو حالة الرحلة.
   */
  useEffect(() => {
    if (!liveWatching || !selectedTripId || routeLoading) return;
    const tripId = selectedTripId;
    const ac = new AbortController();
    let buffer = '';

    void (async () => {
      try {
        const res = await fetch(API.adminRunningTripLiveStream(tripId), {
          headers: {
            ...authHeaders(),
            Accept: 'text/event-stream',
          },
          signal: ac.signal,
        });
        if (!res.ok || !res.body) {
          // احتياطي: نبضة خفيفة كل 5 ثوانٍ إن فشل البث
          while (!ac.signal.aborted && watchingTripIdRef.current === tripId) {
            try {
              const { res: r2, data: j } = await fetchJsonAuth(
                API.adminRunningTripLive(tripId),
              );
              if (r2.ok && j.success === true && j.data && typeof j.data === 'object') {
                const d = j.data as Record<string, unknown>;
                const live = driverLiveFromTrip({ driver_live: d.driver_live });
                if (live) {
                  setTripDriverLive(live);
                  setTripActualRoute((prev) => {
                    if (prev.length === 0) return [live];
                    const last = prev[prev.length - 1];
                    if (
                      Math.abs(last[0] - live[0]) < 0.00008 &&
                      Math.abs(last[1] - live[1]) < 0.00008
                    ) {
                      return prev;
                    }
                    return [...prev, live];
                  });
                }
                if (d.ended === true) {
                  exitTripWatch(`انتهت الرحلة #${tripId} — أُغلقت المتابعة المباشرة.`);
                  break;
                }
              }
            } catch {
              /* ignore */
            }
            await new Promise((r) => window.setTimeout(r, 5000));
          }
          return;
        }

        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        while (!ac.signal.aborted) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          const parts = buffer.split('\n\n');
          buffer = parts.pop() ?? '';
          for (const chunk of parts) {
            const line = chunk
              .split('\n')
              .map((l) => l.trim())
              .find((l) => l.startsWith('data:'));
            if (!line) continue;
            try {
              const d = JSON.parse(line.slice(5).trim()) as Record<string, unknown>;
              if (watchingTripIdRef.current !== tripId) return;
              const live = driverLiveFromTrip({ driver_live: d.driver_live });
              if (live) {
                setTripDriverLive(live);
                setTripActualRoute((prev) => {
                  if (prev.length === 0) return [live];
                  const last = prev[prev.length - 1];
                  if (
                    Math.abs(last[0] - live[0]) < 0.00005 &&
                    Math.abs(last[1] - live[1]) < 0.00005
                  ) {
                    return prev;
                  }
                  return [...prev, live];
                });
              }
              if (d.ended === true) {
                exitTripWatch(`انتهت الرحلة #${tripId} — أُغلقت المتابعة المباشرة.`);
                return;
              }
            } catch {
              /* ignore bad frame */
            }
          }
        }
      } catch (e) {
        if ((e as Error)?.name === 'AbortError') return;
      }
    })();

    return () => ac.abort();
  }, [liveWatching, selectedTripId, routeLoading, exitTripWatch]);

  useEffect(() => {
    if (!mapFullscreen) return;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setMapFullscreen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => {
      document.body.style.overflow = prevOverflow;
      window.removeEventListener('keydown', onKey);
    };
  }, [mapFullscreen]);

  const drivers = (data?.drivers_online as Record<string, unknown>[]) ?? [];
  const driverCounts = useMemo(() => {
    const c: Record<DriverStatus, number> = { available: 0, to_pickup: 0, on_trip: 0 };
    for (const m of drivers) c[driverStatusOf(m)]++;
    return c;
  }, [drivers]);
  const sos = (data?.sos as Record<string, unknown>[]) ?? [];
  const trips = (data?.running_trips as Record<string, unknown>[]) ?? [];

  const selectedTrip = useMemo(() => {
    if (!selectedTripId) return null;
    return (
      trips.find((t) => parseInt(String(t.id ?? 0), 10) === selectedTripId) ??
      null
    );
  }, [trips, selectedTripId]);

  const loadTripRoute = useCallback(async (trip: Record<string, unknown>) => {
    const id = parseInt(String(trip.id ?? 0), 10);
    if (id <= 0) return;
    watchingTripIdRef.current = id;
    setSelectedTripId(id);
    setLiveWatching(true);
    setWatchEndedMsg('');
    setRouteLoading(true);
    setRouteErr('');
    setTripPickup(null);
    setTripDest(null);
    setTripRoutePoints([]);
    setTripActualRoute([]);
    setTripAcceptRoute([]);
    setTripExtraPoints([]);
    setTripPickupLabel('');
    setTripDestLabel('');
    setTripDriverLive(driverLiveFromTrip(trip));
    window.setTimeout(() => {
      mapSectionRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, 50);
    try {
      const overlay = await buildTripRouteOverlay(trip);
      if (watchingTripIdRef.current !== id) return;
      if (!overlay.pickup && !overlay.dest && overlay.extraPoints.length === 0) {
        setRouteErr('لا تتوفر إحداثيات انطلاق/وجهة لهذا الطلب.');
        return;
      }
      setTripPickup(overlay.pickup);
      setTripDest(overlay.dest);
      setTripRoutePoints(overlay.routePoints);
      setTripActualRoute(overlay.actualRoutePoints);
      setTripAcceptRoute(overlay.acceptToPickupRoute);
      setTripExtraPoints(overlay.extraPoints);
      setTripPickupLabel(overlay.pickupLabel);
      setTripDestLabel(overlay.destLabel);
      const live = overlay.driverLive ?? driverLiveFromTrip(trip);
      setTripDriverLive(live);
      const fitPts = [
        ...overlay.routePoints,
        ...overlay.actualRoutePoints,
        ...overlay.acceptToPickupRoute,
      ];
      if (overlay.pickup) fitPts.push(overlay.pickup);
      if (overlay.dest) fitPts.push(overlay.dest);
      if (live) fitPts.push(live);
      for (const p of overlay.extraPoints) fitPts.push(p.position);
      routeFitPointsRef.current = fitPts;
      setFitToken((n) => n + 1);
    } catch (e) {
      if (watchingTripIdRef.current === id) setRouteErr(String(e));
    } finally {
      if (watchingTripIdRef.current === id) setRouteLoading(false);
    }
  }, []);

  async function cancelRunningTrip(id: number) {
    if (!canCancelTrip) return;
    if (
      !window.confirm(
        `إلغاء الرحلة الجارية #${id}؟\nسيتم إبلاغ السائق والراكب بإنهاء الطلب.`,
      )
    ) {
      return;
    }
    setCancellingId(id);
    try {
      const { res, data: j } = await postJson<Record<string, unknown>>(
        API.adminCancelActive(id),
        { reason: 'admin_map_cancel' },
      );
      const ok = res.ok && (j.success === true || j.state === true);
      if (!ok) {
        throw new Error(String(j.message ?? res.statusText));
      }
      if (selectedTripId === id) {
        exitTripWatch();
      }
      await load();
    } catch (e) {
      alert(String(e));
    } finally {
      setCancellingId(null);
    }
  }

  const selectedDriverId = useMemo(() => {
    if (!selectedTrip) return 0;
    return parseInt(String(selectedTrip.driverId ?? selectedTrip.driver_id ?? 0), 10);
  }, [selectedTrip]);

  const isFocusedSos = useCallback(
    (m: Record<string, unknown>) => {
      if (focusSosKey) {
        const key = String(m.redisKey ?? m.redis_key ?? '').trim();
        if (key && key === focusSosKey) return true;
        if (focusSosKey.startsWith('c:')) {
          const uid = parseInt(focusSosKey.slice(2), 10);
          const mid = parseInt(
            String(m.customerId ?? m.customer_id ?? m.userId ?? m.user_id ?? 0),
            10,
          );
          return uid > 0 && mid === uid;
        }
        const did = parseInt(String(m.driverId ?? m.driver_id ?? 0), 10);
        return did > 0 && String(did) === focusSosKey;
      }
      if (focusSosDriverId) {
        const did = parseInt(String(m.driverId ?? m.driver_id ?? 0), 10);
        return did === focusSosDriverId;
      }
      return false;
    },
    [focusSosKey, focusSosDriverId],
  );

  const markers = useMemo(() => {
    const out: AppMapMarker[] = [];
    // عند اختيار رحلة: أخفِ باقي السيارات؛ موقع السائق يُعرض من المتابعة المباشرة
    drivers.forEach((m) => {
      if (selectedTripId && tripDriverLive) return;
      const driverId = Number(m.driverId ?? m.driver_id ?? 0);
      if (selectedTripId && selectedDriverId > 0 && driverId !== selectedDriverId) {
        return;
      }
      if (selectedTripId && selectedDriverId <= 0) {
        return;
      }
      const st = driverStatusOf(m);
      if (!selectedTripId && hiddenStatuses.has(st)) return;
      const lat = Number(m.latitude);
      const lng = Number(m.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
      const fallbackId = driverId > 0 ? driverId : out.length;
      out.push({
        id: `d-${driverId > 0 ? driverId : `${lat}-${lng}`}`,
        position: [lat, lng],
        emoji: '🚕',
        title: `${driverDisplayName(m, fallbackId)} — ${DRIVER_STATUS[st].label}`,
        detail: driverPopupDetail(m, fallbackId),
        size: 20,
        color: DRIVER_STATUS[st].color,
      });
    });
    sos.forEach((m, i) => {
      if (sosLive && isFocusedSos(m)) return;
      const lat = Number(m.latitude);
      const lng = Number(m.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
      const role = String(m.role ?? 'driver').toLowerCase();
      const isCustomer = role === 'customer';
      const sosName = String(m.name ?? m.driver_name ?? '').trim();
      const sosId = isCustomer
        ? (m.customerId ?? m.customer_id ?? m.userId ?? m.user_id ?? i)
        : (m.driver_id ?? m.driverId ?? i);
      const who = isCustomer ? 'راكب' : 'سائق';
      out.push({
        id: `s-${i}-${lat}-${lng}`,
        position: [lat, lng],
        emoji: '🆘',
        title: sosName ? `SOS ${who}: ${sosName}` : `SOS ${who} #${sosId}`,
        detail: isCustomer
          ? `معرف الراكب: #${sosId}`
          : `معرف السائق: #${sosId}`,
        size: 22,
      });
    });
    if (sosLive) {
      const isCustomer = sosLive.role === 'customer';
      const who = isCustomer ? 'راكب' : 'سائق';
      const label = sosLive.name || `#${sosLive.personId}`;
      if (sosLive.sosPos && !sameLatLng(sosLive.sosPos, sosLive.pos)) {
        out.push({
          id: 'sos-origin',
          position: sosLive.sosPos,
          emoji: '📍',
          title: 'مكان إرسال SOS',
          size: 20,
        });
      }
      out.push({
        id: 'sos-live',
        position: sosLive.pos,
        emoji: '🆘',
        title: `SOS ${who}: ${label} — موقع مباشر`,
        detail: [
          isCustomer ? `معرف الراكب: #${sosLive.personId}` : `معرف السائق: #${sosLive.personId}`,
          sosLive.number ? `الهاتف: ${sosLive.number}` : '',
        ]
          .filter(Boolean)
          .join(' · '),
        size: 30,
      });
    }
    return out;
  }, [drivers, sos, selectedTripId, selectedDriverId, tripDriverLive, sosLive, isFocusedSos, hiddenStatuses]);

  const snapshotSosPos = useMemo((): LatLngTuple | null => {
    if (!focusSosDriverId && !focusSosKey) return null;
    for (const m of sos) {
      if (!isFocusedSos(m)) continue;
      const lat = Number(m.latitude);
      const lng = Number(m.longitude);
      if (Number.isFinite(lat) && Number.isFinite(lng)) return [lat, lng];
    }
    return null;
  }, [sos, focusSosDriverId, focusSosKey, isFocusedSos]);

  const flySosPos: LatLngTuple | null = sosLive?.pos ?? snapshotSosPos;

  const showTripOverlay = selectedTripId != null && !focusSosDriverId && !focusSosKey;

  const overlayMarkers = useMemo(() => {
    const out: AppMapMarker[] = [...markers];
    if (!showTripOverlay) return out;
    if (tripPickup) {
      out.push({
        id: 'pickup',
        position: tripPickup,
        emoji: '🟢',
        title: 'انطلاق',
        detail: tripPickupLabel || undefined,
      });
    }
    if (tripDest) {
      out.push({
        id: 'dest',
        position: tripDest,
        emoji: '🚩',
        title: 'وجهة',
        detail: tripDestLabel || undefined,
      });
    }
    tripExtraPoints.forEach((p, i) => {
      out.push({
        id: `xp-${i}`,
        position: p.position,
        emoji: '📍',
        title: p.title,
        detail: p.detail,
      });
    });
    if (tripDriverLive) {
      out.push({
        id: 'live-driver',
        position: tripDriverLive,
        emoji: '🚕',
        title: `موقع السائق — رحلة #${selectedTripId}`,
        size: 24,
      });
    }
    return out;
  }, [
    markers,
    showTripOverlay,
    tripPickup,
    tripDest,
    tripPickupLabel,
    tripDestLabel,
    tripExtraPoints,
    tripDriverLive,
    selectedTripId,
  ]);

  const overlayLines = useMemo(() => {
    if (!showTripOverlay) {
      if (!sosLive) return [] as AppMapLine[];
      const pts = [...sosLive.trail];
      const last = pts[pts.length - 1];
      if (!last || !sameLatLng(last, sosLive.pos)) pts.push(sosLive.pos);
      return pts.length >= 2
        ? [{ id: 'sos-trail', positions: pts, color: '#dc2626', width: 5, casing: true }]
        : ([] as AppMapLine[]);
    }
    const out: AppMapLine[] = [];
    if (tripRoutePoints.length >= 2) {
      out.push({
        id: 'planned',
        positions: tripRoutePoints,
        color: APP_ROUTE_COLOR,
        width: 5,
        casing: true,
      });
    }
    if (tripActualRoute.length >= 2) {
      out.push({
        id: 'actual',
        positions: tripActualRoute,
        color: '#dc2626',
        width: 5,
        casing: true,
      });
    }
    if (tripAcceptRoute.length >= 2) {
      out.push({
        id: 'accept',
        positions: tripAcceptRoute,
        color: '#ca8a04',
        width: 4,
        dashArray: [1.2, 1.2],
        casing: false,
      });
    }
    return out;
  }, [showTripOverlay, tripRoutePoints, tripActualRoute, tripAcceptRoute, sosLive]);

  const mapCenter = flySosPos ?? tripDriverLive ?? overlayMarkers[0]?.position ?? DEFAULT_CENTER;
  const mapFitPoints = showTripOverlay
    ? routeFitPointsRef.current
    : flySosPos
      ? [flySosPos]
      : overlayMarkers.map((m) => m.position);
  // إطار الكاميرا: رحلة/SOS فقط، أو مرة عند أول ظهور للعلامات — بدون زوم عند كل poll
  const mapFitToken = showTripOverlay
    ? fitToken
    : flySosPos
      ? `sos-${sosFollowKey}-${sosRecenter}`
      : overlayMarkers.length > 0
        ? 'ops-browse-init'
        : 0;

  return (
    <div className="page-pad">
      <PageHeader
        title="خريطة العمليات"
        subtitle="السائقون الأونلاين والرحلات الجارية وتنبيهات SOS."
        backTo="/"
        backLabel="الرئيسية"
        onRefresh={() => void load()}
      />
      {err && <p className="text-err">{err}</p>}
      {watchEndedMsg && (
        <p
          className="text-muted"
          style={{
            marginTop: 8,
            padding: '8px 12px',
            borderRadius: 10,
            background: 'rgba(22, 163, 74, 0.08)',
            border: '1px solid rgba(22, 163, 74, 0.2)',
          }}
        >
          {watchEndedMsg}{' '}
          <button
            type="button"
            className="btn-ghost"
            style={{ fontSize: 12, padding: '2px 8px' }}
            onClick={() => setWatchEndedMsg('')}
          >
            حسناً
          </button>
        </p>
      )}
      {sosFollowKey && (sosLive || sosLiveEnded) && (
        <div
          style={{
            marginTop: 10,
            marginBottom: 4,
            padding: '10px 12px',
            borderRadius: 12,
            background: sosLiveEnded ? 'rgba(17, 33, 91, 0.06)' : 'rgba(220, 38, 38, 0.08)',
            border: sosLiveEnded
              ? '1px solid rgba(17, 33, 91, 0.12)'
              : '1px solid rgba(220, 38, 38, 0.3)',
          }}
        >
          <p style={{ margin: 0, fontWeight: 700, fontSize: 14 }}>
            {sosLiveEnded
              ? 'انتهى تنبيه SOS أو أُزيل — توقفت المتابعة المباشرة.'
              : sosLive
                ? `🔴 متابعة مباشرة — SOS ${sosLive.role === 'customer' ? 'راكب' : 'سائق'}: ${
                    sosLive.name || `#${sosLive.personId}`
                  }${sosLive.number ? ` · ${sosLive.number}` : ''}`
                : ''}
          </p>
          {!sosLiveEnded && sosLive && (
            <p className="text-muted" style={{ margin: '6px 0 0', fontSize: 13 }}>
              {sosLive.updatedAtMs
                ? `آخر موقع قبل ${formatAgo(
                    Math.max(0, Math.round((nowMs - sosLive.updatedAtMs) / 1000)),
                  )}`
                : 'آخر موقع: غير معروف'}
              {` · المصدر: ${SOS_SOURCE_LABEL[sosLive.source] ?? sosLive.source}`}
              {' · أحمر = مسار حركته منذ إرسال التنبيه · 📍 = مكان الإرسال'}
              {sosLive.updatedAtMs && nowMs - sosLive.updatedAtMs > 120000
                ? ' — لم يصل موقع جديد منذ فترة (قد يكون التطبيق مغلقاً أو بلا إنترنت).'
                : ''}
              {sosLiveErr ? ` — تعذر التحديث: ${sosLiveErr}` : ''}
            </p>
          )}
          <div style={{ display: 'flex', gap: 8, marginTop: 8, flexWrap: 'wrap' }}>
            {!sosLiveEnded && sosLive && (
              <button
                type="button"
                className="btn-ghost"
                style={{ fontSize: 12 }}
                onClick={() => setSosRecenter((n) => n + 1)}
              >
                توسيط ومتابعة
              </button>
            )}
            <button
              type="button"
              className="btn-ghost"
              style={{ fontSize: 12 }}
              onClick={() => setSearchParams({})}
            >
              خروج من المتابعة
            </button>
          </div>
        </div>
      )}
      {(focusSosDriverId || focusSosKey) && !flySosPos && !sosLiveEnded && !err && (
        <p className="text-muted" style={{ marginTop: 8 }}>
          طلب التركيز على تنبيه SOS
          {focusSosKey
            ? ` (${focusSosKey})`
            : ` سائق #${focusSosDriverId}`}
          : إن لم يظهر الموقع، اضغط «تحديث» — قد يكون التنبيه انتهى أو لم تُبلَّغ إحداثياته بعد.
        </p>
      )}
      {selectedTripId && (
        <div
          style={{
            marginTop: 10,
            marginBottom: 4,
            padding: '10px 12px',
            borderRadius: 12,
            background: liveWatching
              ? 'rgba(220, 38, 38, 0.07)'
              : 'rgba(17, 33, 91, 0.06)',
            border: liveWatching
              ? '1px solid rgba(220, 38, 38, 0.25)'
              : '1px solid rgba(17, 33, 91, 0.12)',
          }}
        >
          <p style={{ margin: 0, fontWeight: 700, fontSize: 14 }}>
            {routeLoading
              ? `جاري فتح المتابعة المباشرة للطلب #${selectedTripId}…`
              : routeErr
                ? routeErr
                : liveWatching
                  ? `متابعة مباشرة — رحلة #${selectedTripId}${
                      selectedTrip
                        ? ` (${statusArabic(String(selectedTrip.status ?? ''), selectedTrip.driverId ?? selectedTrip.driver_id)})`
                        : ''
                    }`
                  : `رحلة #${selectedTripId}`}
          </p>
          {!routeLoading && !routeErr && liveWatching && (
            <p className="text-muted" style={{ margin: '6px 0 0', fontSize: 13 }}>
              متابعة مباشرة عبر بث مستمر. بنفسجي = مسار تقديري كالتطبيق · أحمر = حركة السائق الفعلية.
              تنتهي تلقائياً عند انتهاء الرحلة أو عند خروجك.
              {tripDriverLive ? '' : ' بانتظار موقع السائق…'}
            </p>
          )}
          {!routeLoading && !routeErr && (
            <p className="text-muted" style={{ margin: '6px 0 0', fontSize: 13 }}>
              انطلاق: {tripPickupLabel || '—'} → وجهة: {tripDestLabel || '—'}
            </p>
          )}
          {!routeLoading && (
            <button
              type="button"
              className="btn-ghost"
              style={{ marginTop: 8, fontSize: 12 }}
              onClick={() => exitTripWatch()}
            >
              خروج من المتابعة
            </button>
          )}
        </div>
      )}
      <p className="text-muted" style={{ marginBottom: 8, fontSize: 13 }}>
        خريطة بنفس ستايل التطبيق (OpenFreeMap). اضغط رحلة جارية للمتابعة المباشرة.
        <button
          type="button"
          className="btn-ghost"
          style={{ marginInlineStart: 8, fontSize: 12, padding: '2px 8px' }}
          onClick={() => setMapNight((v) => !v)}
        >
          {mapNight ? 'نهار' : 'ليل'}
        </button>
        {!mapFullscreen && (
          <span className="map-fullscreen-hint"> — اضغط على الخريطة لتكبيرها.</span>
        )}
      </p>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
        {DRIVER_STATUS_ORDER.map((st) => {
          const hidden = hiddenStatuses.has(st);
          return (
            <button
              key={st}
              type="button"
              className="btn-ghost"
              title={hidden ? 'إظهار على الخريطة' : 'إخفاء من الخريطة'}
              onClick={() =>
                setHiddenStatuses((prev) => {
                  const next = new Set(prev);
                  if (next.has(st)) next.delete(st);
                  else next.add(st);
                  return next;
                })
              }
              style={{
                fontSize: 13,
                padding: '4px 10px',
                display: 'inline-flex',
                alignItems: 'center',
                gap: 6,
                opacity: hidden ? 0.45 : 1,
                textDecoration: hidden ? 'line-through' : 'none',
              }}
            >
              <span
                style={{
                  width: 12,
                  height: 12,
                  borderRadius: '50%',
                  background: DRIVER_STATUS[st].color,
                  display: 'inline-block',
                }}
              />
              {DRIVER_STATUS[st].label}: {driverCounts[st]}
            </button>
          );
        })}
        <span className="text-muted" style={{ fontSize: 12 }}>
          اضغط على اللون لإخفائه أو إظهاره · يظهر فقط السائق الذي أرسل موقعه خلال آخر 9 دقائق
        </span>
      </div>
      <div
        ref={mapSectionRef}
        className={`map-wrap${mapFullscreen ? ' map-wrap-fullscreen' : ''}`}
        style={{ marginTop: 12 }}
        onClick={() => {
          if (!mapFullscreen) setMapFullscreen(true);
        }}
        onKeyDown={(e) => {
          if (mapFullscreen) return;
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            setMapFullscreen(true);
          }
        }}
        role={mapFullscreen ? undefined : 'button'}
        tabIndex={mapFullscreen ? undefined : 0}
        aria-label={mapFullscreen ? undefined : 'تكبير خريطة العمليات لملء الشاشة'}
      >
        {mapFullscreen && (
          <button
            type="button"
            className="map-fullscreen-close"
            onClick={(e) => {
              e.stopPropagation();
              setMapFullscreen(false);
            }}
          >
            إغلاق ✕
          </button>
        )}
        <AppStyleMap
          height={mapFullscreen ? '100%' : liveWatching || sosLive ? 420 : 300}
          className={mapFullscreen ? 'map-fullscreen-inner' : ''}
          center={mapCenter}
          zoom={flySosPos ? 16 : liveWatching ? 15 : 12}
          pitch={mapFullscreen || liveWatching ? 52 : 40}
          night={mapNight}
          lines={overlayLines}
          markers={overlayMarkers}
          fitPoints={mapFitPoints}
          fitToken={mapFitToken}
          followPos={showTripOverlay && liveWatching ? tripDriverLive : flySosPos}
          followZoom={flySosPos ? 16 : 15}
        />
      </div>
      <p style={{ marginTop: 12, fontWeight: 700 }}>
        سائقون متصلون: {drivers.length} (متاح {driverCounts.available} · متجه للراكب{' '}
        {driverCounts.to_pickup} · في رحلة {driverCounts.on_trip}) — تنبيهات SOS: {sos.length}
        {data?.snapshot_at ? (
          <span className="text-muted" style={{ fontWeight: 400, fontSize: 12 }}>
            {' '}
            — آخر تحديث: {new Date(String(data.snapshot_at)).toLocaleTimeString('ar-SY')}
          </span>
        ) : null}
      </p>
      <h3 className="page-title" style={{ marginTop: 16, fontSize: '1rem' }}>
        رحلات جارية ({trips.length})
      </h3>
      <p className="text-muted" style={{ marginBottom: 8, fontSize: 13 }}>
        اضغط على رحلة جارية لمتابعتها مباشرة (مسار + موقع السائق حتى تنتهي أو تخرج).
      </p>
      <div className="card-list">
        {trips.slice(0, 30).map((t, i) => {
          const id = Number(t.id ?? 0);
          const st = String(t.status ?? '');
          const stLabel = statusArabic(st, t.driverId ?? t.driver_id);
          const selected = id > 0 && id === selectedTripId;
          const { pickup, dest } = pickupDestLabelsFromRequest(t);
          return (
            <div
              key={id || i}
              className={`card${selected ? ' card-selected' : ''}`}
              role="button"
              tabIndex={0}
              onClick={() => void loadTripRoute(t)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                  e.preventDefault();
                  void loadTripRoute(t);
                }
              }}
              style={{ cursor: 'pointer' }}
            >
              <div className="row-between wrap" style={{ gap: 8 }}>
                <div className="card-title">
                  طلب #{id || '—'} — {stLabel || st}
                </div>
                {id > 0 && (
                  <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                    <Link
                      to={`/requests/${id}`}
                      className="card-link"
                      style={{ fontSize: 13 }}
                      onClick={(e) => e.stopPropagation()}
                    >
                      التفاصيل ←
                    </Link>
                    {canCancelTrip && (
                      <button
                        type="button"
                        className="btn-warn"
                        style={{ fontSize: 12, padding: '4px 10px' }}
                        disabled={cancellingId === id}
                        onClick={(e) => {
                          e.stopPropagation();
                          void cancelRunningTrip(id);
                        }}
                      >
                        {cancellingId === id ? 'جاري الإلغاء…' : 'إلغاء الرحلة'}
                      </button>
                    )}
                  </div>
                )}
              </div>
              <div className="text-muted small" style={{ marginTop: 6 }}>
                انطلاق: {pickup}
                <br />
                وجهة: {dest}
              </div>
            </div>
          );
        })}
      </div>
      {!trips.length && !err && <p className="text-muted">لا رحلات جارية في اللقطة الحالية.</p>}
    </div>
  );
}
