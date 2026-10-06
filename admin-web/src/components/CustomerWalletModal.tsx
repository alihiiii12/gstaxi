import { useCallback, useEffect, useState } from 'react';
import { API } from '../api/endpoints';
import { fetchJsonAuth, postJson } from '../api/http';
import { formatApiFailure } from '../util/apiError';
import { ModalPortal } from './ModalPortal';

type Props = {
  customerId: number;
  customerName: string;
  onClose: () => void;
};

type Kind = 'topup' | 'deduct' | 'adjust';

function asRecord(v: unknown): Record<string, unknown> | null {
  if (v && typeof v === 'object' && !Array.isArray(v)) return v as Record<string, unknown>;
  return null;
}

export function CustomerWalletModal({ customerId, customerName, onClose }: Props) {
  const [balance, setBalance] = useState(0);
  const [currency, setCurrency] = useState('SYP');
  const [txs, setTxs] = useState<Record<string, unknown>[]>([]);
  const [canManage, setCanManage] = useState(false);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setErr('');
    try {
      const { res, data: j } = await fetchJsonAuth(API.customerWallet(customerId));
      if (!res.ok || j.success !== true) {
        throw new Error(String(j.message ?? res.statusText));
      }
      const data = asRecord(j.data) ?? {};
      const wallet = asRecord(data.wallet) ?? {};
      setBalance(Number(wallet.balance ?? 0));
      setCurrency(String(wallet.currency ?? 'SYP'));
      setCanManage(data.can_manage === true);
      const list = Array.isArray(data.transactions) ? data.transactions : [];
      setTxs(list.map((e) => asRecord(e)).filter((e): e is Record<string, unknown> => e != null));
    } catch (e) {
      setErr(String(e));
    } finally {
      setLoading(false);
    }
  }, [customerId]);

  useEffect(() => {
    void load();
  }, [load]);

  const cur = currency === 'SYP' ? 'ل.س' : currency;

  async function submit(kind: Kind) {
    const value = Number(amount);
    if (!Number.isFinite(value) || value < 0 || (kind !== 'adjust' && value <= 0)) {
      alert(kind === 'adjust' ? 'أدخل الرصيد الصحيح (صفر أو أكثر)' : 'أدخل مبلغاً موجباً');
      return;
    }
    const confirmMsg =
      kind === 'topup'
        ? `تعبئة ${value.toLocaleString('ar-SY')} ${cur} في محفظة «${customerName}»؟`
        : kind === 'deduct'
          ? `خصم ${value.toLocaleString('ar-SY')} ${cur} من محفظة «${customerName}»؟`
          : `ضبط رصيد «${customerName}» ليصبح ${value.toLocaleString('ar-SY')} ${cur}؟`;
    if (!window.confirm(confirmMsg)) return;

    setBusy(true);
    try {
      const url =
        kind === 'topup'
          ? API.customerWalletTopup(customerId)
          : kind === 'deduct'
            ? API.customerWalletDeduct(customerId)
            : API.customerWalletAdjust(customerId);
      const { res, data } = await postJson<Record<string, unknown>>(url, {
        amount: value,
        note: note.trim() || undefined,
      });
      if (res.ok && data.success === true) {
        alert(String(data.message ?? 'تم'));
        setAmount('');
        setNote('');
        void load();
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } catch (e) {
      alert(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <ModalPortal onClose={onClose}>
      <div
        className="modal"
        role="dialog"
        onClick={(e) => e.stopPropagation()}
        dir="rtl"
        style={{ maxWidth: 760, width: '95vw' }}
      >
        <div className="row-between" style={{ alignItems: 'center' }}>
          <h3 style={{ margin: 0 }}>محفظة {customerName}</h3>
          <button type="button" className="btn-ghost" onClick={onClose}>
            إغلاق
          </button>
        </div>

        <div className="row-between wrap" style={{ gap: 12, alignItems: 'center', marginTop: 12 }}>
          <p style={{ margin: 0, fontSize: 20, fontWeight: 700 }}>
            الرصيد:{' '}
            <span style={{ color: 'var(--accent, #0ea5e9)' }}>
              {balance.toLocaleString('ar-SY')} {cur}
            </span>
          </p>
          <button type="button" className="btn-ghost" disabled={loading || busy} onClick={() => void load()}>
            تحديث
          </button>
        </div>
        {loading && <p className="text-muted">جاري تحميل المحفظة…</p>}
        {err && <p className="text-err">{err}</p>}

        {canManage ? (
          <>
            <p className="text-muted" style={{ margin: '8px 0', fontSize: 13 }}>
              التعبئة تضيف رصيداً · الخصم ينقص الرصيد · التصحيح يضبط الرصيد على القيمة المدخلة.
            </p>
            <div className="row-between wrap" style={{ gap: 12 }}>
              <label style={{ flex: 1, minWidth: 140 }}>
                المبلغ
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  placeholder="0"
                  disabled={busy}
                />
              </label>
              <label style={{ flex: 2, minWidth: 180 }}>
                ملاحظة (اختياري)
                <input
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="سبب التعبئة / الخصم / التصحيح"
                  disabled={busy}
                />
              </label>
            </div>
            <div className="row-gap" style={{ gap: 8, flexWrap: 'wrap', marginTop: 8 }}>
              <button type="button" className="btn-primary" disabled={busy} onClick={() => void submit('topup')}>
                تعبئة الرصيد
              </button>
              <button
                type="button"
                className="btn-warn"
                disabled={busy || balance <= 0}
                onClick={() => void submit('deduct')}
              >
                خصم
              </button>
              <button type="button" className="btn-ghost" disabled={busy} onClick={() => void submit('adjust')}>
                تصحيح الرصيد
              </button>
            </div>
          </>
        ) : (
          <p className="text-muted" style={{ fontSize: 13 }}>
            لا تملك صلاحية تعديل محافظ الزبائن.
          </p>
        )}

        <h4 className="mt">سجل الحركات</h4>
        {txs.length > 0 ? (
          <div style={{ overflowX: 'auto', maxHeight: '40vh', overflowY: 'auto' }}>
            <table className="data-table" style={{ width: '100%', fontSize: 13 }}>
              <thead>
                <tr>
                  <th>النوع</th>
                  <th>المبلغ</th>
                  <th>بعد العملية</th>
                  <th>رحلة</th>
                  <th>السائق</th>
                  <th>ملاحظة</th>
                  <th>التاريخ</th>
                </tr>
              </thead>
              <tbody>
                {txs.map((tx) => {
                  const amt = Number(tx.amount ?? 0);
                  return (
                    <tr key={String(tx.id)}>
                      <td>{String(tx.type_label ?? tx.type ?? '')}</td>
                      <td style={{ color: amt < 0 ? '#b91c1c' : '#15803d', fontWeight: 600 }}>
                        {amt > 0 ? '+' : ''}
                        {amt.toLocaleString('ar-SY')}
                      </td>
                      <td>{Number(tx.balance_after ?? 0).toLocaleString('ar-SY')}</td>
                      <td>{tx.request_id ? `#${String(tx.request_id)}` : '—'}</td>
                      <td>{String(tx.driver_name ?? '—')}</td>
                      <td>{String(tx.note ?? '—')}</td>
                      <td>
                        {tx.created_at ? new Date(String(tx.created_at)).toLocaleString('ar-SY') : '—'}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          !loading && !err && <p className="text-muted">لا حركات بعد</p>
        )}
      </div>
    </ModalPortal>
  );
}
