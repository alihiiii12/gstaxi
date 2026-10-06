import { useCallback, useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { API } from '../api/endpoints';
import { fetchJsonAuth, getJson } from '../api/http';
import { PageHeader } from '../components/PageHeader';
import { TripRouteMap } from '../components/TripRouteMap';
import { statusArabic, typeArabic } from '../util/adminRequestLabels';
import {
  personName,
  pickupDestLabelsFromRequest,
  requestCustomer,
  requestDriverUser,
  requestHistory,
} from '../util/requestDetailFields';
import {
  buildTripRouteOverlay,
  type LatLngTuple,
} from '../util/requestRouteMap';
import {
  tripFinancialDetailArabic,
  tripPathLabelArabic,
} from '../util/tripPathLabels';

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <p className="detail-row">
      <strong>{label}:</strong> {value || '—'}
    </p>
  );
}

function fmtNum(v: unknown, suffix = ''): string {
  if (v === null || v === undefined || v === '') return '—';
  const n = Number(v);
  if (!Number.isFinite(n)) return String(v);
  return `${n}${suffix}`;
}

function fmtTime(iso: unknown): string {
  if (!iso) return '—';
  const d = new Date(String(iso));
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleString('ar-SY');
}

function mapHintForStatus(status: string, isMeter: boolean): string {
  if (isMeter) {
    return 'رحلة عداد — تُعرض نقاط البداية/النهاية والمسار الفعلي إن وُجد.';
  }
  switch (status) {
    case 'Finished':
      return 'رحلة مكتملة — أزرق = مسار افتراضي، أحمر = مسار فعلي.';
    case 'Running':
      return 'رحلة جارية — المسار المتوقع وموقع السائق (بدون سيارات أخرى).';
    case 'Reserved':
    case 'DriverArrived':
    case 'AwaitingDestination':
      return 'بعد قبول السائق — نقاط القبول والانطلاق والوجهة.';
    case 'Pending':
      return 'قيد الانتظار — موقع الانطلاق (والوجهة إن وُجدت).';
    case 'Removed':
      return 'طلب ملغى — قبول الطلب + الانطلاق + الوجهة والمسارات الافتراضية.';
    default:
      return 'عرض نقاط الرحلة على الخريطة إن توفرت.';
  }
}

