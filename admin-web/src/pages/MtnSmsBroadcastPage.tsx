import { useCallback, useEffect, useMemo, useState } from 'react';
import { API } from '../api/endpoints';
import { fetchJsonAuth, postJson } from '../api/http';
import { formatApiFailure } from '../util/apiError';
import { PageHeader } from '../components/PageHeader';

type BroadcastStatus = {
  id?: string;
  status?: string;
  total?: number;
  sent?: number;
  failed?: number;
  error?: string;
};

type LastBroadcast = {
  message?: string;
  total?: number;
  sent?: number;
  failed?: number;
  finished_at?: string;
};

type BatchStats = {
  total: number;
  already_sent: number;
  remaining: number;
  next_batch: number;
  batch_size: number;
};

type CustomerRow = {
  id: number;
  name: string;
  number: string;
};

const PAGE_SIZE = 50;
const BATCH_SIZE = 50;

type Audience = 'customers' | 'drivers' | 'all';

export function MtnSmsBroadcastPage() {
  const [message, setMessage] = useState('');
  const [onlyVerified, setOnlyVerified] = useState(true);
  const [sendAll, setSendAll] = useState(true);
  const [batchMode, setBatchMode] = useState(true);
  const [audience, setAudience] = useState<Audience>('customers');
  const [recipients, setRecipients] = useState<number | null>(null);
  const [batch, setBatch] = useState<BatchStats | null>(null);
  const [mtnOk, setMtnOk] = useState<boolean | null>(null);
  const [lastBroadcast, setLastBroadcast] = useState<LastBroadcast | null>(null);
  const [loadingCount, setLoadingCount] = useState(false);
  const [sending, setSending] = useState(false);
  const [err, setErr] = useState('');
  const [broadcastId, setBroadcastId] = useState<string | null>(null);
  const [progress, setProgress] = useState<BroadcastStatus | null>(null);
  const [cancelling, setCancelling] = useState(false);

  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [lastPage, setLastPage] = useState(1);
  const [rows, setRows] = useState<CustomerRow[]>([]);
  const [listTotal, setListTotal] = useState(0);
  const [loadingList, setLoadingList] = useState(false);
  const [selected, setSelected] = useState<Record<number, true>>({});

  const selectedIds = useMemo(
    () => Object.keys(selected).map((k) => Number(k)).filter((n) => n > 0),
    [selected],
  );

  const audienceLabel =
    audience === 'drivers' ? 'سائقين' : audience === 'all' ? 'زبائن وسائقين' : 'زبائن';

  const loadCount = useCallback(async () => {
    setLoadingCount(true);
    setErr('');
    try {
      const q = new URLSearchParams({
        only_verified: onlyVerified ? '1' : '0',
        batch_size: String(BATCH_SIZE),
        audience,
      });
      if (!sendAll && selectedIds.length > 0) {
        q.set('customer_ids', selectedIds.join(','));
      }
      const { res, data } = await fetchJsonAuth(
        `${API.adminMtnSmsBroadcastRecipients}?${q}`,
      );
      if (!res.ok || data.success !== true) {
        setErr(formatApiFailure(data, 'تعذر جلب عدد المستلمين'));
        return;
      }
      const d = data.data as Record<string, unknown> | undefined;
      setRecipients(Number(d?.recipients ?? 0));
      setMtnOk(d?.mtn_configured === true);
      if (d?.batch && typeof d.batch === 'object') {
        const b = d.batch as Record<string, unknown>;
        setBatch({
          total: Number(b.total ?? 0),
          already_sent: Number(b.already_sent ?? 0),
          remaining: Number(b.remaining ?? 0),
          next_batch: Number(b.next_batch ?? 0),
          batch_size: Number(b.batch_size ?? BATCH_SIZE),
        });
      }
      if (d?.last_broadcast && typeof d.last_broadcast === 'object') {
        setLastBroadcast(d.last_broadcast as LastBroadcast);
      }
    } catch (e) {
      setErr(String(e));
    } finally {
      setLoadingCount(false);
    }
  }, [onlyVerified, sendAll, selectedIds, audience]);

  useEffect(() => {
    void loadCount();
  }, [loadCount]);

  const loadRecipientsList = useCallback(async () => {
    setLoadingList(true);
    try {
      if (audience === 'drivers') {
        const q = new URLSearchParams();
        q.set('per_page', String(PAGE_SIZE));
        q.set('page', String(page));
        if (search.trim()) q.set('search', search.trim());
        const { res, data: j } = await fetchJsonAuth(`${API.driversIndex}?${q}`);
        if (!res.ok || j.success !== true) {
          throw new Error(String(j.message ?? res.statusText));
        }
        const payload = (j.data as Record<string, unknown>) ?? {};
        const inner = Array.isArray(j.data)
          ? (j.data as unknown[])
          : ((payload.data as unknown[]) ?? []);
        setRows(
          inner.map((e) => {
            const r = e as Record<string, unknown>;
            const u = (r.user as Record<string, unknown> | undefined) ?? r;
            const first = String(u.firstName ?? u.first_name ?? '');
            const last = String(u.lastName ?? u.last_name ?? '');
            const userId = Number(u.id ?? r.userId ?? r.user_id ?? 0);
            return {
              id: userId > 0 ? userId : Number(r.id),
              name: `${first} ${last}`.trim() || `سائق #${r.id}`,
              number: String(u.number ?? r.number ?? ''),
            };
          }),
        );
        setLastPage(Number(payload.last_page ?? 1));
        setListTotal(Number(payload.total ?? inner.length));
      } else {
        const q = new URLSearchParams();
        q.set('per_page', String(PAGE_SIZE));
        q.set('page', String(page));
        if (search.trim()) q.set('search', search.trim());
        const { res, data: j } = await fetchJsonAuth(`${API.adminCustomers}?${q}`);
        if (!res.ok || j.success !== true) {
          throw new Error(String(j.message ?? res.statusText));
        }
        const payload = (j.data as Record<string, unknown>) ?? {};
        const inner = (payload.data as unknown[]) ?? [];
        setRows(
          inner.map((e) => {
            const r = e as Record<string, unknown>;
            const first = String(r.firstName ?? r.first_name ?? '');
            const last = String(r.lastName ?? r.last_name ?? '');
            return {
              id: Number(r.id),
              name: `${first} ${last}`.trim() || '—',
              number: String(r.number ?? ''),
            };
          }),
        );
        setLastPage(Number(payload.last_page ?? 1));
        setListTotal(Number(payload.total ?? inner.length));
      }
    } catch (e) {
      setErr(String(e));
    } finally {
      setLoadingList(false);
    }
  }, [page, search, audience]);

  useEffect(() => {
    if (!sendAll && audience !== 'all') void loadRecipientsList();
  }, [sendAll, loadRecipientsList, audience]);

  useEffect(() => {
    setSelected({});
    setPage(1);
  }, [audience]);

  useEffect(() => {
    if (!broadcastId) return;
    let stopped = false;
    const tick = async () => {
      try {
        const { res, data } = await fetchJsonAuth(
          API.adminMtnSmsBroadcastStatus(broadcastId),
        );
        if (stopped) return;
        if (res.ok && data.success === true && data.data) {
          const st = data.data as BroadcastStatus;
          setProgress(st);
          if (
            st.status === 'finished' ||
            st.status === 'failed' ||
            st.status === 'cancelled'
          ) {
            setSending(false);
            setCancelling(false);
            void loadCount();
            return;
          }
        }
      } catch {
        /* ignore */
      }
      if (!stopped) window.setTimeout(() => void tick(), 2000);
    };
    void tick();
    return () => {
      stopped = true;
    };
  }, [broadcastId, loadCount]);

  async function send() {
    if (!message.trim()) {
      alert('أدخل نص الرسالة');
      return;
    }
    if (!sendAll && selectedIds.length === 0) {
      alert('اختر مستلمين أو فعّل الإرسال للجميع');
      return;
    }
    const target = batchMode
      ? batch?.next_batch ?? 0
      : sendAll
        ? recipients ?? 0
        : selectedIds.length;
    if (
      !window.confirm(
        batchMode
          ? `إرسال SMS للدفعة التالية (${target} رقم — ${audienceLabel}) عبر MTN؟`
          : `إرسال SMS إلى ${target} رقم (${audienceLabel}) عبر MTN؟`,
      )
    ) {
      return;
    }
    setSending(true);
    setErr('');
    setProgress(null);
    try {
      const body: Record<string, unknown> = {
        message: message.trim(),
        only_verified: onlyVerified,
        send_all: sendAll,
        batch_mode: batchMode,
        batch_size: BATCH_SIZE,
        audience,
      };
      if (!sendAll) body.customer_ids = selectedIds;
      const { res, data } = await postJson<Record<string, unknown>>(
        API.adminMtnSmsBroadcast,
        body,
      );
      if (!res.ok || data.success !== true) {
        setSending(false);
        setErr(formatApiFailure(data, 'تعذر الإرسال'));
        return;
      }
      const d = data.data as Record<string, unknown> | undefined;
      setBroadcastId(String(d?.id ?? ''));
    } catch (e) {
      setSending(false);
      setErr(String(e));
    }
  }

  async function cancelSend() {
    if (!broadcastId) return;
    if (!window.confirm('إيقاف الإرسال؟')) return;
    setCancelling(true);
    try {
      await postJson(API.adminMtnSmsBroadcastCancel(broadcastId), {});
    } catch {
      setCancelling(false);
    }
  }

  async function resetBatch() {
    if (!window.confirm('مسح سجل المستلمين السابقين والبدء من جديد؟')) return;
    try {
      const { res, data } = await postJson<Record<string, unknown>>(
        API.adminMtnSmsBroadcastResetBatch,
        {
          only_verified: onlyVerified,
          audience,
          customer_ids: sendAll ? undefined : selectedIds,
        },
      );
      if (!res.ok || data.success !== true) {
        alert(formatApiFailure(data, 'تعذر إعادة التعيين'));
        return;
      }
      void loadCount();
    } catch (e) {
      alert(String(e));
    }
  }

  return (
    <div className="page">
      <PageHeader title="إرسال رسائل MTN SMS" />
      <p className="muted">
        نفس بوابة MTN المستخدمة لرمز التحقق. نص فقط (بدون مرفقات). يمكن الإرسال للزبائن أو السائقين أو الاثنين.
      </p>
      {mtnOk === false && (
        <div className="err-box">
          بوابة MTN غير مُعدّة على السيرفر (MTN_SMS_USER / PASS / FROM).
        </div>
      )}
      {err && <div className="err-box">{err}</div>}

      <label className="field-label">نص الرسالة</label>
      <textarea
        className="input"
        rows={5}
        maxLength={700}
        value={message}
        onChange={(e) => setMessage(e.target.value)}
        placeholder="مثال: عرض خاص من GS Taxi…"
      />
      <div className="muted" style={{ marginBottom: 12 }}>
        {message.length}/700
      </div>

      <label className="field-label">المستهدفون</label>
      <div className="row-gap" style={{ marginBottom: 12, flexWrap: 'wrap' }}>
        {(
          [
            ['customers', 'الزبائن'],
            ['drivers', 'السائقون'],
            ['all', 'الكل (زبائن + سائقون)'],
          ] as const
        ).map(([value, label]) => (
          <label key={value} className="check-row">
            <input
              type="radio"
              name="mtn-audience"
              checked={audience === value}
              onChange={() => setAudience(value)}
            />
            {label}
          </label>
        ))}
      </div>

      <label className="check-row">
        <input
          type="checkbox"
          checked={onlyVerified}
          onChange={(e) => setOnlyVerified(e.target.checked)}
        />
        أرقام موثّقة فقط
      </label>
      <label className="check-row">
        <input
          type="checkbox"
          checked={sendAll}
          onChange={(e) => setSendAll(e.target.checked)}
        />
        إرسال للجميع ضمن المستهدفين (وليس محددين فقط)
      </label>
      <label className="check-row">
        <input
          type="checkbox"
          checked={batchMode}
          onChange={(e) => setBatchMode(e.target.checked)}
        />
        وضع الدفعات ({BATCH_SIZE} لكل دفعة)
      </label>

      <div style={{ margin: '12px 0' }}>
        <button type="button" className="btn" onClick={() => void loadCount()} disabled={loadingCount}>
          {loadingCount ? '…' : 'تحديث العدد'}
        </button>{' '}
        <button type="button" className="btn secondary" onClick={() => void resetBatch()}>
          إعادة تعيين الدفعات
        </button>
      </div>

      <p>
        المستلمون ({audienceLabel}): <strong>{recipients ?? '—'}</strong>
        {batch && (
          <>
            {' '}
            — متبقّي: {batch.remaining} — الدفعة التالية: {batch.next_batch}
          </>
        )}
      </p>

      {!sendAll && audience !== 'all' && (
        <div className="card" style={{ marginTop: 12 }}>
          <h3>اختيار {audience === 'drivers' ? 'سائقين' : 'زبائن'}</h3>
          <div className="row-gap">
            <input
              className="input"
              placeholder="بحث بالاسم أو الرقم"
              value={search}
              onChange={(e) => {
                setPage(1);
                setSearch(e.target.value);
              }}
            />
            <button type="button" className="btn secondary" onClick={() => void loadRecipientsList()}>
              بحث
            </button>
          </div>
          {loadingList ? (
            <p>جاري التحميل…</p>
          ) : (
            <ul className="plain-list">
              {rows.map((r) => (
                <li key={r.id}>
                  <label className="check-row">
                    <input
                      type="checkbox"
                      checked={!!selected[r.id]}
                      onChange={() =>
                        setSelected((prev) => {
                          const next = { ...prev };
                          if (next[r.id]) delete next[r.id];
                          else next[r.id] = true;
                          return next;
                        })
                      }
                    />
                    {r.name} — {r.number}
                  </label>
                </li>
              ))}
            </ul>
          )}
          <div className="row-gap">
            <button type="button" className="btn secondary" onClick={() => setPage((p) => Math.max(1, p - 1))}>
              السابق
            </button>
            <span>
              {page}/{lastPage} ({listTotal})
            </span>
            <button
              type="button"
              className="btn secondary"
              onClick={() => setPage((p) => Math.min(lastPage, p + 1))}
            >
              التالي
            </button>
            <span>محدد: {selectedIds.length}</span>
          </div>
        </div>
      )}

      {!sendAll && audience === 'all' && (
        <p className="muted">للتحديد اليدوي اختر «الزبائن» أو «السائقون» فقط.</p>
      )}

      <div style={{ marginTop: 16 }}>
        <button
          type="button"
          className="btn primary"
          disabled={sending || mtnOk === false}
          onClick={() => void send()}
        >
          {sending ? 'جاري الإرسال…' : 'إرسال عبر MTN'}
        </button>{' '}
        {sending && (
          <button type="button" className="btn danger" disabled={cancelling} onClick={() => void cancelSend()}>
            إيقاف
          </button>
        )}
      </div>

      {progress && (
        <div className="card" style={{ marginTop: 12 }}>
          <div>الحالة: {progress.status}</div>
          <div>
            أُرسل: {progress.sent ?? 0} / {progress.total ?? 0} — فشل:{' '}
            {progress.failed ?? 0}
          </div>
          {progress.error && <div className="err-box">{progress.error}</div>}
        </div>
      )}

      {lastBroadcast && (
        <div className="card" style={{ marginTop: 12 }}>
          <h3>آخر إرسال</h3>
          <p>{lastBroadcast.message}</p>
          <p className="muted">
            أُرسل {lastBroadcast.sent}/{lastBroadcast.total} — فشل{' '}
            {lastBroadcast.failed} — {lastBroadcast.finished_at}
          </p>
        </div>
      )}
    </div>
  );
}
