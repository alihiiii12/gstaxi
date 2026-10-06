import { useCallback, useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { API } from '../api/endpoints';
import { fetchJsonAuth, postJson } from '../api/http';
import { ListPagination } from '../components/ListPagination';
import { NameSearchField } from '../components/NameSearchField';
import { PageHeader } from '../components/PageHeader';
import { staffHas, useAuth } from '../auth/AuthContext';
import { statusArabic } from '../util/adminRequestLabels';
import { pickupDestLabelsFromRequest } from '../util/requestDetailFields';
import { tripPathLabelArabic } from '../util/tripPathLabels';
import { usePersistedState, useResetOnChange, useScrollRestore } from '../util/pageState';

const STATUS_OPTIONS: { value: string; label: string }[] = [
  { value: '', label: 'الكل' },
  { value: 'Pending', label: 'قيد الانتظار (لم يُقبل بعد)' },
  { value: 'Reserved', label: 'غير مكتملة — محجوز' },
  { value: 'DriverArrived', label: 'غير مكتملة — وصل السائق' },
  { value: 'AwaitingDestination', label: 'غير مكتملة — بانتظار الوجهة' },
  { value: 'Running', label: 'جارية' },
  { value: 'Finished', label: 'مكتملة' },
  { value: 'Removed', label: 'ملغاة' },
];

const REQUESTS_PAGE_SIZE = 50;

function useDebounced(value: string, ms = 400): string {
  const [v, setV] = useState(value);
  useEffect(() => {
    const t = window.setTimeout(() => setV(value), ms);
    return () => window.clearTimeout(t);
  }, [value, ms]);
  return v;
}

export function RequestsPage() {
  const { user } = useAuth();
  const canWrite =
    user != null && staffHas(user.roll, user.permissions, 'requests.write');
  const [searchParams] = useSearchParams();
  const [filter, setFilter] = usePersistedState('requests.status', '');
  const [billing, setBilling] = usePersistedState('requests.billing', '');
  const [search, setSearch] = usePersistedState('requests.search', '');
  const debouncedSearch = useDebounced(search.trim());
  const [page, setPage] = usePersistedState('requests.page', 1);
  const [list, setList] = useState<Record<string, unknown>[]>([]);
  const [total, setTotal] = useState(0);
  const [lastPage, setLastPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');

  useEffect(() => {
    const b = searchParams.get('billing') ?? '';
    if (b) setBilling(b);
  }, [searchParams, setBilling]);

  const load = useCallback(async () => {
    setErr('');
    setLoading(true);
    try {
      const q = new URLSearchParams({
        per_page: String(REQUESTS_PAGE_SIZE),
        page: String(page),
      });
      if (filter) q.set('status', filter);
      if (billing) q.set('billing_kind', billing);
      if (debouncedSearch) q.set('search', debouncedSearch);
      const { res, data: j } = await fetchJsonAuth(`${API.adminRequests}?${q}`);
      if (!res.ok || j.success !== true) {
        throw new Error(String(j.message ?? res.statusText));
      }
      const payload = (j.data as Record<string, unknown>) ?? {};
      const rows = Array.isArray(payload.data)
        ? (payload.data as Record<string, unknown>[])
        : [];
      setList(rows);
      setTotal(Number(payload.total ?? rows.length));
      setLastPage(Math.max(1, Number(payload.last_page ?? 1)));
    } catch (e) {
      setErr(String(e));
      setList([]);
      setTotal(0);
      setLastPage(1);
    } finally {
      setLoading(false);
    }
  }, [filter, billing, debouncedSearch, page]);

  useResetOnChange([filter, billing, debouncedSearch], () => setPage(1));

  useEffect(() => {
    void load();
  }, [load]);

  useScrollRestore('requests', !loading && list.length > 0);

  async function expire(id: number) {
    if (!confirm(`إزالة الطلب #${id} من قائمة الانتظار؟`)) return;
    const { res, data } = await postJson<Record<string, unknown>>(
      API.adminExpirePending(id),
      {},
    );
    const ok = res.ok && (data.success === true || data.state === true);
    alert(ok ? String(data.message ?? 'تم') : String(data.message ?? 'فشل'));
    await load();
  }

  return (
    <div className="page-pad">
      <PageHeader
        title="الطلبات والتتبع"
        subtitle="فلترة وبحث سريع عن الرحلات حسب الحالة ونوع الفوترة ومعرّفات الأطراف."
        backTo="/"
        backLabel="الرئيسية"
        onRefresh={() => void load()}
        refreshing={loading}
        actions={
          <>
            {canWrite && (
              <Link
                to="/requests/dispatch"
                className="btn-primary"
                style={{ textDecoration: 'none' }}
              >
                إرسال طلب لسائق
              </Link>
            )}
            <Link to="/map" className="btn-ghost" style={{ textDecoration: 'none' }}>
              خريطة العمليات
            </Link>
          </>
        }
      />
      <div className="filter-row">
        <label>
          الحالة
          <select
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
          >
            {STATUS_OPTIONS.map((o) => (
              <option key={o.value || 'all'} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
        </label>
        <label>
          نوع الرحلة
          <select
            value={billing}
            onChange={(e) => setBilling(e.target.value)}
          >
            <option value="">الكل</option>
            <option value="app_request">طلب تطبيق</option>
            <option value="free_meter">عداد حر</option>
          </select>
        </label>
      </div>
      <NameSearchField
        value={search}
        onChange={setSearch}
        label="بحث: رقم الرحلة · اسم/هاتف الفارس · اسم/هاتف العميل · رقم اللوحة"
        placeholder="مثال: 1234 أو 09xxxxxxxx أو اسم السائق…"
        hint="يدعم رقم الرحلة وهاتف السائق والعميل"
      />
      <div className="page-meta">
        <span className="meta-pill">
          المطابق <strong>{total}</strong>
        </span>
        {loading ? <span className="meta-pill">جاري التحميل…</span> : null}
      </div>
      {err && <p className="text-err">{err}</p>}
      <ListPagination
        currentPage={page}
        lastPage={lastPage}
        total={total}
        pageSize={REQUESTS_PAGE_SIZE}
        loading={loading}
        onPageChange={setPage}
      />
      <div className="card-list">
        {list.map((r) => {
          const id = parseInt(String(r.id ?? 0), 10);
          const st = String(r.status ?? '');
          const stLabel = statusArabic(st, r.driverId);
          const user = r.user as Record<string, unknown> | undefined;
          const driver = r.driver as Record<string, unknown> | undefined;
          const driverUser = driver?.user as Record<string, unknown> | undefined;
          const isGuest = r.is_guest_customer === true;
          const name =
            (`${user?.firstName ?? ''} ${user?.lastName ?? ''}`.trim() || 'زبون') +
            (isGuest ? ' (غير مسجّل)' : '');
          const driverName =
            `${driverUser?.firstName ?? ''} ${driverUser?.lastName ?? ''}`.trim();
          const plate = String(driver?.carNumber ?? driver?.car_number ?? '').trim();
          const driverPhone = String(driverUser?.number ?? '').trim();
          const custPhone = String(user?.number ?? '').trim();
          const coupon = r.discountCode ?? r.discount_code;
          const isMeter = String(r.billing_kind ?? '') === 'free_meter';
          const pendingNoDriver = st === 'Pending' && !r.driverId;
          const stuckAfterAccept =
            st === 'Reserved' ||
            st === 'DriverArrived' ||
            st === 'AwaitingDestination';
          const canAdminRemove = pendingNoDriver || stuckAfterAccept;
          const { pickup, dest } = pickupDestLabelsFromRequest(r);
          return (
            <div key={id} className="card">
              <div className="row-between">
                <Link to={`/requests/${id}`} className="card-link">
                  <div className="card-title">
                    طلب #{id} — {stLabel}
                    {isMeter ? ' · عداد' : ''}
                  </div>
                  <div className="text-muted">
                    {name}
                    {custPhone ? ` · ${custPhone}` : ''}
                    {driverName ? `\nالسائق: ${driverName}` : ''}
                    {driverPhone ? ` · ${driverPhone}` : ''}
                    {plate ? `\nاللوحة: ${plate}` : ''}
                    {coupon ? `\nكوبون: ${String(coupon)}` : ''}
                  </div>
                  <div className="text-muted small" style={{ marginTop: 6 }}>
                    انطلاق: {pickup}
                    <br />
                    وجهة: {dest}
                  </div>
                  <div className="text-muted small" style={{ marginTop: 4 }}>
                    {tripPathLabelArabic(r)}
                  </div>
                </Link>
                <div className="row-gap" style={{ flexDirection: 'column', alignItems: 'stretch' }}>
                  <Link
                    to={`/requests/${id}`}
                    className="btn-ghost"
                    style={{ textDecoration: 'none', textAlign: 'center', fontSize: 12 }}
                  >
                    التفاصيل
                  </Link>
                  {st === 'Running' && (
                    <Link
                      to="/map"
                      className="btn-primary"
                      style={{ textDecoration: 'none', textAlign: 'center', fontSize: 12 }}
                    >
                      على الخريطة
                    </Link>
                  )}
                  {canAdminRemove && (
                    <button type="button" className="btn-warn" onClick={() => void expire(id)}>
                      {stuckAfterAccept ? 'إلغاء عالق' : 'إزالة'}
                    </button>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>
      <ListPagination
        currentPage={page}
        lastPage={lastPage}
        total={total}
        pageSize={REQUESTS_PAGE_SIZE}
        loading={loading}
        onPageChange={setPage}
      />
      {!list.length && !err && !loading && <p className="text-muted">لا توجد طلبات</p>}
    </div>
  );
}
