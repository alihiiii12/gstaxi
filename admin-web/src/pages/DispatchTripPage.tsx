import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { API } from '../api/endpoints';
import { fetchJsonAuth, postJson } from '../api/http';
import { staffHas, useAuth } from '../auth/AuthContext';
import { MapPlacePicker } from '../components/MapPlacePicker';
import { PageHeader } from '../components/PageHeader';
import { formatApiFailure } from '../util/apiError';
import type { LatLngTuple } from '../util/requestRouteMap';

type DriverOpt = {
  id: number;
  name: string;
  phone: string;
  carTypeId: number;
  online?: boolean;
};

type CustomerOpt = {
  id: number;
  name: string;
  phone: string;
  firstName: string;
  lastName: string;
};

type PlaceValue = { position: LatLngTuple; name: string };

const DRIVERS_PAGE_SIZE = 50;
const CUSTOMERS_PAGE_SIZE = 40;

function parseDriverRows(
  rows: Record<string, unknown>[],
  onlineIds: Set<number>,
): DriverOpt[] {
  return rows
    .map((r) => {
      const id = Number(r.id ?? r.driver_id ?? 0);
      const u = (r.user as Record<string, unknown> | undefined) ?? {};
      const name =
        `${String(u.firstName ?? r.firstName ?? '').trim()} ${String(u.lastName ?? r.lastName ?? '').trim()}`.trim();
      return {
        id,
        name: name || `سائق #${id}`,
        phone: String(u.number ?? r.number ?? ''),
        carTypeId: Number(r.transTypeId ?? r.CarTypeId ?? r.carTypeId ?? 0),
        online: onlineIds.has(id),
      };
    })
    .filter((d) => d.id > 0)
    .sort(
      (a, b) =>
        Number(b.online) - Number(a.online) || a.name.localeCompare(b.name, 'ar'),
    );
}

function parseCustomerRows(rows: Record<string, unknown>[]): CustomerOpt[] {
  return rows
    .map((u) => {
      const id = Number(u.id ?? 0);
      const firstName = String(u.firstName ?? '').trim();
      const lastName = String(u.lastName ?? '').trim();
      const name = `${firstName} ${lastName}`.trim() || `زبون #${id}`;
      return {
        id,
        name,
        phone: String(u.number ?? '').trim(),
        firstName,
        lastName,
      };
    })
    .filter((c) => c.id > 0);
}

async function fetchDriversPage(
  search: string,
  page: number,
): Promise<{ rows: Record<string, unknown>[]; lastPage: number; total: number }> {
  const q = new URLSearchParams();
  q.set('per_page', String(DRIVERS_PAGE_SIZE));
  q.set('page', String(page));
  q.set('sort_by', 'id');
  q.set('sort_order', 'desc');
  if (search) q.set('search', search);
  const { res, data: j } = await fetchJsonAuth(`${API.driversIndex}?${q}`);
  if (!res.ok || j.success !== true) {
    throw new Error(String(j.message ?? res.statusText));
  }
  const raw = j.data;
  let rows: Record<string, unknown>[] = [];
  let lastPage = 1;
  let total = 0;
  if (Array.isArray(raw)) {
    rows = raw as Record<string, unknown>[];
    total = rows.length;
  } else if (raw && typeof raw === 'object') {
    const d = raw as Record<string, unknown>;
    if (Array.isArray(d.data)) rows = d.data as Record<string, unknown>[];
    lastPage = Math.max(1, Number(d.last_page ?? 1));
    total = Number(d.total ?? rows.length);
  }
  return { rows, lastPage, total };
}

async function fetchCustomersPage(
  search: string,
  page: number,
): Promise<{ rows: Record<string, unknown>[]; lastPage: number; total: number }> {
  const q = new URLSearchParams();
  q.set('per_page', String(CUSTOMERS_PAGE_SIZE));
  q.set('page', String(page));
  if (search) q.set('search', search);
  const { res, data: j } = await fetchJsonAuth(`${API.adminCustomers}?${q}`);
  if (!res.ok || j.success !== true) {
    throw new Error(String(j.message ?? res.statusText));
  }
  const payload = (j.data as Record<string, unknown>) ?? {};
  const inner = (payload.data as unknown[]) ?? [];
  return {
    rows: inner.map((e) => e as Record<string, unknown>),
    lastPage: Math.max(1, Number(payload.last_page ?? 1)),
    total: Number(payload.total ?? inner.length),
  };
}