export function RequestDetailPage() {
  const { id } = useParams();
  const [data, setData] = useState<Record<string, unknown> | null>(null);
  const [driverExtra, setDriverExtra] = useState<Record<string, unknown> | null>(
    null,
  );
  const [err, setErr] = useState('');
  const [loading, setLoading] = useState(false);
  const [mapLoading, setMapLoading] = useState(false);
  const [mapErr, setMapErr] = useState('');
  const [pickup, setPickup] = useState<LatLngTuple | null>(null);
  const [dest, setDest] = useState<LatLngTuple | null>(null);
  const [routePoints, setRoutePoints] = useState<LatLngTuple[]>([]);
  const [actualRoutePoints, setActualRoutePoints] = useState<LatLngTuple[]>([]);
  const [acceptToPickupRoute, setAcceptToPickupRoute] = useState<LatLngTuple[]>(
    [],
  );
  const [pickupLabel, setPickupLabel] = useState('');
  const [destLabel, setDestLabel] = useState('');
  const [driverLive, setDriverLive] = useState<LatLngTuple | null>(null);
  const [extraPoints, setExtraPoints] = useState<
    {
      position: LatLngTuple;
      title: string;
      detail?: string;
      kind?: 'pickup' | 'dest' | 'accept' | 'actual_start' | 'actual_end' | 'driver';
    }[]
  >([]);
  const [analytics, setAnalytics] = useState<Record<string, unknown> | null>(
    null,
  );

  const loadDetail = useCallback(async () => {
    setErr('');
    setLoading(true);
    setDriverExtra(null);
    try {
      const { res, data: j } = await fetchJsonAuth(
        API.adminRequestDetail(Number(id)),
      );
      if (!res.ok || j.success !== true) {
        throw new Error(String(j.message ?? ''));
      }
      const row = j.data as Record<string, unknown>;
      setData(row);

      const driverId = parseInt(String(row.driverId ?? row.driver_id ?? 0), 10);
      const hasDriver = row.driver != null;
      if (driverId > 0 && !hasDriver) {
        try {
          const d = await getJson<Record<string, unknown>>(
            API.driverShow(driverId),
          );
          const inner = d.data as Record<string, unknown> | undefined;
          if (inner) setDriverExtra(inner);
        } catch {
          /* optional */
        }
      }
    } catch (e) {
      setErr(String(e));
      setData(null);
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    void loadDetail();
  }, [loadDetail]);

  useEffect(() => {
    if (!data) return;
    let cancelled = false;
    (async () => {
      setMapLoading(true);
      setMapErr('');
      try {
        const overlay = await buildTripRouteOverlay(data);
        if (cancelled) return;
        if (!overlay.pickup && !overlay.dest && overlay.extraPoints.length === 0) {
          setMapErr('لا تتوفر إحداثيات انطلاق/وجهة لهذا الطلب.');
        }
        setPickup(overlay.pickup);
        setDest(overlay.dest);
        setRoutePoints(overlay.routePoints);
        setActualRoutePoints(overlay.actualRoutePoints);
        setAcceptToPickupRoute(overlay.acceptToPickupRoute);
        setPickupLabel(overlay.pickupLabel);
        setDestLabel(overlay.destLabel);
        setDriverLive(overlay.driverLive ?? null);
        setExtraPoints(overlay.extraPoints);
        setAnalytics(overlay.analytics);
      } catch (e) {
        if (!cancelled) setMapErr(String(e));
      } finally {
        if (!cancelled) setMapLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [data]);

  if (err) {
    return (
      <div className="page-pad">
        <div className="row-between wrap">
          <Link to="/requests" className="link-back">
            ← رجوع
          </Link>
          <button type="button" className="btn-ghost" onClick={() => void loadDetail()}>
            تحديث
          </button>
        </div>
        <p className="text-err">{err}</p>
      </div>
    );
  }
  if (!data || loading) {
    return (
      <div className="page-center">
        <div className="spinner" />
      </div>
    );
  }

  const st = String(data.status ?? '');
  const typ = String(data.type ?? '');
  const user = requestCustomer(data);
  const driver = (data.driver as Record<string, unknown> | undefined) ?? driverExtra;
  const driverUser =
    requestDriverUser(data) ??
    (driver?.user as Record<string, unknown> | undefined);
  const pathNames = pickupDestLabelsFromRequest(data);
  const hist = requestHistory(data);
  const area =
    (data.service_area as Record<string, unknown> | undefined) ??
    (data.serviceArea as Record<string, unknown> | undefined);

  const isGuest = data.is_guest_customer === true;
  const custName = isGuest
    ? `${`${data.guest_first_name ?? ''} ${data.guest_last_name ?? ''}`.trim() || 'زبون'} (غير مسجّل)`
    : personName(user, '');
  const custPhone = isGuest
    ? String(data.guest_phone ?? '')
    : String(user?.number ?? data.customerPhone ?? '');
  const drvName = driver
    ? personName(driverUser, `سائق #${driver.id ?? data.driverId ?? ''}`)
    : data.driverId
      ? `سائق #${data.driverId} (لم تُحمَّل التفاصيل)`
      : 'لم يُعيَّن بعد';

  const userId = String(data.userId ?? data.user_id ?? '—');
  const isMeter =
    analytics?.is_free_meter === true ||
    String(data.billing_kind ?? '') === 'free_meter';
  const showAcceptRoute = st === 'Removed' || Boolean(analytics?.accept_point);

  return (
    <div className="page-pad">
      <PageHeader
        title={`طلب #${id}${isMeter ? ' — عداد' : ''}`}
        subtitle="تفاصيل المسار والأوقات والمسافات والتقييمات."
        backTo="/requests"
        backLabel="الطلبات"
        onRefresh={() => void loadDetail()}
        refreshing={loading}
        actions={
          <>
            {(st === 'Running' || st === 'Reserved' || st === 'DriverArrived') && (
              <Link to="/map" className="btn-primary" style={{ textDecoration: 'none' }}>
                خريطة العمليات
              </Link>
            )}
            {isMeter && (
              <Link
                to="/requests?billing=free_meter"
                className="btn-ghost"
                style={{ textDecoration: 'none' }}
              >
                كل رحلات العداد
              </Link>
            )}
          </>
        }
      />
      <div className="card detail-card">
        <DetailRow label="الحالة" value={statusArabic(st, data.driverId)} />
        <DetailRow label="النوع" value={typeArabic(typ)} />
        <DetailRow
          label="نوع الفوترة"
          value={isMeter ? 'عداد حر' : 'طلب عبر التطبيق'}
        />
        <DetailRow label="مسار الرحلة" value={tripPathLabelArabic(data)} />
        <DetailRow
          label="التفاصيل المالية"
          value={tripFinancialDetailArabic(data)}
        />

        <h4 className="detail-section">العرض على الخريطة</h4>
        <TripRouteMap
          height={360}
          loading={mapLoading}
          error={mapErr}
          statusHint={mapHintForStatus(st, isMeter)}
          legend="بنفسجي: مسار تقديري كالتطبيق · أحمر: مسار فعلي GPS · أصفر متقطع: من قبول الطلب إلى الانطلاق"
          pickup={pickup}
          dest={dest}
          routePoints={routePoints}
          actualRoutePoints={actualRoutePoints}
          acceptToPickupRoute={showAcceptRoute ? acceptToPickupRoute : []}
          pickupLabel={pickupLabel || pathNames.pickup}
          destLabel={destLabel || pathNames.dest}
          driverLive={
            st === 'Running' || st === 'Reserved' || st === 'DriverArrived'
              ? driverLive
              : null
          }
          driverLabel={
            drvName !== 'لم يُعيَّن بعد' ? `السائق: ${drvName}` : 'موقع السائق'
          }
          extraPoints={extraPoints}
        />

        <h4 className="detail-section">تفاصيل الزمن والمسافة</h4>
        <p className="text-muted" style={{ margin: '0 0 8px', fontSize: 13 }}>
          الافتراضي = تقدير التطبيق لمسار الطرق. الفعلي = ما قطعه السائق (GPS) والمسافة المسجّلة نظامياً في
          التطبيق.
        </p>
        <DetailRow
          label="زمن الرحلة الافتراضي"
          value={fmtNum(analytics?.planned_duration_minutes, ' دقيقة')}
        />
        <DetailRow
          label="زمن الرحلة الفعلي"
          value={fmtNum(analytics?.actual_duration_minutes, ' دقيقة')}
        />
        <DetailRow
          label="المسافة الافتراضية (تقدير التطبيق)"
          value={fmtNum(analytics?.planned_distance_km, ' كم')}
        />
        <DetailRow
          label="المسافة الفعلية (مسجّلة في التطبيق)"
          value={fmtNum(analytics?.actual_distance_km, ' كم')}
        />
        <DetailRow
          label="مسافة توجه الفارس للعميل"
          value={fmtNum(analytics?.driver_to_pickup_km, ' كم')}
        />
        <DetailRow
          label="تقييم العميل للرحلة"
          value={fmtNum(analytics?.passenger_rating_of_trip, ' / 5')}
        />
        <DetailRow
          label="تقييم الفارس للعميل"
          value={fmtNum(analytics?.driver_rating_of_customer, ' / 5')}
        />

        {(isMeter || analytics?.final_cost != null) && (
          <>
            <h4 className="detail-section">تفاصيل العداد / التكلفة</h4>
            <DetailRow
              label="بداية العداد / الرحلة"
              value={fmtTime(analytics?.trip_started_at)}
            />
            <DetailRow
              label="نهاية العداد / الرحلة"
              value={fmtTime(analytics?.trip_ended_at)}
            />
            <DetailRow
              label="مسافة الرحلة (فعلية من التطبيق)"
              value={fmtNum(analytics?.actual_distance_km, ' كم')}
            />
            <DetailRow
              label="تكلفة الرحلة"
              value={fmtNum(
                analytics?.final_cost ??
                  hist?.finalCost ??
                  hist?.final_cost,
                ' ل.س',
              )}
            />
          </>
        )}

        <h4 className="detail-section">أوقات الأحداث</h4>
        <p className="text-muted" style={{ margin: '0 0 8px', fontSize: 13 }}>
          وقت القبول ووقت وصول السائق يُسجَّلان تلقائياً من إجراءات السائق في الطلب. الرحلات القديمة قبل تفعيل
          التتبع قد تظهر فارغة.
        </p>
        <DetailRow
          label="وقت قبول الطلب (من السائق)"
          value={fmtTime(analytics?.accepted_at)}
        />
        <DetailRow
          label="وقت وصول السائق (من السائق)"
          value={fmtTime(analytics?.arrived_at)}
        />
        <DetailRow
          label="وقت بداية الرحلة"
          value={fmtTime(analytics?.trip_started_at)}
        />
        <DetailRow
          label="وقت نهاية الرحلة"
          value={fmtTime(analytics?.trip_ended_at)}
        />

        <h4 className="detail-section">الأشخاص</h4>
        <DetailRow
          label="الزبون (راكب)"
          value={custName || `معرّف ${userId}`}
        />
        <DetailRow
          label="هاتف الزبون"
          value={custPhone}
        />
        <DetailRow label="السائق" value={drvName} />
        {driver && (
          <>
            <DetailRow
              label="هاتف السائق"
              value={String(driverUser?.number ?? driver.number ?? '')}
            />
            <DetailRow
              label="لوحة السيارة"
              value={String(driver.carNumber ?? driver.car_number ?? '')}
            />
          </>
        )}

        <h4 className="detail-section">المواقع والموعد</h4>
        <DetailRow label="نقطة الانطلاق" value={pathNames.pickup} />
        <DetailRow label="الوجهة" value={pathNames.dest} />
        <DetailRow
          label="وصف إضافي"
          value={String(data.locationDesc ?? data.location_desc ?? '')}
        />
        <DetailRow label="موعد الطلب" value={String(data.requestDate ?? '')} />
        <DetailRow
          label="منطقة الخدمة"
          value={String(area?.name ?? 'غير مرتبطة')}
        />
        <DetailRow
          label="كوبون"
          value={String(data.discountCode ?? data.discount_code ?? '—')}
        />
        <DetailRow
          label="تكلفة متوقعة"
          value={String(data.predictedCost ?? data.predectedCost ?? '—')}
        />
        {data.zone_multiplier != null && (
          <DetailRow
            label="تسعيرة المنطقة"
            value={`${String(data.pickup_zone_name ?? '—')} ← ${String(data.dest_zone_name ?? '—')} · ×${Number(data.zone_multiplier)}`}
          />
        )}

        <details className="json-details mt">
          <summary>بيانات تقنية (JSON)</summary>
          <pre className="json-dump">{JSON.stringify(data, null, 2)}</pre>
        </details>
      </div>
    </div>
  );
}
