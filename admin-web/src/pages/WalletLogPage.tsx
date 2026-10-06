import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { API } from '../api/endpoints';
import { fetchJsonAuth } from '../api/http';
import { CustomerWalletModal } from '../components/CustomerWalletModal';
import { ListPagination } from '../components/ListPagination';
import { PageHeader } from '../components/PageHeader';
import { usePersistedState, useResetOnChange, useScrollRestore } from '../util/pageState';

const PAGE_SIZE = 50;

const TYPE_OPTIONS: { value: string; label: string }[] = [
  { value: '', label: 'كل الحركات' },
  { value: 'trip_payment', label: 'دفع أجرة رحلة' },
  { value: 'admin_topup', label: 'تعبئة رصيد' },
  { value: 'admin_deduct', label: 'خصم بواسطة الإدارة' },
  { value: 'admin_adjust', label: 'تصحيح رصيد' },
];

type Row = Record<string, unknown>;
type Totals = Record<string, { total: number; count: number }>;

function fmt(n: number): string {
  return n.toLocaleString('ar-SY');
}

export function WalletLogPage() {
  const [rows, setRows] = useState<Row[]>([]);
  const [totals, setTotals] = useState<Totals>({});
  const [currentPage, setCurrentPage] = usePersistedState('walletLog.page', 1);
  const [lastPage, setLastPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');
  const [type, setType] = usePersistedState('walletLog.type', '');
  const [from, setFrom] = usePersistedState('walletLog.from', '');
  const [to, setTo] = usePersistedState('walletLog.to', '');
  const [search, setSearch] = usePersistedState('walletLog.search', '');
  const [debouncedSearch, setDebouncedSearch] = useState(() => search.trim());
  const [walletFor, setWalletFor] = useState<{ id: number; name: string } | null>(null);

  useEffect(() => {
    const id = window.setTimeout(() => setDebouncedSearch(search.trim()), 350);
    return () => window.clearTimeout(id);
  }, [search]);

  useResetOnChange([type, from, to, debouncedSearch], () => setCurrentPage(1));

  const load = useCallback(
    async (page: number) => {
      setLoading(true);
      setErr('');
      try {
        const q = new URLSearchParams();
        q.set('page', String(page));
        q.set('per_page', String(PAGE_SIZE));
        if (type) q.set('type', type);
        if (from) q.set('from', from);
        if (to) q.set('to', to);
        if (debouncedSearch) q.set('search', debouncedSearch);
        const { res, data: j } = await fetchJsonAuth(`${API.customerWalletsLog}?${q}`);
        if (!res.ok || j.success !== true) {
          throw new Error(String(j.message ?? res.statusText));
        }
        const d = (j.data as Record<string, unknown>) ?? {};
        setRows(Array.isArray(d.rows) ? (d.rows as Row[]) : []);
        setTotals((d.totals as Totals) ?? {});
        setLastPage(Number(d.last_page ?? 1));
        setTotal(Number(d.total ?? 0));
        setCurrentPage(Number(d.current_page ?? page));
      } catch (e) {
        setErr(String(e));
        setRows([]);
      } finally {
        setLoading(false);
      }
    },
    [type, from, to, debouncedSearch, setCurrentPage],
  );

  useEffect(() => {
    void load(currentPage);
  }, [load, currentPage]);
  useScrollRestore('walletLog', !loading && rows.length > 0);

  const tripTotal = Math.abs(totals.trip_payment?.total ?? 0);
  const topupTotal = totals.admin_topup?.total ?? 0;

  return (
    <div className="page-pad">
      <PageHeader
        title="سجل محافظ الزبائن"
        subtitle="كل دفعات الرحلات من المحفظة (الراكب ← السائق) وعمليات التعبئة والخصم والتصحيح."
        onRefresh={() => void load(currentPage)}
        refreshing={loading}
      />

      <div className="page-meta">
        <span className="meta-pill">
          الحركات <strong>{total}</strong>
        </span>
        <span className="meta-pill">
          مدفوعات الرحلات <strong>{fmt(tripTotal)} ل.س</strong> ({totals.trip_payment?.count ?? 0})
        </span>
        <span className="meta-pill">
          التعبئة <strong>{fmt(topupTotal)} ل.س</strong> ({totals.admin_topup?.count ?? 0})
        </span>
      </div>

      <div className="card stack-tight">
        <div className="row-between wrap" style={{ gap: 12 }}>
          <label style={{ minWidth: 170 }}>
            نوع الحركة
            <select value={type} onChange={(e) => setType(e.target.value)}>
              {TYPE_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          </label>
          <label>
            من تاريخ
            <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </label>
          <label>
            إلى تاريخ
            <input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          </label>
          <label style={{ flex: 1, minWidth: 200 }}>
            بحث (اسم/هاتف الراكب أو السائق، أو رقم الرحلة)
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="مثال: أحمد، 09xxxxxxxx، 66703"
            />
          </label>
        </div>
      </div>

      {err && <p className="text-err">{err}</p>}

      <ListPagination
        currentPage={currentPage}
        lastPage={lastPage}
        total={total}
        pageSize={PAGE_SIZE}
        loading={loading}
        onPageChange={setCurrentPage}
      />

      {rows.length > 0 ? (
        <div className="card" style={{ overflowX: 'auto' }}>
          <table className="data-table" style={{ width: '100%', fontSize: 13 }}>
            <thead>
              <tr>
                <th>التاريخ</th>
                <th>النوع</th>
                <th>المبلغ</th>
                <th>الراكب</th>
                <th>السائق (المدفوع له)</th>
                <th>رحلة</th>
                <th>رصيد الراكب بعدها</th>
                <th>بواسطة</th>
                <th>ملاحظة</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((tx) => {
                const amt = Number(tx.amount ?? 0);
                const cid = Number(tx.customer_id ?? tx.user_id ?? 0);
                const cname = String(tx.customer_name ?? `زبون #${cid}`);
                const did = Number(tx.driver_id ?? 0);
                return (
                  <tr key={String(tx.id)}>
                    <td>
                      {tx.created_at ? new Date(String(tx.created_at)).toLocaleString('ar-SY') : '—'}
                    </td>
                    <td>{String(tx.type_label ?? tx.type ?? '')}</td>
                    <td style={{ color: amt < 0 ? '#b91c1c' : '#15803d', fontWeight: 600 }}>
                      {amt > 0 ? '+' : ''}
                      {fmt(amt)}
                    </td>
                    <td>
                      <button
                        type="button"
                        className="btn-link"
                        onClick={() => cid > 0 && setWalletFor({ id: cid, name: cname })}
                        style={{ background: 'none', border: 0, padding: 0, color: 'inherit', textDecoration: 'underline', cursor: 'pointer' }}
                      >
                        {cname}
                      </button>
                      {tx.customer_phone ? (
                        <div className="text-muted" style={{ fontSize: 11 }}>
                          {String(tx.customer_phone)}
                        </div>
                      ) : null}
                    </td>
                    <td>
                      {did > 0 ? (
                        <Link to={`/drivers/${did}/edit`}>{String(tx.driver_name ?? `سائق #${did}`)}</Link>
                      ) : (
                        '—'
                      )}
                    </td>
                    <td>
                      {tx.request_id ? (
                        <Link to={`/requests/${String(tx.request_id)}`}>#{String(tx.request_id)}</Link>
                      ) : (
                        '—'
                      )}
                    </td>
                    <td>{fmt(Number(tx.balance_after ?? 0))}</td>
                    <td>{String(tx.created_by_name ?? (tx.type === 'trip_payment' ? 'الراكب' : '—'))}</td>
                    <td>{String(tx.note ?? '—')}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      ) : (
        !loading && !err && <p className="text-muted">لا توجد حركات مطابقة</p>
      )}

      <ListPagination
        currentPage={currentPage}
        lastPage={lastPage}
        total={total}
        pageSize={PAGE_SIZE}
        loading={loading}
        onPageChange={setCurrentPage}
      />

      {walletFor && (
        <CustomerWalletModal
          customerId={walletFor.id}
          customerName={walletFor.name}
          onClose={() => {
            setWalletFor(null);
            void load(currentPage);
          }}
        />
      )}
    </div>
  );
}
