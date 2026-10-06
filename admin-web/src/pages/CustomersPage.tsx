import { useCallback, useEffect, useState } from 'react';
import { API } from '../api/endpoints';
import { deleteJson, fetchJsonAuth } from '../api/http';
import { staffHas, useAuth } from '../auth/AuthContext';
import { CustomerWalletModal } from '../components/CustomerWalletModal';
import { ListPagination } from '../components/ListPagination';
import { NameSearchField } from '../components/NameSearchField';
import { PageHeader } from '../components/PageHeader';
import { formatApiFailure } from '../util/apiError';
import { usePersistedState, useResetOnChange, useScrollRestore } from '../util/pageState';
const CUSTOMERS_PAGE_SIZE = 50;
type CustomersListPage = {
  rows: Record<string, unknown>[];
  currentPage: number;
  lastPage: number;
  total: number;
};
async function fetchCustomersPage(
  page: number,
  search: string,
): Promise<CustomersListPage> {
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
    currentPage: Number(payload.current_page ?? page),
    lastPage: Number(payload.last_page ?? 1),
    total: Number(payload.total ?? inner.length),
  };
}
export function CustomersPage() {
  const { user } = useAuth();
  const canDelete =
    user &&
    (user.roll === 'Admin' || staffHas(user.roll, user.permissions, 'customers.read'));
  const [page, setPage] = useState<CustomersListPage | null>(null);
  const [currentPage, setCurrentPage] = usePersistedState('customers.page', 1);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');
  const [nameQuery, setNameQuery] = usePersistedState('customers.search', '');
  const [debouncedName, setDebouncedName] = useState(() => nameQuery.trim());
  const [walletFor, setWalletFor] = useState<{ id: number; name: string } | null>(null);
  useEffect(() => {
    const id = window.setTimeout(() => setDebouncedName(nameQuery.trim()), 350);
    return () => window.clearTimeout(id);
  }, [nameQuery]);
  useResetOnChange([debouncedName], () => setCurrentPage(1));
  const load = useCallback(
    async (pageNum: number) => {
      setLoading(true);
      setErr('');
      try {
        const result = await fetchCustomersPage(pageNum, debouncedName);
        setPage(result);
        setCurrentPage(result.currentPage);
      } catch (e) {
        setErr(String(e));
        setPage(null);
      } finally {
        setLoading(false);
      }
    },
    [debouncedName, setCurrentPage],
  );
  useEffect(() => {
    void load(currentPage);
  }, [load, currentPage]);
  useScrollRestore('customers', !loading && (page?.rows.length ?? 0) > 0);
  async function removeCustomer(id: number, name: string) {
    if (!window.confirm(`حذف حساب «${name}»؟ (حذف منطقي)`)) return;
    try {
      const { res, data } = await deleteJson<Record<string, unknown>>(
        API.adminCustomerDestroy(id),
      );
      if (res.ok && data.success === true) {
        alert(String(data.message ?? 'تم الحذف'));
        void load(currentPage);
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } catch (e) {
      alert(String(e));
    }
  }
  const list = page?.rows ?? [];
  const totalCount = page?.total ?? 0;
  return (
    <div className="page-pad">
      <PageHeader
        title="الزبائن المسجّلون"
        subtitle="بحث بالاسم أو رقم الهاتف وإدارة الحسابات."
        onRefresh={() => void load(currentPage)}
        refreshing={loading}
      />
      <div className="page-meta">
        <span className="meta-pill">
          الإجمالي <strong>{totalCount}</strong>
        </span>
      </div>
      {err && <p className="text-err">{err}</p>}
      <NameSearchField
        value={nameQuery}
        onChange={setNameQuery}
        label="بحث باسم الزبون أو رقم الهاتف"
        placeholder="مثال: سارة، 09xxxxxxxx…"
        hint="النتائج تتحدث تلقائياً أثناء الكتابة"
      />
      <ListPagination
        currentPage={page?.currentPage ?? currentPage}
        lastPage={page?.lastPage ?? 1}
        total={totalCount}
        pageSize={CUSTOMERS_PAGE_SIZE}
        loading={loading}
        onPageChange={setCurrentPage}
      />
      <div className="card-list">
        {list.map((u) => {
          const id = Number(u.id ?? 0);
          const name = `${u.firstName ?? ''} ${u.lastName ?? ''}`.trim() || `زبون #${id}`;
          return (
            <div key={id} className="card">
              <div className="row-between">
                <div>
                  <div className="card-title">{name}</div>
                  <div className="text-muted">{String(u.number ?? '')}</div>
                </div>
                <div className="row-gap" style={{ gap: 8 }}>
                  <button
                    type="button"
                    className="btn-primary"
                    onClick={() => setWalletFor({ id, name })}
                  >
                    المحفظة
                  </button>
                  {canDelete && (
                    <button
                      type="button"
                      className="btn-warn"
                      onClick={() => void removeCustomer(id, name)}
                    >
                      حذف
                    </button>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>
      {!list.length && !err && !loading && debouncedName && (
        <p className="text-muted">لا زبون يطابق «{debouncedName}».</p>
      )}
      {!list.length && !err && !loading && !debouncedName && (
        <p className="text-muted">لا يوجد زبائن</p>
      )}
      <ListPagination
        currentPage={page?.currentPage ?? currentPage}
        lastPage={page?.lastPage ?? 1}
        total={totalCount}
        pageSize={CUSTOMERS_PAGE_SIZE}
        loading={loading}
        onPageChange={setCurrentPage}
      />
      {walletFor && (
        <CustomerWalletModal
          customerId={walletFor.id}
          customerName={walletFor.name}
          onClose={() => setWalletFor(null)}
        />
      )}
    </div>
  );
}
