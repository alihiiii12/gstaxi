import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { API } from '../api/endpoints';
import { fetchJsonAuth } from '../api/http';
import { PageHeader } from '../components/PageHeader';
import { statusArabic, typeArabic } from '../util/adminRequestLabels';
import { formatDateTimeLatin } from '../util/latinDigits';
import {
  personName,
  pickupDestLabelsFromRequest,
} from '../util/requestDetailFields';
import {
  tripFinancialDetailArabic,
  tripPathLabelArabic,
} from '../util/tripPathLabels';

type Row = Record<string, unknown>;

function asRecord(v: unknown): Row | undefined {
  return v && typeof v === 'object' && !Array.isArray(v) ? (v as Row) : undefined;
}

function extractPaginatedList(j: Record<string, unknown>, key: 'data'): unknown[] {
  const d = j[key];
  if (Array.isArray(d)) return d;
  const inner = asRecord(d);
  if (inner && Array.isArray(inner.data)) return inner.data as unknown[];
  return [];
}

function requestFromReview(row: Row): Row | undefined {
  return asRecord(row.request) ?? asRecord(row.Request);
}

function driverFromReview(row: Row, req: Row | undefined): Row | undefined {
  return (
    asRecord(row.driver) ??
    asRecord(req?.driver) ??
    asRecord(req?.Driver)
  );
}

function strVal(...vals: unknown[]): string {
  for (const v of vals) {
    const s = String(v ?? '').trim();
    if (s) return s;
  }
  return '';
}

function passengerDisplay(row: Row, req: Row | undefined): string {
  const fromApi = strVal(row.passenger_name);
  if (fromApi) return fromApi;
  const embedded = asRecord(req?.user) ?? asRecord(req?.User);
  return personName(embedded, '—');
}

function driverDisplay(row: Row, driver: Row | undefined): string {
  const fromApi = strVal(row.driver_name);
  if (fromApi) return fromApi;
  const u = asRecord(driver?.user) ?? asRecord(driver?.User);
  if (u) return personName(u, '—');
  const id = driver?.id ?? row.driverId ?? row.driver_id;
  return id ? `سائق #${id}` : '—';
}

function carPlate(row: Row, driver: Row | undefined): string {
  return (
    strVal(row.car_number, driver?.carNumber, driver?.car_number) || '—'
  );
}

function tripPlaces(row: Row, req: Row | undefined): { pickup: string; dest: string } {
  const pickup = strVal(row.pickup_label, row.pickupLabel);
  const dest = strVal(row.dest_label, row.destLabel);
  if (pickup || dest) {
    return { pickup: pickup || '—', dest: dest || '—' };
  }
  if (req) return pickupDestLabelsFromRequest(req);
  return { pickup: '—', dest: '—' };
}

function tripOutcomeArabic(req: Row | undefined, row?: Row): string {
  const st = String(row?.trip_status ?? req?.status ?? '').trim();
  if (st === 'Finished') return 'مكتملة';
  if (st === 'Removed') return 'ملغاة';
  if (!st) return '—';
  return statusArabic(st, req?.driverId ?? req?.driver_id);
}

function ratingLine(rating: unknown): { stars: string; num: string } {
  const n = typeof rating === 'number' ? rating : parseInt(String(rating ?? ''), 10);
  const clamped = Math.min(5, Math.max(0, Number.isNaN(n) ? 0 : n));
  return {
    stars: '★'.repeat(clamped) + '☆'.repeat(5 - clamped),
    num: String(clamped),
  };
}

function formatReviewDate(iso: unknown): string {
  const s = String(iso ?? '').trim();
  if (!s) return '—';
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return s;
  return formatDateTimeLatin(d);
}

function money(v: unknown): string {
  const n = typeof v === 'number' ? v : parseFloat(String(v ?? ''));
  if (!Number.isFinite(n)) return '—';
  return `${Math.round(n).toLocaleString('en-US')} ل.س`;
}

function DetailLine({ label, value }: { label: string; value: string }) {
  return (
    <div style={{ marginBottom: 8, lineHeight: 1.45 }}>
      <span className="text-muted">{label}: </span>
      <strong>{value || '—'}</strong>
    </div>
  );
}

