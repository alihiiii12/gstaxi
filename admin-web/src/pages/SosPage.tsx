import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { API } from '../api/endpoints';
import { deleteJson, fetchJsonAuth, postJson } from '../api/http';
import { ModalPortal } from '../components/ModalPortal';
import { PageHeader } from '../components/PageHeader';
import { formatApiFailure } from '../util/apiError';

function sosRedisKey(s: Record<string, unknown>): string {
  const raw = String(s.redisKey ?? s.redis_key ?? '').trim();
  if (raw) return raw;
  const role = String(s.role ?? 'driver').toLowerCase();
  if (role === 'customer') {
    const uid = parseInt(String(s.customerId ?? s.customer_id ?? s.userId ?? s.user_id ?? 0), 10);
    return uid > 0 ? `c:${uid}` : '';
  }
  const did = parseInt(String(s.driverId ?? s.driver_id ?? 0), 10);
  return did > 0 ? String(did) : '';
}

function isCustomerSos(s: Record<string, unknown>): boolean {
  return String(s.role ?? '').toLowerCase() === 'customer' || sosRedisKey(s).startsWith('c:');
}

export function SosPage() {
  const [rows, setRows] = useState<Record<string, unknown>[]>([]);
  const [loading, setLoading] = useState(true);
  const [fineModal, setFineModal] = useState<{
    id: number;
    name: string;
  } | null>(null);
  const [fineAmount, setFineAmount] = useState('');
  const [fineNote, setFineNote] = useState('مخالفة SOS');
  const [fineBusy, setFineBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data: j } = await fetchJsonAuth(API.emergencyActive);
      if (j.state !== true && j.success !== true) {
        setRows([]);
        return;
      }
      const list = (j.data as unknown[]) ?? [];
      setRows(list.map((e) => e as Record<string, unknown>));
    } catch {
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function clear(key: string) {
    if (!key) return;
    const label = key.startsWith('c:') ? 'لهذا الراكب' : 'لهذا السائق';
    if (!confirm(`إنهاء تنبيه SOS ${label}؟`)) return;
    await deleteJson(API.clearSos(key));
    await load();
  }

  async function submitViolation() {
    if (!fineModal) return;
    const amount = Number(fineAmount);
    if (!Number.isFinite(amount) || amount <= 0) {
      alert('أدخل مبلغ مخالفة موجباً');
      return;
    }
    if (
      !window.confirm(
        `خصم ${amount} ل.س كمخالفة من محفظة «${fineModal.name}»؟`,
      )
    ) {
      return;
    }
    setFineBusy(true);
    try {
      const { res, data } = await postJson<Record<string, unknown>>(
        API.driverWalletViolation(fineModal.id),
        {
          amount,
          note: fineNote.trim() || 'مخالفة SOS',
        },
      );
      if (res.ok && data.success === true) {
        alert(String(data.message ?? 'تم خصم المخالفة'));
        setFineModal(null);
        setFineAmount('');
        setFineNote('مخالفة SOS');
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } catch (e) {
      alert(String(e));
    } finally {
      setFineBusy(false);
    }
  }

  if (loading) {
    return (
      <div className="page-center">
        <div className="spinner" />
      </div>
    );
  }

  return (
    <div className="page-pad">
      <PageHeader
        title="تنبيهات SOS"
        subtitle="بلاغات الطوارئ النشطة من تطبيق السائق والراكب."
        onRefresh={() => void load()}
        refreshing={loading}
        actions={
          <Link to="/map" className="btn-primary" style={{ textDecoration: 'none' }}>
            خريطة العمليات
          </Link>
        }
      />
      {!rows.length ? (
        <div className="card">
          <p className="text-muted" style={{ margin: 0 }}>
            لا توجد تنبيهات SOS حالياً.
          </p>
        </div>
      ) : (
        <div className="card-list">
          {rows.map((s, i) => {
            const key = sosRedisKey(s);
            const customer = isCustomerSos(s);
            const did = parseInt(String(s.driverId ?? s.driver_id ?? 0), 10);
            const uid = parseInt(
              String(s.customerId ?? s.customer_id ?? s.userId ?? s.user_id ?? 0),
              10,
            );
            const name = String(
              s.name ?? (customer ? `راكب #${uid || '?'}` : `سائق #${did || '?'}`),
            );
            const mapHref = customer
              ? `/map?sosKey=${encodeURIComponent(key)}`
              : `/map?sosDriver=${did}`;
            return (
              <div key={key || i} className="card card-warn">
                <div className="row-between">
                  <div>
                    <div className="card-title">
                      <span className="coupon-badge" data-kind={customer ? 'aud' : 'fixed'}>
                        {customer ? 'راكب' : 'سائق'}
                      </span>{' '}
                      {name} — {String(s.number ?? '')}
                    </div>
                    <pre className="card-sub">
                      lat {String(s.latitude)} , lng {String(s.longitude)}
                      {'\n'}
                      {String(s.at ?? '')}
                    </pre>
                  </div>
                  {key && (
                    <div className="row-gap" style={{ flexWrap: 'wrap', gap: 8 }}>
                      <Link
                        to={mapHref}
                        className="btn-primary"
                        style={{ textDecoration: 'none', display: 'inline-block' }}
                      >
                        عرض على الخريطة
                      </Link>
                      {!customer && did > 0 && (
                        <button
                          type="button"
                          className="btn-warn"
                          onClick={() => {
                            setFineAmount('');
                            setFineNote('مخالفة SOS');
                            setFineModal({ id: did, name });
                          }}
                        >
                          مخالفة
                        </button>
                      )}
                      <button type="button" className="btn-ghost" onClick={() => void clear(key)}>
                        إنهاء التنبيه
                      </button>
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {fineModal && (
        <ModalPortal onClose={() => !fineBusy && setFineModal(null)}>
          <div
            className="modal"
            role="dialog"
            onClick={(ev) => ev.stopPropagation()}
            dir="rtl"
          >
            <h3>مخالفة — {fineModal.name}</h3>
            <p className="text-muted" style={{ marginTop: 0 }}>
              يُخصم المبلغ من محفظة السائق فوراً ويظهر في التطبيق.
            </p>
            <label>
              المبلغ (ل.س)
              <input
                type="number"
                min="0"
                step="0.01"
                value={fineAmount}
                onChange={(e) => setFineAmount(e.target.value)}
                disabled={fineBusy}
                placeholder="مثال: 5000"
              />
            </label>
            <label>
              ملاحظة
              <input
                value={fineNote}
                onChange={(e) => setFineNote(e.target.value)}
                disabled={fineBusy}
              />
            </label>
            <div className="row-gap" style={{ marginTop: 12 }}>
              <button
                type="button"
                className="btn-ghost"
                disabled={fineBusy}
                onClick={() => setFineModal(null)}
              >
                إلغاء
              </button>
              <button
                type="button"
                className="btn-warn"
                disabled={fineBusy}
                onClick={() => void submitViolation()}
              >
                خصم المخالفة
              </button>
            </div>
          </div>
        </ModalPortal>
      )}
    </div>
  );
}
