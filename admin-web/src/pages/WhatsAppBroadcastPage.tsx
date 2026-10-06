import { useCallback, useEffect, useMemo, useState } from 'react';
import { API } from '../api/endpoints';
import { fetchJsonAuth, putJson, postJson } from '../api/http';
import { formatApiFailure } from '../util/apiError';

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
  has_media?: boolean;
  media_url?: string | null;
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
/** ملفات أكبر من هذا يُفضَّل رفعها كرابط (تجنّب 413 nginx). */
const MAX_UPLOAD_MB = 20;

export function WhatsAppBroadcastPage() {
  const [message, setMessage] = useState('');
  const [onlyVerified, setOnlyVerified] = useState(true);
  const [sendAll, setSendAll] = useState(true);
  const [batchMode, setBatchMode] = useState(true);
  const [file, setFile] = useState<File | null>(null);
  const [mediaUrl, setMediaUrl] = useState('');
  const [recipients, setRecipients] = useState<number | null>(null);
  const [batch, setBatch] = useState<BatchStats | null>(null);
  const [ultramsgOk, setUltramsgOk] = useState<boolean | null>(null);
  const [lastBroadcast, setLastBroadcast] = useState<LastBroadcast | null>(null);
  const [loadingCount, setLoadingCount] = useState(false);
  const [sending, setSending] = useState(false);
  const [err, setErr] = useState('');
  const [broadcastId, setBroadcastId] = useState<string | null>(null);
  const [progress, setProgress] = useState<BroadcastStatus | null>(null);

  const [minBuild, setMinBuild] = useState('6');
  const [downloadUrl, setDownloadUrl] = useState(
    'https://gstaxi.online/downloads/gstaxi.apk',
  );
  const [updateMessage, setUpdateMessage] = useState(
    'نسخة التطبيق قديمة. حدّث التطبيق لمتابعة استخدام GS Taxi.',
  );
  const [blockOld, setBlockOld] = useState(false);
  const [savingUpdate, setSavingUpdate] = useState(false);
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
  const selectedCount = selectedIds.length;

  const loadCount = useCallback(async () => {
    setLoadingCount(true);
    setErr('');
    try {
      const q = new URLSearchParams({
        only_verified: onlyVerified ? '1' : '0',
        batch_size: String(BATCH_SIZE),
      });
      if (!sendAll && selectedIds.length > 0) {
        q.set('customer_ids', selectedIds.join(','));
      }
      const { res, data } = await fetchJsonAuth(
        `${API.adminWhatsAppBroadcastRecipients}?${q}`,
      );
      if (!res.ok || data.success !== true) {
        setErr(formatApiFailure(data, 'تعذر جلب عدد الزبائن'));
        return;
      }
      const d = data.data as Record<string, unknown> | undefined;
      setRecipients(Number(d?.recipients ?? 0));
      setUltramsgOk(d?.ultramsg_configured === true);
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
  }, [onlyVerified, sendAll, selectedIds]);

  const loadUpdateSettings = useCallback(async () => {
    try {
      const { res, data } = await fetchJsonAuth(API.adminAppUpdateSettings);
      if (!res.ok || data.success !== true) return;
      const d = data.data as Record<string, unknown> | undefined;
      if (!d) return;
      setMinBuild(String(d.min_build ?? '6'));
      setDownloadUrl(String(d.download_url ?? ''));
      setUpdateMessage(String(d.message ?? ''));
      setBlockOld(d.block_old_login !== false);
    } catch {
      /* ignore */
    }
  }, []);

  useEffect(() => {
    void loadCount();
  }, [loadCount]);

  useEffect(() => {
    void loadUpdateSettings();
  }, [loadUpdateSettings]);

  const loadCustomers = useCallback(async () => {
    setLoadingList(true);
    try {
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
    } catch (e) {
      setErr(String(e));
    } finally {
      setLoadingList(false);
    }
  }, [page, search]);

  useEffect(() => {
    if (!sendAll) void loadCustomers();
  }, [sendAll, loadCustomers]);

  useEffect(() => {
    if (!broadcastId) return;
    let stopped = false;
    const tick = async () => {
      try {
        const { res, data } = await fetchJsonAuth(
          API.adminWhatsAppBroadcastStatus(broadcastId),
        );
        if (stopped) return;
        if (res.ok && data.success === true && data.data) {
          const st = data.data as BroadcastStatus;
          setProgress(st);
          if (st.status === 'done' || st.status === 'failed' || st.status === 'cancelled') {
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
  }, [broadcastId]);

  function toggleOne(id: number) {
    setSelected((prev) => {
      const next = { ...prev };
      if (next[id]) delete next[id];
      else next[id] = true;
      return next;
    });
  }

  function selectPageAll() {
    setSelected((prev) => {
      const next = { ...prev };
      for (const r of rows) next[r.id] = true;
      return next;
    });
  }

  function clearSelection() {
    setSelected({});
  }

  async function cancelSend() {
    if (!broadcastId) return;
    if (!window.confirm('إيقاف الإرسال الآن؟ لن تُرسل الرسائل المتبقية.')) return;
    setCancelling(true);
    try {
      const { res, data } = await postJson<Record<string, unknown>>(
        API.adminWhatsAppBroadcastCancel(broadcastId),
        {},
      );
      if (!res.ok || data.success !== true) {
        setCancelling(false);
        alert(formatApiFailure(data, 'تعذر الإلغاء'));
        return;
      }
      setProgress((p) =>
        p
          ? { ...p, status: 'cancelling' }
          : { status: 'cancelling', sent: 0, failed: 0, total: 0 },
      );
    } catch (e) {
      setCancelling(false);
      alert(String(e));
    }
  }

  async function saveUpdateSettings() {
    const mb = Number(minBuild);
    if (!Number.isFinite(mb) || mb < 1) {
      alert('أدخل رقم إصدار أدنى صحيح (build number)');
      return;
    }
    if (!downloadUrl.trim()) {
      alert('أدخل رابط تحميل التطبيق');
      return;
    }
    setSavingUpdate(true);
    try {
      const { res, data } = await putJson<Record<string, unknown>>(
        API.adminAppUpdateSettings,
        {
          min_build: mb,
          download_url: downloadUrl.trim(),
          message: updateMessage.trim(),
          block_old_login: blockOld,
        },
      );
      if (res.ok && data.success === true) {
        alert(String(data.message ?? 'تم الحفظ'));
        await loadUpdateSettings();
      } else {
        alert(formatApiFailure(data, 'تعذر الحفظ'));
      }
    } catch (e) {
      alert(String(e));
    } finally {
      setSavingUpdate(false);
    }
  }

  function onPickFile(f: File | null) {
    setFile(f);
    if (f && f.size > MAX_UPLOAD_MB * 1024 * 1024) {
      setErr(
        `الملف كبير (${Math.round(f.size / 1024 / 1024)} م.ب). ارفعه على السيرفر أو أي استضافة ثم الصق رابط التحميل أدناه — رفع الملفات الضخمة عبر النموذج يرفضه nginx (413).`,
      );
      setFile(null);
    }
  }

  async function resetBatch() {
    if (
      !window.confirm(
        'مسح سجل من أُرسل لهم سابقاً؟ بعدها يمكن إرسال الدفعة الأولى من جديد لجميع المستلمين.',
      )
    ) {
      return;
    }
    try {
      const body: Record<string, unknown> = {
        only_verified: onlyVerified,
      };
      if (!sendAll && selectedIds.length > 0) {
        body.customer_ids = selectedIds;
      }
      const { res, data } = await postJson<Record<string, unknown>>(
        API.adminWhatsAppBroadcastResetBatch,
        body,
      );
      if (!res.ok || data.success !== true) {
        alert(formatApiFailure(data, 'تعذر إعادة التعيين'));
        return;
      }
      const d = data.data as Record<string, unknown> | undefined;
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
      void loadCount();
    } catch (e) {
      alert(String(e));
    }
  }

  async function send() {
    const text = message.trim();
    const url = mediaUrl.trim();
    if (!text && !file && !url) {
      alert('أدخل نصاً أو ملفاً صغيراً أو رابط تحميل عام');
      return;
    }
    if (!sendAll && selectedCount < 1) {
      alert('حدّد مشتركين أو اختر إرسال للجميع');
      return;
    }
    const nextN = batchMode
      ? (batch?.next_batch ?? 0)
      : sendAll
        ? (recipients ?? 0)
        : selectedCount;
    if (nextN < 1) {
      alert(
        batchMode
          ? 'لا متبقّين لهذه الدفعة. اضغط «إعادة التعيين» أو انتهى الجميع.'
          : 'لا يوجد زبائن للإرسال',
      );
      return;
    }
    if (
      !window.confirm(
        batchMode
          ? `إرسال دفعة من ${nextN} مستلم فقط (لن يُعاد الإرسال لمن أُرسل لهم سابقاً).\nهل تريد المتابعة؟`
          : `سيتم إرسال الإعلان عبر واتساب إلى حوالي ${nextN} مستلم.\nهل تريد المتابعة؟`,
      )
    ) {
      return;
    }

    setSending(true);
    setErr('');
    setProgress(null);
    setBroadcastId(null);

    try {
      const form = new FormData();
      if (text) form.append('message', text);
      form.append('only_verified', onlyVerified ? '1' : '0');
      form.append('send_all', sendAll ? '1' : '0');
      form.append('batch_mode', batchMode ? '1' : '0');
      form.append('batch_size', String(BATCH_SIZE));
      if (!sendAll) {
        for (const id of selectedIds) form.append('customer_ids[]', String(id));
      }
      if (file) form.append('media', file);
      if (url) {
        form.append('media_url', url);
        form.append(
          'media_type',
          /\.(jpe?g|png|webp|gif)(\?|$)/i.test(url) ? 'image' : 'document',
        );
        const name = url.split('/').pop()?.split('?')[0] || 'file.apk';
        form.append('media_filename', name);
      }

      const token = localStorage.getItem('token') ?? '';
      const res = await fetch(API.adminWhatsAppBroadcast, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          'Accept-Language': 'ar',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          'X-Client': 'web-admin',
        },
        body: form,
      });
      const textBody = await res.text();

      if (res.status === 413 || /413|Request Entity Too Large/i.test(textBody)) {
        setSending(false);
        setErr(
          'الملف أكبر من حد السيرفر (413). ارفع الـ APK عبر FTP/scp إلى public ثم ضع رابطه هنا، أو زد client_max_body_size في nginx إلى 100m.',
        );
        return;
      }

      let data: Record<string, unknown>;
      try {
        data = JSON.parse(textBody) as Record<string, unknown>;
      } catch {
        throw new Error(textBody.slice(0, 220) || `خطأ ${res.status}`);
      }

      if (!res.ok || data.success !== true) {
        setSending(false);
        setErr(formatApiFailure(data, 'تعذر بدء الإرسال'));
        return;
      }

      const d = data.data as Record<string, unknown> | undefined;
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
      const id = String(d?.broadcast_id ?? '');
      if (id) {
        setBroadcastId(id);
        setProgress({
          status: 'queued',
          total: Number(d?.recipients ?? nextN),
          sent: 0,
          failed: 0,
        });
      } else {
        setSending(false);
        alert(String(data.message ?? 'تم'));
      }
    } catch (e) {
      setSending(false);
      setErr(String(e));
    }
  }

  const pct =
    progress && progress.total && progress.total > 0
      ? Math.round(
          (((progress.sent ?? 0) + (progress.failed ?? 0)) / progress.total) *
            100,
        )
      : 0;

  const displayRecipients = sendAll
    ? recipients
    : selectedCount;

  const sendBtnLabel = sending
    ? 'جاري الإرسال…'
    : batchMode
      ? `إرسال الدفعة التالية (${batch?.next_batch ?? BATCH_SIZE})`
      : 'إرسال عبر واتساب (الكل)';

  return (
    <div className="page-pad">
      <h2 style={{ marginTop: 0 }}>إعلانات واتساب للزبائن</h2>
      <p className="muted" style={{ marginBottom: 16 }}>
        نص و/أو صورة/ملف عبر UltraMsg. للملفات الكبيرة (مثل APK) استخدم رابط
        تحميل عام وليس الرفع المباشر.
      </p>

      {ultramsgOk === false && (
        <p className="text-err">
          UltraMsg غير مُعدّ — تحقق من ULTRAMSG_INSTANCE_ID و ULTRAMSG_TOKEN.
        </p>
      )}
      {err && <p className="text-err">{err}</p>}

      {lastBroadcast && (
        <div
          className="card"
          style={{
            maxWidth: 720,
            padding: 14,
            marginBottom: 14,
            background: '#f8fafc',
          }}
        >
          <div style={{ fontWeight: 800, marginBottom: 8 }}>آخر إعلان واتساب</div>
          <p style={{ margin: '0 0 8px', whiteSpace: 'pre-wrap' }}>
            {lastBroadcast.message?.trim()
              ? lastBroadcast.message
              : '(بدون نص — مرفق فقط)'}
          </p>
          <p className="muted" style={{ margin: 0, fontSize: 13 }}>
            وصل بنجاح: {(lastBroadcast.sent ?? 0).toLocaleString('ar-SY')} · فشل:{' '}
            {(lastBroadcast.failed ?? 0).toLocaleString('ar-SY')} · الإجمالي:{' '}
            {(lastBroadcast.total ?? 0).toLocaleString('ar-SY')}
            {lastBroadcast.finished_at
              ? ` · ${new Date(lastBroadcast.finished_at).toLocaleString('ar-SY')}`
              : ''}
          </p>
        </div>
      )}

      <div
        className="card"
        style={{ maxWidth: 720, padding: 16, marginBottom: 14 }}
      >
        <div style={{ fontWeight: 800, marginBottom: 8 }}>
          إجبار تحديث التطبيق (النسخ القديمة)
        </div>
        <p className="muted" style={{ fontSize: 13, marginTop: 0 }}>
          عند تفعيل الخيار: أي نسخة بدون رقم بناء ≥ الحد الأدنى (أو بدون رأس
          الإصدار) تُرفض عند تسجيل الدخول مع رسالة ورابط التحميل.
        </p>
        <label className="field-label">الحد الأدنى لرقم البناء (build)</label>
        <input
          className="input"
          value={minBuild}
          onChange={(e) => setMinBuild(e.target.value)}
          style={{ width: '100%' }}
        />
        <label className="field-label" style={{ marginTop: 10 }}>
          رابط تحميل APK
        </label>
        <input
          className="input"
          value={downloadUrl}
          onChange={(e) => setDownloadUrl(e.target.value)}
          style={{ width: '100%' }}
        />
        <label className="field-label" style={{ marginTop: 10 }}>
          نص رسالة التحديث
        </label>
        <textarea
          className="input"
          rows={3}
          value={updateMessage}
          onChange={(e) => setUpdateMessage(e.target.value)}
          style={{ width: '100%' }}
        />
        <label
          style={{
            display: 'flex',
            gap: 8,
            alignItems: 'center',
            marginTop: 10,
          }}
        >
          <input
            type="checkbox"
            checked={blockOld}
            onChange={(e) => setBlockOld(e.target.checked)}
          />
          منع تسجيل الدخول من النسخ الأقدم
        </label>
        <button
          type="button"
          className="btn btn-primary"
          style={{ marginTop: 12 }}
          disabled={savingUpdate}
          onClick={() => void saveUpdateSettings()}
        >
          {savingUpdate ? 'جاري الحفظ…' : 'حفظ إعدادات التحديث'}
        </button>
      </div>

      <div className="card" style={{ maxWidth: 720, padding: 16 }}>
        <label className="field-label">نص الإعلان</label>
        <textarea
          className="input"
          rows={5}
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          placeholder="اكتب رسالة الإعلان هنا…"
          disabled={sending}
          style={{ width: '100%', resize: 'vertical' }}
        />

        <label className="field-label" style={{ marginTop: 14 }}>
          رابط ملف/صورة عام (مستحسن للـ APK)
        </label>
        <input
          className="input"
          type="url"
          value={mediaUrl}
          disabled={sending}
          placeholder="https://gstaxi.online/downloads/gstaxi.apk"
          onChange={(e) => setMediaUrl(e.target.value)}
          style={{ width: '100%' }}
        />
        <p className="muted" style={{ fontSize: 12, marginTop: 4 }}>
          ملاحظة: ملف gstaxi.apk حجمه أكبر من 30 م.ب — واتساب/UltraMsg لا يرسله
          كمرفق، لذلك يُرسل تلقائياً كرسالة نصية فيها الرابط (هذا سبب فشل آخر
          رسالتين كـ document).
        </p>

        <label className="field-label" style={{ marginTop: 14 }}>
          أو ارفع ملفاً صغيراً (حتى {MAX_UPLOAD_MB} م.ب)
        </label>
        <input
          type="file"
          accept="image/*,.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.txt,.zip,.apk"
          disabled={sending}
          onChange={(e) => onPickFile(e.target.files?.[0] ?? null)}
        />
        {file && (
          <p className="muted" style={{ marginTop: 6, fontSize: 13 }}>
            المرفق: {file.name} ({Math.round(file.size / 1024)} ك.ب)
          </p>
        )}

        <label
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            marginTop: 16,
            cursor: 'pointer',
          }}
        >
          <input
            type="checkbox"
            checked={onlyVerified}
            disabled={sending}
            onChange={(e) => setOnlyVerified(e.target.checked)}
          />
          إرسال للمؤكَّدين فقط (رقم هاتف مُفعَّل)
        </label>

        <label
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            marginTop: 12,
            cursor: 'pointer',
          }}
        >
          <input
            type="checkbox"
            checked={batchMode}
            disabled={sending}
            onChange={(e) => setBatchMode(e.target.checked)}
          />
          إرسال على دفعات ({BATCH_SIZE}) — بدون إعادة إرسال لنفس المستلم
        </label>

        {batchMode && batch && (
          <div
            style={{
              marginTop: 12,
              padding: 12,
              background: '#f0f9ff',
              borderRadius: 10,
              fontSize: 14,
              lineHeight: 1.7,
            }}
          >
            <div>
              إجمالي المستلمين:{' '}
              <strong>{batch.total.toLocaleString('ar-SY')}</strong>
            </div>
            <div>
              أُرسل لهم سابقاً (لن يُعاد):{' '}
              <strong>{batch.already_sent.toLocaleString('ar-SY')}</strong>
            </div>
            <div>
              متبقّي:{' '}
              <strong>{batch.remaining.toLocaleString('ar-SY')}</strong>
            </div>
            <div>
              الدفعة التالية:{' '}
              <strong>{batch.next_batch.toLocaleString('ar-SY')}</strong>
            </div>
          </div>
        )}

        <div style={{ marginTop: 18, borderTop: '1px solid #e5e7eb', paddingTop: 14 }}>
          <div style={{ fontWeight: 700, marginBottom: 10 }}>المستلمون</div>
          <label style={{ display: 'flex', gap: 8, alignItems: 'center', marginBottom: 8 }}>
            <input
              type="radio"
              name="who"
              checked={sendAll}
              disabled={sending}
              onChange={() => setSendAll(true)}
            />
            إرسال لجميع الزبائن المطابقين للفلتر
          </label>
          <label style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <input
              type="radio"
              name="who"
              checked={!sendAll}
              disabled={sending}
              onChange={() => setSendAll(false)}
            />
            تحديد مشتركين معيّنين
          </label>
        </div>

        {!sendAll && (
          <div style={{ marginTop: 12 }}>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 8 }}>
              <input
                className="input"
                placeholder="بحث بالاسم أو الرقم…"
                value={search}
                disabled={sending}
                onChange={(e) => {
                  setPage(1);
                  setSearch(e.target.value);
                }}
                style={{ flex: 1, minWidth: 160 }}
              />
              <button
                type="button"
                className="btn"
                disabled={loadingList || sending}
                onClick={() => void loadCustomers()}
              >
                بحث
              </button>
              <button type="button" className="btn" disabled={sending} onClick={selectPageAll}>
                تحديد الصفحة
              </button>
              <button type="button" className="btn" disabled={sending} onClick={clearSelection}>
                إلغاء التحديد
              </button>
            </div>
            <p className="muted" style={{ fontSize: 13 }}>
              محدّد: {selectedCount.toLocaleString('ar-SY')} · في القائمة:{' '}
              {listTotal.toLocaleString('ar-SY')}
            </p>
            {loadingList ? (
              <p className="muted">جاري التحميل…</p>
            ) : (
              <div
                style={{
                  maxHeight: 280,
                  overflow: 'auto',
                  border: '1px solid #e5e7eb',
                  borderRadius: 10,
                }}
              >
                {rows.map((r) => (
                  <label
                    key={r.id}
                    style={{
                      display: 'flex',
                      gap: 10,
                      alignItems: 'center',
                      padding: '8px 10px',
                      borderBottom: '1px solid #f0f1f5',
                      cursor: 'pointer',
                    }}
                  >
                    <input
                      type="checkbox"
                      checked={!!selected[r.id]}
                      disabled={sending}
                      onChange={() => toggleOne(r.id)}
                    />
                    <span style={{ flex: 1 }}>
                      <strong>{r.name}</strong>
                      <span className="muted" style={{ marginInlineStart: 8 }}>
                        {r.number}
                      </span>
                    </span>
                  </label>
                ))}
                {rows.length === 0 && (
                  <p className="muted" style={{ padding: 12 }}>
                    لا نتائج
                  </p>
                )}
              </div>
            )}
            <div style={{ display: 'flex', gap: 8, marginTop: 8, alignItems: 'center' }}>
              <button
                type="button"
                className="btn"
                disabled={sending || page <= 1}
                onClick={() => setPage((p) => Math.max(1, p - 1))}
              >
                السابق
              </button>
              <span className="muted" style={{ fontSize: 13 }}>
                صفحة {page} / {lastPage}
              </span>
              <button
                type="button"
                className="btn"
                disabled={sending || page >= lastPage}
                onClick={() => setPage((p) => p + 1)}
              >
                التالي
              </button>
            </div>
          </div>
        )}

        <div
          style={{
            marginTop: 16,
            display: 'flex',
            flexWrap: 'wrap',
            gap: 10,
            alignItems: 'center',
          }}
        >
          <button
            type="button"
            className="btn"
            onClick={() => void loadCount()}
            disabled={loadingCount || sending}
          >
            {loadingCount ? 'جاري العد…' : 'تحديث العدد'}
          </button>
          {batchMode && (
            <button
              type="button"
              className="btn"
              onClick={() => void resetBatch()}
              disabled={sending || loadingCount}
            >
              إعادة التعيين (من الأول)
            </button>
          )}
          <span style={{ fontWeight: 700 }}>
            المستلمون:{' '}
            {displayRecipients == null
              ? '—'
              : displayRecipients.toLocaleString('ar-SY')}
          </span>
        </div>

        <button
          type="button"
          className="btn btn-primary"
          style={{ marginTop: 18, width: '100%' }}
          disabled={
            sending ||
            ultramsgOk === false ||
            (batchMode && (batch?.next_batch ?? 0) < 1)
          }
          onClick={() => void send()}
        >
          {sendBtnLabel}
        </button>

        {progress && (
          <div style={{ marginTop: 18 }}>
            <div
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                fontSize: 13,
                marginBottom: 6,
              }}
            >
              <span>
                الحالة:{' '}
                {progress.status === 'done'
                  ? 'اكتمل'
                  : progress.status === 'failed'
                    ? 'فشل'
                    : progress.status === 'cancelled'
                      ? 'أُلغي'
                      : progress.status === 'cancelling'
                        ? 'جاري الإلغاء…'
                        : progress.status === 'running'
                          ? 'جارٍ…'
                          : 'في الطابور'}
              </span>
              <span>
                نجح {progress.sent ?? 0} · فشل {progress.failed ?? 0} · من{' '}
                {progress.total ?? 0}
              </span>
            </div>
            {(progress.status === 'running' ||
              progress.status === 'queued' ||
              progress.status === 'cancelling') && (
              <button
                type="button"
                className="btn"
                style={{
                  marginBottom: 10,
                  width: '100%',
                  background: '#b91c1c',
                  color: '#fff',
                  border: 'none',
                }}
                disabled={cancelling || progress.status === 'cancelling'}
                onClick={() => void cancelSend()}
              >
                {cancelling || progress.status === 'cancelling'
                  ? 'جاري إيقاف الإرسال…'
                  : 'إلغاء الإرسال'}
              </button>
            )}
            <div
              style={{
                height: 10,
                background: '#e8eaf0',
                borderRadius: 6,
                overflow: 'hidden',
              }}
            >
              <div
                style={{
                  width: `${pct}%`,
                  height: '100%',
                  background: '#11215b',
                  transition: 'width .3s',
                }}
              />
            </div>
            {progress.error && (
              <p className="text-err" style={{ marginTop: 8 }}>
                {progress.error}
              </p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