function ReviewDetailModal({
  row,
  onClose,
}: {
  row: Row;
  onClose: () => void;
}) {
  const req = requestFromReview(row);
  const driver = driverFromReview(row, req);
  const requestId = row.requestId ?? row.request_id ?? req?.id;
  const rid = parseInt(String(requestId ?? ''), 10);
  const passenger = passengerDisplay(row, req);
  const driverName = driverDisplay(row, driver);
  const plate = carPlate(row, driver);
  const { pickup, dest } = tripPlaces(row, req);
  const outcome = tripOutcomeArabic(req, row);
  const created = formatReviewDate(row.created_at ?? row.createdAt);
  const detail = String(row.detail ?? row.comment ?? '—').trim() || '—';
  const { stars, num } = ratingLine(row.rating);
  const passengerPhone = strVal(row.passenger_phone, asRecord(req?.user)?.number);
  const driverPhone = strVal(row.driver_phone, asRecord(driver?.user)?.number);
  const carType = strVal(row.car_type_name, asRecord(req?.carType)?.name);
  const vehicleModel = strVal(row.vehicle_model, driver?.vehicle_model);
  const finalCost = money(row.final_cost ?? asRecord(req?.history)?.finalCost);
  const predicted = money(row.predicted_cost ?? req?.predectedCost);
  const area = strVal(row.service_area_name, asRecord(req?.serviceArea)?.name);
  const tripType = typeArabic(String(row.trip_type ?? req?.type ?? ''));
  const startedAt = formatReviewDate(row.trip_started_at ?? req?.trip_started_at);
  const requestAt = formatReviewDate(row.created_request_at ?? req?.created_at);

  return (
    <div className="modal-backdrop" role="presentation" onClick={onClose}>
      <div
        className="modal modal-wide"
        role="dialog"
        aria-modal="true"
        onClick={(e) => e.stopPropagation()}
        dir="rtl"
      >
        <div className="row-between wrap" style={{ marginBottom: 12, gap: 8 }}>
          <h3 className="page-title" style={{ margin: 0, fontSize: '1.1rem' }}>
            تفاصيل رأي الراكب
            {!Number.isNaN(rid) && rid > 0 ? ` — رحلة #${rid}` : ''}
          </h3>
          <button type="button" className="btn-ghost" onClick={onClose}>
            إغلاق
          </button>
        </div>

        <div style={{ marginBottom: 14 }}>
          <span style={{ color: '#ffc107', letterSpacing: 1, fontSize: 18 }}>{stars}</span>
          <span className="text-muted" style={{ marginInlineStart: 8 }}>
            التقييم: {num} / 5
          </span>
          <span
            style={{
              marginInlineStart: 12,
              fontWeight: 700,
              color: outcome === 'ملغاة' ? '#c62828' : outcome === 'مكتملة' ? '#2e7d32' : undefined,
            }}
          >
            {outcome}
          </span>
        </div>

        <p style={{ whiteSpace: 'pre-wrap', lineHeight: 1.55, marginTop: 0 }}>{detail}</p>

        <h4 className="detail-section">الراكب</h4>
        <DetailLine label="الاسم" value={passenger} />
        <DetailLine label="رقم الهاتف" value={passengerPhone || '—'} />

        <h4 className="detail-section">السائق والسيارة</h4>
        <DetailLine label="اسم السائق" value={driverName} />
        <DetailLine label="هاتف السائق" value={driverPhone || '—'} />
        <DetailLine label="رقم لوحة السيارة" value={plate} />
        <DetailLine label="فئة السيارة" value={carType || '—'} />
        <DetailLine label="طراز السيارة" value={vehicleModel || '—'} />

        <h4 className="detail-section">مسار الرحلة</h4>
        <DetailLine label="من (الانطلاق)" value={pickup} />
        <DetailLine label="إلى (الوجهة)" value={dest} />
        <DetailLine
          label="وصف إضافي"
          value={strVal(row.location_desc, req?.locationDesc, req?.location_desc) || '—'}
        />
        <DetailLine label="منطقة الخدمة" value={area || '—'} />
        {req && <DetailLine label="ملخص المسار" value={tripPathLabelArabic(req)} />}

        <h4 className="detail-section">بيانات الرحلة</h4>
        <DetailLine label="رقم الرحلة" value={!Number.isNaN(rid) && rid > 0 ? `#${rid}` : '—'} />
        <DetailLine label="نوع الطلب" value={tripType || '—'} />
        <DetailLine label="حالة الرحلة" value={outcome} />
        <DetailLine label="التكلفة النهائية" value={finalCost} />
        <DetailLine label="التكلفة المتوقعة" value={predicted} />
        {req && <DetailLine label="التفاصيل المالية" value={tripFinancialDetailArabic(req)} />}
        <DetailLine label="وقت إنشاء الطلب" value={requestAt} />
        <DetailLine label="وقت بدء الرحلة" value={startedAt} />
        <DetailLine label="تاريخ التقييم" value={created} />

        {!Number.isNaN(rid) && rid > 0 && (
          <div style={{ marginTop: 16 }}>
            <Link to={`/requests/${rid}`} className="card-link" onClick={onClose}>
              فتح صفحة الطلب كاملة ←
            </Link>
          </div>
        )}
      </div>
    </div>
  );
}

