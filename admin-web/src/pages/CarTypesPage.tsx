import { useCallback, useEffect, useState } from 'react';
import { API } from '../api/endpoints';
import { deleteJson, postJson, putJson } from '../api/http';
import { loadCarTypesForPricing } from '../api/carTypes';
import { PageHeader } from '../components/PageHeader';
import { formatApiFailure } from '../util/apiError';

type Row = Record<string, unknown>;

function normBadge(v: unknown): string {
  const s = String(v ?? 'economy').toLowerCase().trim();
  if (s === 'suv' || s === 'premium' || s === 'economy') return s;
  return 'economy';
}

function isReservedFreeMeterName(n: string): boolean {
  return n.trim() === 'العداد الحر';
}

function alsoDispatchIds(r: Row | null | undefined): number[] {
  const raw = r?.also_dispatch_to;
  if (!Array.isArray(raw)) return [];
  return raw.map((x) => Number(x)).filter((x) => Number.isFinite(x) && x > 0);
}

export function CarTypesPage() {
  const [rows, setRows] = useState<Row[]>([]);
  const [err, setErr] = useState('');
  const [loading, setLoading] = useState(true);
  const [createOpen, setCreateOpen] = useState(false);
  const [editRow, setEditRow] = useState<Row | null>(null);

  const load = useCallback(async () => {
    setErr('');
    setLoading(true);
    try {
      const list = await loadCarTypesForPricing();
      setRows(list);
    } catch (e) {
      setErr(String(e));
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function remove(id: number) {
    if (!window.confirm('حذف هذه الفئة؟ تأكد أن لا يوجد سائقون مرتبطون بها إن كانت السياسة تمنع الحذف.')) {
      return;
    }
    const { res, data: j } = await deleteJson(API.carTypesDestroy(id));
    if (res.ok && j.success === true) {
      alert(String(j.message ?? 'حُذفت الفئة'));
      void load();
    } else {
      alert(formatApiFailure(j, JSON.stringify(j)));
    }
  }

  return (
    <div className="page-pad">
      <PageHeader
        title="فئات السيارة (التسعير)"
        subtitle="طلب التطبيق فقط — العداد الحر من إعدادات العداد الحر."
        onRefresh={() => void load()}
        refreshing={loading}
        actions={
          <button type="button" className="btn-primary" onClick={() => setCreateOpen(true)}>
            + فئة جديدة
          </button>
        }
      />
      {err && <p className="text-err">{err}</p>}
      {loading ? (
        <div className="page-center">
          <div className="spinner" />
        </div>
      ) : (
        <div className="card-list">
          {rows.map((r) => {
            const id = Number(r.id ?? 0);
            const badge = normBadge(r.customer_badge ?? r.customerBadge);
            const extraNames = alsoDispatchIds(r)
              .map((x) => rows.find((o) => Number(o.id) === x))
              .filter((o): o is Row => !!o)
              .map((o) => String(o.name ?? ''));
            return (
              <div key={id} className="card">
                <div className="row-between">
                  <div>
                    <div className="card-title">{String(r.name ?? '')}</div>
                    <div className="text-muted" style={{ marginTop: 8, fontWeight: 600 }}>
                      تقدير طلب التطبيق: افتتاحي {String(r.openPrice ?? '—')} — كم{' '}
                      {String(r.KMPrice ?? '—')} — دقيقة {String(r.timePrice ?? '—')} (ل.س) — أيقونة:{' '}
                      {badge}
                    </div>
                    <div className="row-gap" style={{ gap: 6, flexWrap: 'wrap', marginTop: 8 }}>
                      <span className="coupon-badge" data-kind="uses">
                        📨 طلب «{String(r.name ?? '')}» يصل إلى:{' '}
                        {[String(r.name ?? ''), ...extraNames].join(' + ')}
                      </span>
                    </div>
                  </div>
                  <div className="row-gap">
                    <button type="button" className="btn-ghost" onClick={() => setEditRow(r)}>
                      تعديل
                    </button>
                    <button
                      type="button"
                      className="btn-warn"
                      disabled={id <= 0}
                      onClick={() => void remove(id)}
                    >
                      حذف
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
      {!loading && !rows.length && !err && (
        <p className="text-muted">
          لا توجد فئات بعد. أضف فئة بسعر الكيلو والدقيقة، ثم اربط السائقين بها من «سائقون».
        </p>
      )}

      {createOpen && (
        <CarTypeFormModal
          title="فئة سيارة جديدة"
          onClose={() => setCreateOpen(false)}
          onSubmit={async (payload) => {
            const { res, data } = await postJson<Record<string, unknown>>(
              API.carTypesStore,
              payload,
            );
            if ((res.status === 200 || res.status === 201) && data.success === true) {
              alert(String(data.message ?? 'أُضيفت الفئة'));
              setCreateOpen(false);
              void load();
            } else {
              alert(formatApiFailure(data, JSON.stringify(data)));
            }
          }}
        />
      )}
      {editRow && (
        <CarTypeFormModal
          title="تعديل فئة السيارة"
          initial={editRow}
          allRows={rows}
          onClose={() => setEditRow(null)}
          onSubmit={async (payload) => {
            const { res, data } = await putJson<Record<string, unknown>>(
              API.carTypesUpdate,
              payload,
            );
            if (res.ok && data.success === true) {
              alert(String(data.message ?? 'حُفظ التعديل'));
              setEditRow(null);
              void load();
            } else {
              alert(formatApiFailure(data, JSON.stringify(data)));
            }
          }}
        />
      )}
    </div>
  );
}

function CarTypeFormModal({
  title,
  initial,
  allRows = [],
  onClose,
  onSubmit,
}: {
  title: string;
  initial?: Row | null;
  allRows?: Row[];
  onClose: () => void;
  onSubmit: (body: Record<string, unknown>) => Promise<void>;
}) {
  const isEdit = !!initial;
  const selfId = Number(initial?.id ?? 0);
  const otherTypes = allRows.filter((o) => Number(o.id ?? 0) !== selfId);
  const [alsoTo, setAlsoTo] = useState<number[]>(alsoDispatchIds(initial));
  const [name, setName] = useState(String(initial?.name ?? ''));
  const [openPrice, setOpenPrice] = useState(String(initial?.openPrice ?? '0'));
  const [km, setKm] = useState(String(initial?.KMPrice ?? ''));
  const [time, setTime] = useState(String(initial?.timePrice ?? ''));
  const [badge, setBadge] = useState(
    normBadge(initial?.customer_badge ?? initial?.customerBadge),
  );
  const [busy, setBusy] = useState(false);

  async function submit() {
    const n = name.trim();
    if (!n) {
      alert('أدخل اسم الفئة');
      return;
    }
    if (isReservedFreeMeterName(n)) {
      alert('لا تستخدم اسم «العداد الحر» — مخصص للنظام');
      return;
    }
    const kmN = Number(km);
    const tN = Number(time);
    const openN = Number(openPrice.trim() || '0');
    if (
      Number.isNaN(kmN) ||
      kmN < 0 ||
      Number.isNaN(tN) ||
      tN < 0 ||
      Number.isNaN(openN) ||
      openN < 0
    ) {
      alert('أدخل سعر افتتاحي وكيلومتر ودقيقة صحيحين (أرقام ≥ 0)');
      return;
    }
    setBusy(true);
    try {
      if (isEdit && initial) {
        const id = Number(initial.id ?? 0);
        const sort_order =
          Number(initial.sort_order ?? initial.sortOrder ?? 0) || 0;
        await onSubmit({
          id,
          name: n,
          openPrice: openN,
          KMPrice: kmN,
          timePrice: tN,
          sort_order,
          customer_badge: normBadge(badge),
          also_dispatch_to: alsoTo,
        });
      } else {
        await onSubmit({
          name: n,
          openPrice: openN,
          KMPrice: kmN,
          timePrice: tN,
          sort_order: 0,
          customer_badge: normBadge(badge),
        });
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" role="presentation" onClick={onClose}>
      <div className="modal" role="dialog" onClick={(ev) => ev.stopPropagation()} dir="rtl">
        <h3>{title}</h3>
        <p className="text-muted small">
          مثال: عادية، مريحة، VIP. الأسعار تُستخدم لتقدير رحلة «طلب التطبيق».
        </p>
        <label>
          اسم الفئة *
          <input value={name} onChange={(e) => setName(e.target.value)} />
        </label>
        <label>
          السعر الافتتاحي (ل.س)
          <input
            value={openPrice}
            onChange={(e) => setOpenPrice(e.target.value)}
            inputMode="decimal"
          />
        </label>
        <label>
          سعر الكيلومتر (ل.س) *
          <input value={km} onChange={(e) => setKm(e.target.value)} inputMode="decimal" />
        </label>
        <label>
          سعر الدقيقة (ل.س) *
          <input value={time} onChange={(e) => setTime(e.target.value)} inputMode="decimal" />
        </label>
        <p className="text-muted small" style={{ marginTop: 12 }}>
          شكل الأيقونة عند الزبون
        </p>
        <div className="row-gap" style={{ flexWrap: 'wrap', marginTop: 8 }}>
          {(
            [
              ['economy', 'عادي'],
              ['suv', 'عائلي'],
              ['premium', 'VIP'],
            ] as const
          ).map(([k, lab]) => (
            <button
              key={k}
              type="button"
              className={badge === k ? 'btn-primary' : 'btn-ghost'}
              onClick={() => setBadge(k)}
            >
              {lab}
            </button>
          ))}
        </div>
        {isEdit ? (
          otherTypes.length > 0 && (
            <>
              <div className="opt-section-title" style={{ marginTop: 16 }}>
                طلب هذه الفئة يصل أيضاً لسائقي
              </div>
              {otherTypes.map((o) => {
                const oid = Number(o.id ?? 0);
                const checked = alsoTo.includes(oid);
                return (
                  <label key={oid} className={`cust-pick-row${checked ? ' checked' : ''}`}>
                    <input
                      type="checkbox"
                      checked={checked}
                      onChange={() =>
                        setAlsoTo((prev) =>
                          prev.includes(oid) ? prev.filter((x) => x !== oid) : [...prev, oid],
                        )
                      }
                    />
                    <span style={{ flex: 1 }}>
                      <strong>{String(o.name ?? '')}</strong>
                    </span>
                  </label>
                );
              })}
              <p className="text-muted small" style={{ marginTop: 6 }}>
                سائقو الفئات المختارة يستلمون طلب «{name.trim() || '…'}» أيضاً، والأجرة تبقى
                بتسعيرة «{name.trim() || '…'}». سائقو هذه الفئة لا يستلمون طلبات الفئات الأخرى
                إلا إذا فعّلت ذلك من تعديل تلك الفئة.
              </p>
            </>
          )
        ) : (
          <p className="text-muted small" style={{ marginTop: 12 }}>
            بعد إضافة الفئة يمكنك من «تعديل» تحديد فئات أخرى يصلها طلب هذه الفئة.
          </p>
        )}
        <div className="row-gap" style={{ marginTop: 16 }}>
          <button type="button" className="btn-ghost" onClick={onClose}>
            إلغاء
          </button>
          <button type="button" className="btn-primary" disabled={busy} onClick={() => void submit()}>
            {busy ? '…' : 'حفظ'}
          </button>
        </div>
      </div>
    </div>
  );
}
