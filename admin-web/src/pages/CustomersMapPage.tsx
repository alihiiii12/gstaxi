import { useEffect, useMemo, useState } from 'react';
import { AppStyleMap, type AppMapMarker } from '../components/AppStyleMap';
import { API } from '../api/endpoints';
import { fetchJsonAuth } from '../api/http';
import { PageHeader } from '../components/PageHeader';

const DEFAULT_CENTER: [number, number] = [33.5138, 36.2765];

export function CustomersMapPage() {
  const [markers, setMarkers] = useState<AppMapMarker[]>([]);
  const [count, setCount] = useState(0);
  const [err, setErr] = useState('');
  const [at, setAt] = useState('');
  const [tick, setTick] = useState(0);

  useEffect(() => {
    const t = window.setInterval(() => setTick((x) => x + 1), 12000);
    return () => window.clearInterval(t);
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const { res, data: json } = await fetchJsonAuth(
          API.adminCustomersMapSnapshot,
        );
        if (cancelled) return;
        if (!res.ok || json.success !== true) {
          setErr(String(json.message ?? 'تعذر التحميل'));
          return;
        }
        setErr('');
        const data = (json.data ?? {}) as Record<string, unknown>;
        const rows = (data.customers_online as Record<string, unknown>[]) ?? [];
        setCount(Number(data.count ?? rows.length) || rows.length);
        setAt(String(data.snapshot_at ?? ''));
        const mks: AppMapMarker[] = [];
        rows.forEach((row, i) => {
          const lat = Number(row.latitude ?? row.lat);
          const lng = Number(row.longitude ?? row.lng ?? row.lon);
          if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
          const id = Number(row.user_id ?? row.id ?? i);
          const name = String(row.name ?? `زبون #${id}`);
          const phone = String(row.number ?? '').trim();
          const source = String(row.source ?? '');
          const emoji =
            source === 'live'
              ? '🟢'
              : source === 'session_approx'
                ? '⚪'
                : '👤';
          const detailParts = [
            phone ? `الهاتف: ${phone}` : '',
            source === 'live'
              ? 'موقع حي'
              : source === 'session_approx'
                ? 'متصل — موقع تقريبي'
                : source === 'session'
                  ? 'متصل'
                  : source === 'active_trip'
                    ? 'طلب نشط'
                    : '',
          ].filter(Boolean);
          mks.push({
            id: `c-${id}`,
            position: [lat, lng],
            emoji,
            title: name,
            detail: detailParts.join(' — ') || undefined,
            size: 20,
          });
        });
        setMarkers(mks);
      } catch (e) {
        if (!cancelled) setErr(String(e));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick]);

  const center = useMemo((): [number, number] => {
    if (markers.length === 0) return DEFAULT_CENTER;
    return markers[0].position;
  }, [markers]);

  // إطار أولي مرة واحدة فقط — التحديث الدوري يحدّث العلامات دون زوم
  const fitPoints = useMemo(
    () => markers.map((m) => m.position),
    [markers],
  );
  const fitToken = markers.length > 0 ? 'customers-init' : 0;

  const timeLabel = at
    ? new Date(at).toLocaleTimeString('ar-SY')
    : '—';

  return (
    <div className="page">
      <PageHeader title="خريطة الزبائن" />
      <p className="muted" style={{ marginTop: 0 }}>
        كل الزبائن المتصلين أو النشطين مؤخراً (جلسة خلال ~6 ساعات) مع آخر موقع
        معروف.
      </p>
      {err && <div className="err-box">{err}</div>}
      <AppStyleMap
        height={420}
        center={center}
        zoom={markers.length ? 12 : 11}
        markers={markers}
        fitPoints={fitPoints}
        fitToken={fitToken}
      />
      <p style={{ marginTop: 12, color: '#11215b', fontWeight: 600 }}>
        زبائن على الخريطة: {count} — آخر تحديث: {timeLabel}
      </p>
      {count === 0 && !err && (
        <p className="muted">
          لا يوجد زبائن بجلسة نشطة الآن. يظهرون عند فتح تطبيق الزبون وتسجيل
          الدخول.
        </p>
      )}
    </div>
  );
}
