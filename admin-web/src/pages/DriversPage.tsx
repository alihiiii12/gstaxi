import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { API } from '../api/endpoints';
import { deleteJson, fetchJsonAuth, postJson } from '../api/http';
import { loadCarTypesForPricing } from '../api/carTypes';
import { staffHas, useAuth } from '../auth/AuthContext';
import { DriverCategoryFilterBar } from '../components/DriverCategoryFilterBar';
import { ListPagination } from '../components/ListPagination';
import { ModalPortal } from '../components/ModalPortal';
import { NameSearchField } from '../components/NameSearchField';
import { PageHeader } from '../components/PageHeader';
import { formatApiFailure } from '../util/apiError';
import { adminDriverCardSubtitle } from '../util/driverSubtitle';
import { isDriverSubscriptionBlocked } from '../util/driverSubscriptionDates';
import { resolveMediaUrl } from '../util/mediaUrl';
import { usePersistedState, useResetOnChange, useScrollRestore } from '../util/pageState';
const DRIVERS_PAGE_SIZE = 30;
type DriversListPage = {
  rows: Record<string, unknown>[];
  currentPage: number;
  lastPage: number;
  total: number;
};
async function fetchDriversPage(
  transTypeId: number | null,
  page: number,
  search: string,
  blockedOnly: boolean,
): Promise<DriversListPage> {
  const q = new URLSearchParams();
  q.set('per_page', String(DRIVERS_PAGE_SIZE));
  q.set('page', String(page));
  if (search) q.set('search', search);
  if (blockedOnly) q.set('blocked', '1');
  if (transTypeId != null && transTypeId > 0) {
    q.set('transTypeId', String(transTypeId));
  }
  const { data: j } = await fetchJsonAuth(`${API.driversIndex}?${q}`);
  if (j.success !== true) throw new Error(String(j.message ?? ''));
  const data = (j.data as Record<string, unknown>) ?? {};
  const innerData = (data.data as unknown[]) ?? [];
  const rows = Array.isArray(innerData)
    ? innerData.map((e) => e as Record<string, unknown>)
    : [];
  return {
    rows,
    currentPage: Number(data.current_page ?? 1),
    lastPage: Math.max(1, Number(data.last_page ?? 1)),
    total: Number(data.total ?? rows.length),
  };
}
export function DriversPage() {
  const { user } = useAuth();
  const canWrite = user && staffHas(user.roll, user.permissions, 'drivers.write');
  const [rows, setRows] = useState<Record<string, unknown>[]>([]);
  const [listPage, setListPage] = usePersistedState('drivers.page', 1);
  const [listLastPage, setListLastPage] = useState(1);
  const [listTotal, setListTotal] = useState(0);
  const [listLoading, setListLoading] = useState(false);
  const [totalCount, setTotalCount] = useState(0);
  const [blockedTotal, setBlockedTotal] = useState(0);
  const [blockedOnly, setBlockedOnly] = usePersistedState('drivers.blockedOnly', false);
  const [countByCategoryId, setCountByCategoryId] = useState<Map<number, number>>(
    () => new Map(),
  );
  const [categories, setCategories] = useState<Record<string, unknown>[]>([]);
  const [filterCatId, setFilterCatId] = usePersistedState<number | null>('drivers.category', null);
  const [err, setErr] = useState('');
  const [nameQuery, setNameQuery] = usePersistedState('drivers.search', '');
  const [debouncedName, setDebouncedName] = useState(() => nameQuery.trim());
  const [subModal, setSubModal] = useState<{
    id: number;
    name: string;
  } | null>(null);
  const [subStarts, setSubStarts] = useState('');
  const [subEnds, setSubEnds] = useState('');
  const [subBusy, setSubBusy] = useState(false);
  useEffect(() => {
    const id = window.setTimeout(() => setDebouncedName(nameQuery.trim()), 350);
    return () => window.clearTimeout(id);
  }, [nameQuery]);
  useResetOnChange([filterCatId, debouncedName, blockedOnly], () => setListPage(1));
  const loadCounts = useCallback(async () => {
    try {
      const { data: j } = await fetchJsonAuth(API.driversStats);
      if (j.success !== true) throw new Error(String(j.message ?? ''));
      const data = (j.data as Record<string, unknown>) ?? {};
      setTotalCount(Number(data.total ?? 0));
      setBlockedTotal(Number(data.blocked_total ?? 0));
      const byCat = (data.by_category as unknown[]) ?? [];
      const m = new Map<number, number>();
      for (const item of byCat) {
        if (!item || typeof item !== 'object') continue;
        const row = item as Record<string, unknown>;
        const tid = Number(row.transTypeId ?? 0);
        const n = Number(row.count ?? 0);
        if (tid > 0) m.set(tid, n);
      }
      setCountByCategoryId(m);
    } catch {
      setTotalCount(0);
      setBlockedTotal(0);
      setCountByCategoryId(new Map());
    }
  }, []);
  const load = useCallback(async () => {
    setErr('');
    setListLoading(true);
    try {
      const result = await fetchDriversPage(
        filterCatId,
        listPage,
        debouncedName,
        blockedOnly,
      );
      setRows(result.rows);
      setListLastPage(result.lastPage);
      setListTotal(result.total);
      if (result.currentPage !== listPage) {
        setListPage(result.currentPage);
      }
    } catch (e) {
      setErr(String(e));
      setRows([]);
      setListTotal(0);
      setListLastPage(1);
    } finally {
      setListLoading(false);
    }
  }, [filterCatId, listPage, debouncedName, blockedOnly, setListPage]);
  useEffect(() => {
    void loadCarTypesForPricing().then(setCategories);
  }, []);
  useEffect(() => {
    void load();
  }, [load]);
  useScrollRestore('drivers', !listLoading && rows.length > 0);
  useEffect(() => {
    void loadCounts();
  }, [loadCounts]);
  const refreshAll = useCallback(() => {
    void load();
    void loadCounts();
  }, [load, loadCounts]);
  async function renewSubscription(id: number, name: string) {
    const today = new Date();
    const y = today.getFullYear();
    const m = `${today.getMonth() + 1}`.padStart(2, '0');
    const d = `${today.getDate()}`.padStart(2, '0');
    const start = `${y}-${m}-${d}`;
    const endDate = new Date(today.getTime() + 30 * 24 * 60 * 60 * 1000);
    const ey = endDate.getFullYear();
    const em = `${endDate.getMonth() + 1}`.padStart(2, '0');
    const ed = `${endDate.getDate()}`.padStart(2, '0');
    setSubStarts(start);
    setSubEnds(`${ey}-${em}-${ed}`);
    setSubModal({ id, name });
  }

  async function submitSubscriptionPeriod() {
    if (!subModal) return;
    if (!subStarts || !subEnds) {
      alert('حدد تاريخ البداية والنهاية');
      return;
    }
    if (subEnds < subStarts) {
      alert('تاريخ النهاية يجب أن يكون بعد البداية');
      return;
    }
    setSubBusy(true);
    try {
      const { res, data } = await postJson<Record<string, unknown>>(
        API.driverSubscriptionSetPeriod(subModal.id),
        { starts_at: subStarts, ends_at: subEnds },
      );
      if (res.ok && data.success === true) {
        alert(String(data.message ?? 'تم ضبط الاشتراك'));
        setSubModal(null);
        refreshAll();
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } catch (e) {
      alert(String(e));
    } finally {
      setSubBusy(false);
    }
  }

  async function quickRenew30() {
    if (!subModal) return;
    if (
      !window.confirm(
        `تجديد سريع 30 يوماً من اليوم لـ «${subModal.name}»؟`,
      )
    ) {
      return;
    }
    setSubBusy(true);
    try {
      const { res, data } = await postJson<Record<string, unknown>>(
        API.driverSubscriptionRenew(subModal.id),
        {},
      );
      if (res.ok && data.success === true) {
        alert(String(data.message ?? 'تم التجديد'));
        setSubModal(null);
        refreshAll();
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } catch (e) {
      alert(String(e));
    } finally {
      setSubBusy(false);
    }
  }
  async function blockDriver(id: number, name: string) {
    if (
      !window.confirm(
        `حظر السائق «${name}» يدوياً؟ لن يستطيع تسجيل الدخول ولن يظهر للركاب.`,
      )
    ) {
      return;
    }
    try {
      const { res, data } = await postJson<Record<string, unknown>>(
        API.driverSubscriptionBlock(id),
        {},
      );
      if (res.ok && data.success === true) {
        alert(String(data.message ?? 'تم الحظر'));
        refreshAll();
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } catch (e) {
      alert(String(e));
    }
  }
  async function unblockDriver(id: number, name: string) {
    if (!window.confirm(`إلغاء حظر السائق «${name}»؟`)) return;
    try {
      const { res, data } = await postJson<Record<string, unknown>>(
        API.driverSubscriptionUnblock(id),
        {},
      );
      if (res.ok && data.success === true) {
        alert(String(data.message ?? 'تم إلغاء الحظر'));
        refreshAll();
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } catch (e) {
      alert(String(e));
    }
  }
  async function removeDriver(id: number, name: string) {
    if (!window.confirm(`حذف حساب «${name}»؟ (حذف منطقي)`)) return;
    try {
      const { res, data } = await deleteJson<Record<string, unknown>>(
        API.driverDestroy(id),
      );
      if (res.ok && data.success === true) {
        alert(String(data.message ?? 'تم الحذف'));
        refreshAll();
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } catch (e) {
      alert(String(e));
    }
  }
  return (
    <div className="page-pad">
      <PageHeader
        title="السائقون"
        subtitle="إدارة الملفات والاشتراك والبحث بالاسم أو اللوحة أو الهاتف."
        onRefresh={() => refreshAll()}
        refreshing={listLoading}
        actions={
          canWrite ? (
            <Link to="/drivers/new" className="btn-primary" style={{ textDecoration: 'none' }}>
              سائق جديد
            </Link>
          ) : null
        }
      />
      {err && <p className="text-err">{err}</p>}
      <div className="page-meta">
        <span className="meta-pill">
          الإجمالي <strong>{totalCount}</strong>
        </span>
        <span className="meta-pill meta-pill-warn">
          محظورون <strong>{blockedTotal}</strong>
        </span>
      </div>
      <NameSearchField
        value={nameQuery}
        onChange={setNameQuery}
        label="بحث بالاسم أو رقم اللوحة أو الهاتف"
        placeholder="مثال: أحمد، 09xxxxxxxx، 50/29978…"
        hint="النتائج تتحدث تلقائياً أثناء الكتابة"
      />
      <DriverCategoryFilterBar
        categories={categories}
        totalCount={totalCount}
        blockedCount={blockedTotal}
        countByCategoryId={countByCategoryId}
        activeId={filterCatId}
        blockedOnly={blockedOnly}
        onSelect={(id) => {
          setBlockedOnly(false);
          setFilterCatId(id);
        }}
        onBlockedToggle={() => {
          setBlockedOnly((v) => !v);
          setFilterCatId(null);
        }}
      />
      {listLoading && !rows.length ? (
        <p className="text-muted">جاري التحميل…</p>
      ) : (
        <div className="card-list">
          {rows.map((row) => {
            const id = Number(row.id ?? 0);
            const u = (row.user as Record<string, unknown>) ?? {};
            const name = `${u.firstName ?? ''} ${u.lastName ?? ''}`.trim() || `سائق #${id}`;
            const sub = adminDriverCardSubtitle(row, u);
            const blocked = isDriverSubscriptionBlocked(row);
            const driverPhoto = resolveMediaUrl(
              row.driver_photo_url ?? row.driverPhotoUrl,
            );
            const carPhoto = resolveMediaUrl(row.car_photo_url ?? row.carPhotoUrl);
            const inner = (
              <div className="driver-preview-row">
                <DriverThumbnails
                  name={name}
                  driverUrl={driverPhoto}
                  carUrl={carPhoto}
                />
                <div className="driver-preview-text">
                  <div className="card-title">{name}</div>
                  <pre className="card-sub">{sub}</pre>
                </div>
              </div>
            );
            return (
              <div key={id} className="card">
                <div className="row-between" style={{ gap: 8 }}>
                  {canWrite ? (
                    <Link
                      to={`/drivers/${id}/edit`}
                      state={{ row }}
                      className="card-link"
                      style={{ flex: 1, minWidth: 0 }}
                    >
                      <div className="card-body">{inner}</div>
                    </Link>
                  ) : (
                    <div className="card-body" style={{ flex: 1 }}>
                      {inner}
                    </div>
                  )}
                  {canWrite && (
                    <div
                      className="row-gap"
                      style={{
                        alignSelf: 'center',
                        flexShrink: 0,
                        flexDirection: 'column',
                      }}
                    >
                      <button
                        type="button"
                        className="btn-primary"
                        style={{ fontSize: 13 }}
                        onClick={() => void renewSubscription(id, name)}
                      >
                        اشتراك / فترة
                      </button>
                      {blocked ? (
                        <button
                          type="button"
                          className="btn-ghost"
                          style={{ fontSize: 13 }}
                          onClick={() => void unblockDriver(id, name)}
                        >
                          إلغاء الحظر
                        </button>
                      ) : (
                        <button
                          type="button"
                          className="btn-warn"
                          style={{ fontSize: 13 }}
                          onClick={() => void blockDriver(id, name)}
                        >
                          حظر يدوي
                        </button>
                      )}
                      <button
                        type="button"
                        className="btn-warn"
                        style={{ fontSize: 13 }}
                        onClick={() => void removeDriver(id, name)}
                      >
                        حذف
                      </button>
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
      <ListPagination
        currentPage={listPage}
        lastPage={listLastPage}
        total={listTotal}
        pageSize={DRIVERS_PAGE_SIZE}
        loading={listLoading}
        onPageChange={(p) => {
          setListPage(p);
          window.scrollTo({ top: 0, behavior: 'smooth' });
        }}
      />
      {!rows.length && !err && !listLoading && debouncedName && (
        <p className="text-muted">لا سائق يطابق «{debouncedName}».</p>
      )}
      {!rows.length && !err && !listLoading && !debouncedName && (
        <p className="text-muted">لا بيانات</p>
      )}

      {subModal && (
        <ModalPortal onClose={() => !subBusy && setSubModal(null)}>
          <div
            className="modal"
            role="dialog"
            onClick={(ev) => ev.stopPropagation()}
            dir="rtl"
          >
            <h3>فترة الاشتراك — {subModal.name}</h3>
            <p className="text-muted" style={{ marginTop: 0 }}>
              اختر تاريخ بداية ونهاية الاشتراك، أو جدّد 30 يوماً من اليوم.
            </p>
            <label>
              من تاريخ
              <input
                type="date"
                value={subStarts}
                onChange={(e) => setSubStarts(e.target.value)}
                disabled={subBusy}
              />
            </label>
            <label>
              إلى تاريخ
              <input
                type="date"
                value={subEnds}
                onChange={(e) => setSubEnds(e.target.value)}
                disabled={subBusy}
              />
            </label>
            <div className="row-gap" style={{ marginTop: 12, flexWrap: 'wrap' }}>
              <button
                type="button"
                className="btn-ghost"
                disabled={subBusy}
                onClick={() => setSubModal(null)}
              >
                إلغاء
              </button>
              <button
                type="button"
                className="btn-ghost"
                disabled={subBusy}
                onClick={() => void quickRenew30()}
              >
                تجديد 30 يوم من اليوم
              </button>
              <button
                type="button"
                className="btn-primary"
                disabled={subBusy}
                onClick={() => void submitSubscriptionPeriod()}
              >
                حفظ الفترة
              </button>
            </div>
          </div>
        </ModalPortal>
      )}
    </div>
  );
}
function DriverThumbnails({
  name,
  driverUrl,
  carUrl,
}: {
  name: string;
  driverUrl?: string;
  carUrl?: string;
}) {
  const [driverBad, setDriverBad] = useState(false);
  const [carBad, setCarBad] = useState(false);
  return (
    <div className="driver-preview-thumbs" aria-hidden={false}>
      <div className="driver-face-wrap">
        {driverUrl && !driverBad ? (
          <img
            src={driverUrl}
            alt={`صورة ${name}`}
            className="driver-face-img"
            onError={() => setDriverBad(true)}
          />
        ) : (
          <div className="driver-face-placeholder" title="لا صورة">
            <span>👤</span>
          </div>
        )}
      </div>
      <div className="driver-car-wrap">
        {carUrl && !carBad ? (
          <img
            src={carUrl}
            alt={`سيارة ${name}`}
            className="driver-car-img"
            onError={() => setCarBad(true)}
          />
        ) : (
          <div className="driver-car-placeholder" title="لا صورة للسيارة">
            <span>🚕</span>
          </div>
        )}
      </div>
    </div>
  );
}