export function DispatchTripPage() {
  const { user } = useAuth();
  const nav = useNavigate();
  const canWrite =
    user != null && staffHas(user.roll, user.permissions, 'requests.write');

  const [onlineIds, setOnlineIds] = useState<Set<number>>(() => new Set());
  const [driverResults, setDriverResults] = useState<DriverOpt[]>([]);
  const [driverTotal, setDriverTotal] = useState(0);
  const [driverPage, setDriverPage] = useState(1);
  const [driverLastPage, setDriverLastPage] = useState(1);
  const [loadingDrivers, setLoadingDrivers] = useState(true);
  const [driverSearch, setDriverSearch] = useState('');
  const [debouncedDriverSearch, setDebouncedDriverSearch] = useState('');
  const [driverId, setDriverId] = useState(0);
  const [selectedDriver, setSelectedDriver] = useState<DriverOpt | null>(null);
  const [driverListOpen, setDriverListOpen] = useState(true);

  const [customerResults, setCustomerResults] = useState<CustomerOpt[]>([]);
  const [customerTotal, setCustomerTotal] = useState(0);
  const [customerPage, setCustomerPage] = useState(1);
  const [customerLastPage, setCustomerLastPage] = useState(1);
  const [loadingCustomers, setLoadingCustomers] = useState(false);
  const [customerSearch, setCustomerSearch] = useState('');
  const [debouncedCustomerSearch, setDebouncedCustomerSearch] = useState('');
  const [selectedCustomer, setSelectedCustomer] = useState<CustomerOpt | null>(
    null,
  );
  const [customerListOpen, setCustomerListOpen] = useState(false);
  const [guestPhone, setGuestPhone] = useState('');
  const [guestFirst, setGuestFirst] = useState('');
  const [guestLast, setGuestLast] = useState('');

  const [pickup, setPickup] = useState<PlaceValue | null>(null);
  const [dest, setDest] = useState<PlaceValue | null>(null);
  const [locationDesc, setLocationDesc] = useState('طلب من لوحة الإدارة');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');

  useEffect(() => {
    const t = window.setTimeout(
      () => setDebouncedDriverSearch(driverSearch.trim()),
      350,
    );
    return () => window.clearTimeout(t);
  }, [driverSearch]);

  useEffect(() => {
    const t = window.setTimeout(
      () => setDebouncedCustomerSearch(customerSearch.trim()),
      350,
    );
    return () => window.clearTimeout(t);
  }, [customerSearch]);

  useEffect(() => {
    setDriverPage(1);
  }, [debouncedDriverSearch]);

  useEffect(() => {
    setCustomerPage(1);
  }, [debouncedCustomerSearch]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const snap = await fetchJsonAuth(API.adminMapSnapshot);
        const list =
          ((snap.data?.data as Record<string, unknown> | undefined)
            ?.drivers_online as Record<string, unknown>[]) ?? [];
        const ids = new Set<number>();
        for (const m of list) {
          const id = Number(m.driverId ?? m.driver_id ?? 0);
          if (id > 0) ids.add(id);
        }
        if (!cancelled) setOnlineIds(ids);
      } catch {
        /* ignore */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const loadDrivers = useCallback(async () => {
    setLoadingDrivers(true);
    try {
      const { rows, lastPage, total } = await fetchDriversPage(
        debouncedDriverSearch,
        driverPage,
      );
      setDriverResults(parseDriverRows(rows, onlineIds));
      setDriverLastPage(lastPage);
      setDriverTotal(total);
    } catch (e) {
      setErr(String(e));
      setDriverResults([]);
    } finally {
      setLoadingDrivers(false);
    }
  }, [debouncedDriverSearch, driverPage, onlineIds]);

  useEffect(() => {
    void loadDrivers();
  }, [loadDrivers]);

  const loadCustomers = useCallback(async () => {
    if (!customerListOpen && selectedCustomer) return;
    setLoadingCustomers(true);
    try {
      const { rows, lastPage, total } = await fetchCustomersPage(
        debouncedCustomerSearch,
        customerPage,
      );
      setCustomerResults(parseCustomerRows(rows));
      setCustomerLastPage(lastPage);
      setCustomerTotal(total);
    } catch (e) {
      setErr(String(e));
      setCustomerResults([]);
    } finally {
      setLoadingCustomers(false);
    }
  }, [
    debouncedCustomerSearch,
    customerPage,
    customerListOpen,
    selectedCustomer,
  ]);

  useEffect(() => {
    void loadCustomers();
  }, [loadCustomers]);

  const displayDriver = useMemo(() => {
    if (selectedDriver && selectedDriver.id === driverId) {
      return { ...selectedDriver, online: onlineIds.has(selectedDriver.id) };
    }
    return driverResults.find((d) => d.id === driverId) ?? null;
  }, [selectedDriver, driverId, driverResults, onlineIds]);

  function pickDriver(d: DriverOpt) {
    setDriverId(d.id);
    setSelectedDriver(d);
    setDriverListOpen(false);
    setDriverSearch('');
  }

  function pickCustomer(c: CustomerOpt) {
    setSelectedCustomer(c);
    setCustomerListOpen(false);
    setCustomerSearch('');
    setGuestPhone('');
    setGuestFirst('');
    setGuestLast('');
  }

  function clearCustomer() {
    setSelectedCustomer(null);
    setCustomerListOpen(true);
  }

  async function submit() {
    setErr('');
    if (!canWrite) {
      setErr('لا تملك صلاحية إنشاء طلبات');
      return;
    }
    if (driverId <= 0) {
      setErr('اختر سائقاً');
      return;
    }
    if (!pickup || !dest) {
      setErr('حدد نقطة الانطلاق ونقطة الوصول من الخريطة أو البحث');
      return;
    }

    const body: Record<string, unknown> = {
      driver_id: driverId,
      start_lat: pickup.position[0],
      start_lng: pickup.position[1],
      dest_lat: dest.position[0],
      dest_lng: dest.position[1],
      start_name: pickup.name || 'موقع العميل',
      dest_name: dest.name || 'الوجهة',
      location_desc: locationDesc.trim() || 'طلب من لوحة الإدارة',
    };

    if (selectedCustomer) {
      body.customer_id = selectedCustomer.id;
    } else {
      if (guestPhone.trim()) body.customer_phone = guestPhone.trim();
      if (guestFirst.trim()) body.customer_first_name = guestFirst.trim();
      if (guestLast.trim()) body.customer_last_name = guestLast.trim();
    }

    const carTypeId = displayDriver?.carTypeId ?? selectedDriver?.carTypeId ?? 0;
    if (carTypeId) body.car_type_id = carTypeId;

    setBusy(true);
    try {
      const { res, data } = await postJson<Record<string, unknown>>(
        API.adminDispatchToDriver,
        body,
      );
      if ((res.status === 200 || res.status === 201) && data.success === true) {
        const d = (data.data as Record<string, unknown>) ?? {};
        const id = Number(d.id ?? 0);
        alert(
          String(
            data.message ??
              `تم إرسال الطلب #${id} للسائق — سيظهر في التطبيق للقبول أو الرفض`,
          ),
        );
        if (id > 0) {
          nav(`/requests/${id}`, { replace: true });
        } else {
          nav('/requests', { replace: true });
        }
      } else {
        setErr(formatApiFailure(data, String(data.message ?? res.statusText)));
      }
    } catch (e) {
      setErr(String(e));
    } finally {
      setBusy(false);
    }
  }

  if (!canWrite) {
    return (
      <div className="page-pad">
        <p className="text-err">لا تملك صلاحية إرسال طلب لسائق.</p>
      </div>
    );
  }

  return (
    <div className="page-pad">
      <PageHeader
        title="إرسال طلب لسائق"
        subtitle="ابحث عن السائق والزبون، وحدد الانطلاق والوصول من الخريطة كالتطبيق."
        backTo="/requests"
        backLabel="الطلبات"
      />

      {err && <p className="text-err">{err}</p>}

      <div className="card" style={{ marginTop: 12, padding: 16 }}>
        {/* —— السائق —— */}
        <div style={{ marginBottom: 8 }}>
          <div className="row-between wrap" style={{ gap: 8, alignItems: 'center' }}>
            <strong>السائق</strong>
            <span className="text-muted" style={{ fontSize: 12 }}>
              {driverTotal > 0 ? `النتائج: ${driverTotal}` : ''}
            </span>
          </div>

          {displayDriver ? (
            <div
              style={{
                marginTop: 8,
                padding: '10px 12px',
                borderRadius: 10,
                border: '1px solid rgba(14,165,233,0.35)',
                background: 'rgba(14,165,233,0.08)',
                display: 'flex',
                gap: 10,
                alignItems: 'center',
                flexWrap: 'wrap',
              }}
            >
              <span>
                {displayDriver.online ? '🟢' : '⚪'}{' '}
                <strong>{displayDriver.name}</strong>
                {displayDriver.phone ? ` — ${displayDriver.phone}` : ''}
                <span className="text-muted"> (#{displayDriver.id})</span>
              </span>
              <button
                type="button"
                className="btn-ghost"
                style={{ fontSize: 12, padding: '4px 10px' }}
                disabled={busy}
                onClick={() => {
                  setDriverId(0);
                  setSelectedDriver(null);
                  setDriverListOpen(true);
                }}
              >
                تغيير
              </button>
            </div>
          ) : null}

          {(driverListOpen || !displayDriver) && (
            <div style={{ marginTop: 10 }}>
              <label className="field-block" style={{ display: 'block' }}>
                بحث بالاسم أو رقم الهاتف
                <input
                  type="search"
                  value={driverSearch}
                  onChange={(e) => {
                    setDriverSearch(e.target.value);
                    setDriverListOpen(true);
                  }}
                  onFocus={() => setDriverListOpen(true)}
                  placeholder="مثال: أحمد، 09xxxxxxxx"
                  disabled={busy}
                  autoComplete="off"
                  dir="rtl"
                />
              </label>
              <div
                style={{
                  marginTop: 8,
                  maxHeight: 240,
                  overflowY: 'auto',
                  border: '1px solid var(--border, #ddd)',
                  borderRadius: 10,
                }}
              >
                {loadingDrivers && (
                  <p className="text-muted" style={{ padding: 12, margin: 0 }}>
                    جاري تحميل السائقين…
                  </p>
                )}
                {!loadingDrivers &&
                  driverResults.map((d) => (
                    <button
                      key={d.id}
                      type="button"
                      onClick={() => pickDriver(d)}
                      disabled={busy}
                      style={{
                        display: 'block',
                        width: '100%',
                        textAlign: 'right',
                        padding: '10px 12px',
                        border: 'none',
                        borderBottom: '1px solid var(--border, #eee)',
                        background:
                          d.id === driverId
                            ? 'rgba(14,165,233,0.12)'
                            : 'transparent',
                        cursor: 'pointer',
                        font: 'inherit',
                      }}
                    >
                      <strong>
                        {d.online ? '🟢 ' : '⚪ '}
                        {d.name}
                      </strong>
                      <div className="text-muted" style={{ fontSize: 12 }}>
                        {d.phone || 'بدون رقم'} · #{d.id}
                      </div>
                    </button>
                  ))}
                {!loadingDrivers && driverResults.length === 0 && (
                  <p className="text-muted" style={{ padding: 12, margin: 0 }}>
                    {debouncedDriverSearch
                      ? `لا سائق يطابق «${debouncedDriverSearch}»`
                      : 'لا سائقين'}
                  </p>
                )}
              </div>
              <div
                className="row-between wrap"
                style={{ gap: 8, marginTop: 8, alignItems: 'center' }}
              >
                <span className="text-muted" style={{ fontSize: 12 }}>
                  صفحة {driverPage} / {driverLastPage}
                </span>
                <div className="row-gap" style={{ gap: 6 }}>
                  <button
                    type="button"
                    className="btn-ghost"
                    disabled={driverPage <= 1 || loadingDrivers || busy}
                    onClick={() => setDriverPage((p) => Math.max(1, p - 1))}
                  >
                    السابق
                  </button>
                  <button
                    type="button"
                    className="btn-ghost"
                    disabled={
                      driverPage >= driverLastPage || loadingDrivers || busy
                    }
                    onClick={() =>
                      setDriverPage((p) => Math.min(driverLastPage, p + 1))
                    }
                  >
                    التالي
                  </button>
                </div>
              </div>
            </div>
          )}

          {displayDriver && !displayDriver.online && (
            <p className="text-muted" style={{ fontSize: 13, marginTop: 6 }}>
              السائق غير ظاهر أونلاين — قد يرفض الخادم الإرسال إن لم يكن متصلاً.
            </p>
          )}
        </div>

        {/* —— الزبون —— */}
        <h4 className="detail-section" style={{ marginTop: 18 }}>
          الزبون
        </h4>
        <p className="text-muted" style={{ fontSize: 13, marginBottom: 8 }}>
          ابحث واختر زبوناً مسجّلاً، أو اتركه فارغاً / أدخل بيانات زائر يدوياً.
        </p>

        {selectedCustomer ? (
          <div
            style={{
              padding: '10px 12px',
              borderRadius: 10,
              border: '1px solid rgba(34,197,94,0.35)',
              background: 'rgba(34,197,94,0.08)',
              display: 'flex',
              gap: 10,
              alignItems: 'center',
              flexWrap: 'wrap',
              marginBottom: 10,
            }}
          >
            <span>
              <strong>{selectedCustomer.name}</strong>
              {selectedCustomer.phone ? ` — ${selectedCustomer.phone}` : ''}
              <span className="text-muted"> (#{selectedCustomer.id})</span>
            </span>
            <button
              type="button"
              className="btn-ghost"
              style={{ fontSize: 12, padding: '4px 10px' }}
              disabled={busy}
              onClick={clearCustomer}
            >
              تغيير
            </button>
          </div>
        ) : (
          <>
            <label className="field-block" style={{ display: 'block' }}>
              بحث بالاسم أو رقم الهاتف
              <input
                type="search"
                value={customerSearch}
                onChange={(e) => {
                  setCustomerSearch(e.target.value);
                  setCustomerListOpen(true);
                }}
                onFocus={() => setCustomerListOpen(true)}
                placeholder="مثال: سارة، 09xxxxxxxx"
                disabled={busy}
                autoComplete="off"
                dir="rtl"
              />
            </label>
            {customerListOpen && (
              <div style={{ marginTop: 8 }}>
                <div
                  style={{
                    maxHeight: 220,
                    overflowY: 'auto',
                    border: '1px solid var(--border, #ddd)',
                    borderRadius: 10,
                  }}
                >
                  {loadingCustomers && (
                    <p className="text-muted" style={{ padding: 12, margin: 0 }}>
                      جاري تحميل الزبائن…
                    </p>
                  )}
                  {!loadingCustomers &&
                    customerResults.map((c) => (
                      <button
                        key={c.id}
                        type="button"
                        onClick={() => pickCustomer(c)}
                        disabled={busy}
                        style={{
                          display: 'block',
                          width: '100%',
                          textAlign: 'right',
                          padding: '10px 12px',
                          border: 'none',
                          borderBottom: '1px solid var(--border, #eee)',
                          background: 'transparent',
                          cursor: 'pointer',
                          font: 'inherit',
                        }}
                      >
                        <strong>{c.name}</strong>
                        <div className="text-muted" style={{ fontSize: 12 }}>
                          {c.phone || 'بدون رقم'} · #{c.id}
                        </div>
                      </button>
                    ))}
                  {!loadingCustomers && customerResults.length === 0 && (
                    <p className="text-muted" style={{ padding: 12, margin: 0 }}>
                      {debouncedCustomerSearch
                        ? `لا زبون يطابق «${debouncedCustomerSearch}»`
                        : 'اكتب للبحث عن زبون'}
                    </p>
                  )}
                </div>
                <div
                  className="row-between wrap"
                  style={{ gap: 8, marginTop: 8, alignItems: 'center' }}
                >
                  <span className="text-muted" style={{ fontSize: 12 }}>
                    {customerTotal > 0
                      ? `صفحة ${customerPage} / ${customerLastPage} · ${customerTotal}`
                      : ''}
                  </span>
                  <div className="row-gap" style={{ gap: 6 }}>
                    <button
                      type="button"
                      className="btn-ghost"
                      disabled={customerPage <= 1 || loadingCustomers || busy}
                      onClick={() => setCustomerPage((p) => Math.max(1, p - 1))}
                    >
                      السابق
                    </button>
                    <button
                      type="button"
                      className="btn-ghost"
                      disabled={
                        customerPage >= customerLastPage ||
                        loadingCustomers ||
                        busy
                      }
                      onClick={() =>
                        setCustomerPage((p) =>
                          Math.min(customerLastPage, p + 1),
                        )
                      }
                    >
                      التالي
                    </button>
                  </div>
                </div>
              </div>
            )}

            <p className="text-muted" style={{ fontSize: 13, marginTop: 14 }}>
              أو زبون غير مسجّل (اختياري) — إن كان الرقم لزبون مسجّل يُربط بحسابه، وإلا
              يظهر الاسم والرقم في الطلب فقط دون إنشاء حساب:
            </p>
            <div className="filter-row" style={{ flexWrap: 'wrap', gap: 12 }}>
              <label className="field-block">
                هاتف
                <input
                  value={guestPhone}
                  onChange={(e) => setGuestPhone(e.target.value)}
                  placeholder="09xxxxxxxx"
                  disabled={busy}
                />
              </label>
              <label className="field-block">
                الاسم الأول
                <input
                  value={guestFirst}
                  onChange={(e) => setGuestFirst(e.target.value)}
                  disabled={busy}
                />
              </label>
              <label className="field-block">
                الاسم الأخير
                <input
                  value={guestLast}
                  onChange={(e) => setGuestLast(e.target.value)}
                  disabled={busy}
                />
              </label>
            </div>
          </>
        )}

        {/* —— المواقع —— */}
        <h4 className="detail-section" style={{ marginTop: 18 }}>
          المواقع (مثل التطبيق)
        </h4>
        <MapPlacePicker
          label="نقطة الانطلاق (مكان العميل)"
          emoji="🟢"
          value={pickup}
          onChange={setPickup}
          disabled={busy}
          near={dest?.position ?? null}
        />
        <div style={{ marginTop: 16 }}>
          <MapPlacePicker
            label="نقطة الوصول (الوجهة)"
            emoji="🚩"
            value={dest}
            onChange={setDest}
            disabled={busy}
            near={pickup?.position ?? null}
          />
        </div>

        <label className="field-block" style={{ marginTop: 14, display: 'block' }}>
          ملاحظة / وصف
          <input
            value={locationDesc}
            onChange={(e) => setLocationDesc(e.target.value)}
            disabled={busy}
            style={{ width: '100%' }}
          />
        </label>

        <div style={{ marginTop: 18, display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          <button
            type="button"
            className="btn-primary"
            disabled={busy || driverId <= 0 || !pickup || !dest}
            onClick={() => void submit()}
          >
            {busy ? 'جاري الإرسال…' : 'إرسال للسائق'}
          </button>
          <Link to="/requests" className="btn-ghost" style={{ textDecoration: 'none' }}>
            إلغاء
          </Link>
        </div>
      </div>
    </div>
  );
}
