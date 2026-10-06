import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { API } from '../api/endpoints';
import { fetchJsonAuth, putJson } from '../api/http';
import { PageHeader } from '../components/PageHeader';
import { formatApiFailure } from '../util/apiError';

function readNum(d: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const v = d[k];
    if (v != null && String(v).trim() !== '') return String(v);
  }
  return '';
}

export function FreeMeterPage() {
  const [openPrice, setOpenPrice] = useState('');
  const [kmPrice, setKmPrice] = useState('');
  const [timePrice, setTimePrice] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');

  const load = useCallback(async () => {
    setErr('');
    setLoading(true);
    try {
      const { res, data: j } = await fetchJsonAuth(API.adminFreeMeterSettings);
      if (res.ok && j.success === true) {
        const d = j.data as Record<string, unknown> | undefined;
        if (d) {
          setOpenPrice(readNum(d, ['openPrice', 'open_price']));
          setKmPrice(readNum(d, ['kmPrice', 'KMPrice', 'km_price']));
          setTimePrice(readNum(d, ['timePrice', 'time_price']));
        }
      }
    } catch (e) {
      setErr(String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function save() {
    const open = Number(openPrice.trim());
    const km = Number(kmPrice.trim());
    const tm = Number(timePrice.trim());
    if (Number.isNaN(open) || open < 0) {
      alert('أدخل سعر فتح العداد رقماً صحيحاً');
      return;
    }
    if (Number.isNaN(km) || km < 0) {
      alert('أدخل سعر الكيلومتر رقماً صحيحاً');
      return;
    }
    if (Number.isNaN(tm) || tm < 0) {
      alert('أدخل سعر الدقيقة رقماً صحيحاً');
      return;
    }
    setSaving(true);
    setErr('');
    try {
      const { res, data } = await putJson<Record<string, unknown>>(
        API.adminFreeMeterSettings,
        { openPrice: open, kmPrice: km, timePrice: tm },
      );
      if (res.ok && data.success === true) {
        await load();
        alert(String(data.message ?? 'حُفظ الإعداد'));
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } catch (e) {
      setErr(String(e));
    } finally {
      setSaving(false);
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
    <div className="page-pad narrow">
      <PageHeader
        title="إعدادات العداد الحر"
        subtitle="سعر الفتح والكيلومتر والدقيقة لرحلات العداد من تطبيق السائق."
        onRefresh={() => void load()}
        actions={
          <Link
            to="/requests?billing=free_meter"
            className="btn-ghost"
            style={{ textDecoration: 'none' }}
          >
            رحلات العداد
          </Link>
        }
      />
      <p className="text-muted" style={{ lineHeight: 1.45 }}>
        رحلات <strong>طلب التطبيق</strong> تُسعَّر من فئات السيارة، وليست من هنا.
      </p>
      {err && <p className="text-err">{err}</p>}
      <div className="form-panel">
        <label>
          سعر فتح العداد (ل.س)
          <input
            value={openPrice}
            onChange={(e) => setOpenPrice(e.target.value)}
            inputMode="decimal"
          />
        </label>
        <label>
          سعر الكيلومتر (ل.س / كم)
          <input
            value={kmPrice}
            onChange={(e) => setKmPrice(e.target.value)}
            inputMode="decimal"
          />
        </label>
        <label>
          سعر الدقيقة (ل.س / دقيقة)
          <input
            value={timePrice}
            onChange={(e) => setTimePrice(e.target.value)}
            inputMode="decimal"
          />
        </label>
        <div className="action-row">
          <button
            type="button"
            className="btn-primary"
            disabled={saving}
            onClick={() => void save()}
          >
            {saving ? 'جاري الحفظ…' : 'حفظ الإعدادات'}
          </button>
          <button type="button" className="btn-ghost" onClick={() => void load()}>
            إعادة التحميل
          </button>
        </div>
      </div>
    </div>
  );
}