export function ReviewsPage() {
  const [list, setList] = useState<Row[]>([]);
  const [err, setErr] = useState('');
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Row | null>(null);

  const load = useCallback(async () => {
    setErr('');
    setLoading(true);
    try {
      const { res, data: jRev } = await fetchJsonAuth(
        `${API.adminComplaintsReviews}?${new URLSearchParams({ per_page: '40' })}`,
      );
      if (!res.ok || jRev.success !== true) {
        throw new Error(String(jRev.message ?? ''));
      }
      setList(extractPaginatedList(jRev, 'data').map((e) => e as Row));
    } catch (e) {
      setErr(String(e));
      setList([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="page-pad">
      <PageHeader
        title="رأي الراكبين بالرحلة"
        subtitle="اضغط على أي رأي لعرض تفاصيل الرحلة كاملة."
        onRefresh={() => void load()}
        refreshing={loading}
      />
      {err && <p className="text-err">{err}</p>}
      {loading && <p className="text-muted">جاري التحميل…</p>}
      <div className="card-list">
        {list.map((row, i) => {
          const req = requestFromReview(row);
          const driver = driverFromReview(row, req);
          const requestId = row.requestId ?? row.request_id ?? req?.id;
          const rid = parseInt(String(requestId ?? ''), 10);
          const passenger = passengerDisplay(row, req);
          const driverName = driverDisplay(row, driver);
          const plate = carPlate(row, driver);
          const { pickup, dest } = tripPlaces(row, req);
          const outcome = tripOutcomeArabic(req, row);
          const created = formatReviewDate(row.created_at ?? row.createdAt);
          const detail = String(row.detail ?? row.comment ?? '—').trim() || '—';
          const { stars, num } = ratingLine(row.rating);
          const rowKey = row.id != null ? String(row.id) : `r-${i}`;

          return (
            <div
              key={rowKey}
              className="card"
              role="button"
              tabIndex={0}
              style={{ cursor: 'pointer' }}
              onClick={() => setSelected(row)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                  e.preventDefault();
                  setSelected(row);
                }
              }}
            >
              <div className="row-between" style={{ flexWrap: 'wrap', gap: 8, alignItems: 'flex-start' }}>
                <div>
                  <div className="card-title">{passenger}</div>
                  <div className="text-muted" style={{ marginTop: 4 }}>
                    {typeArabic(String(req?.type ?? ''))}
                    {!Number.isNaN(rid) && rid > 0 ? ` — رحلة #${rid}` : ''}
                  </div>
                  <div className="text-muted" style={{ marginTop: 4, fontSize: 13 }}>
                    {pickup} → {dest}
                  </div>
                  <div className="text-muted" style={{ marginTop: 4, fontSize: 13 }}>
                    السائق: {driverName} · اللوحة: {plate}
                  </div>
                </div>
                <div className="text-muted" style={{ textAlign: 'left', whiteSpace: 'nowrap' }}>
                  {created}
                  <div style={{ marginTop: 4, fontSize: 12, fontWeight: 700, color: '#11215B' }}>
                    عرض التفاصيل ←
                  </div>
                </div>
              </div>
              <div style={{ marginTop: 10, display: 'flex', flexWrap: 'wrap', gap: 12, alignItems: 'center' }}>
                <span style={{ color: '#ffc107', letterSpacing: 1 }} title={`${num} من 5`}>
                  {stars}
                </span>
                <span className="text-muted">التقييم: {num} / 5</span>
                <span
                  className="text-muted"
                  style={{
                    fontWeight: 700,
                    color: outcome === 'ملغاة' ? '#c62828' : outcome === 'مكتملة' ? '#2e7d32' : undefined,
                  }}
                >
                  {outcome}
                </span>
              </div>
              <p style={{ marginTop: 12, marginBottom: 0, whiteSpace: 'pre-wrap', lineHeight: 1.5 }}>
                {detail.length > 140 ? `${detail.slice(0, 140)}…` : detail}
              </p>
            </div>
          );
        })}
      </div>
      {!list.length && !err && !loading && <p className="text-muted">لا بيانات</p>}

      {selected && (
        <ReviewDetailModal row={selected} onClose={() => setSelected(null)} />
      )}
    </div>
  );
}
