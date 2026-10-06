import { useCallback, useEffect, useState } from 'react';
import { API } from '../api/endpoints';
import { deleteJson, fetchJsonAuth, postJson, putJson } from '../api/http';
import { formatApiFailure } from '../util/apiError';

type AreaRow = Record<string, unknown>;

export function AreasPage() {
  const [rows, setRows] = useState<AreaRow[]>([]);
  const [err, setErr] = useState('');
  const [loading, setLoading] = useState(true);
  const [editor, setEditor] = useState<AreaRow | null | 'new'>(null);

  const load = useCallback(async () => {
    setErr('');
    setLoading(true);
    try {
      const { res, data: j } = await fetchJsonAuth(API.adminServiceAreas);
      if (!res.ok || j.success !== true) {
        throw new Error(String(j.message ?? res.statusText));
      }
      const list = (j.data as unknown[]) ?? [];
      setRows(list.map((e) => e as AreaRow));
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
    if (!window.confirm('حذف هذه المنطقة؟')) return;
    const { res, data: j } = await deleteJson(API.adminServiceAreaUpdate(id));
    if (res.ok && j.success === true) {
      alert('حُذفت المنطقة');
      void load();
    } else {
      alert(formatApiFailure(j, JSON.stringify(j)));
    }
  }

  return (
    <div className="page-pad">
      <div className="row-between wrap">
        <h2 className="page-title">مناطق إدارية (اختياري)</h2>
        <div className="row-gap">
          <button type="button" className="btn-ghost" onClick={() => void load()}>
            تحديث
          </button>
          <button type="button" className="btn-primary" onClick={() => setEditor('new')}>
            + منطقة
          </button>
        </div>
      </div>
      <div className="card" style={{ marginTop: 12, background: '#e3f2fd' }}>
        <p style={{ margin: 0, lineHeight: 1.45, fontSize: '0.9rem' }}>
          التطبيق يخدم سوريا بالكامل. المناطق هنا للتقسيم الإداري أو التقارير فقط، ولا تظهر
          للراكب ولا تُقيّد نقاط الانطلاق أو الوجهة على مستوى الوطن.
        </p>
      </div>
      {err && <p className="text-err">{err}</p>}
      {loading ? (
        <div className="page-center">
          <div className="spinner" />
        </div>
      ) : (
        <div className="card-list">
          {rows.map((r) => {
            const id = Number(r.id ?? 0);
            const bb = `جنوب ${r.south_lat ?? '—'} شمال ${r.north_lat ?? '—'} غرب ${r.west_lng ?? '—'} شرق ${r.east_lng ?? '—'}`;
            return (
              <div key={id || String(r.name)} className="card">
                <div className="row-between">
                  <div>
                    <div className="card-title">{String(r.name ?? '')}</div>
                    <div className="text-muted" style={{ marginTop: 6 }}>
                      {r.active === true ? 'نشطة' : 'معطّلة'}
                    </div>
                    <pre className="card-sub" style={{ marginTop: 8 }}>
                      {bb}
                    </pre>
                  </div>
                  <div className="row-gap">
                    <button type="button" className="btn-ghost" onClick={() => setEditor(r)}>
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
        <p className="text-muted">لا توجد مناطق. أضف منطقة أو حدّث القائمة.</p>
      )}

      {editor !== null && (
        <AreaEditorModal
          mode={editor === 'new' ? 'new' : 'edit'}
          existing={editor === 'new' ? null : editor}
          onClose={() => setEditor(null)}
          onSaved={() => {
            setEditor(null);
            void load();
          }}
        />
      )}
    </div>
  );
}

function AreaEditorModal({
  mode,
  existing,
  onClose,
  onSaved,
}: {
  mode: 'new' | 'edit';
  existing: AreaRow | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(String(existing?.name ?? ''));
  const [active, setActive] = useState(existing == null ? true : existing.active === true);
  const [sortOrder, setSortOrder] = useState(String(existing?.sort_order ?? '0'));
  const [south, setSouth] = useState(String(existing?.south_lat ?? ''));
  const [north, setNorth] = useState(String(existing?.north_lat ?? ''));
  const [west, setWest] = useState(String(existing?.west_lng ?? ''));
  const [east, setEast] = useState(String(existing?.east_lng ?? ''));
  const [busy, setBusy] = useState(false);

  function boundsBody(): Record<string, unknown> {
    const o: Record<string, unknown> = {};
    const s = south.trim();
    const n = north.trim();
    const w = west.trim();
    const e = east.trim();
    if (s) o.south_lat = Number(s);
    if (n) o.north_lat = Number(n);
    if (w) o.west_lng = Number(w);
    if (e) o.east_lng = Number(e);
    return o;
  }

  async function save() {
    setBusy(true);
    try {
      const body = {
        name: name.trim(),
        active,
        sort_order: Number(sortOrder) || 0,
        ...boundsBody(),
      };
      if (mode === 'new') {
        const { res, data } = await postJson<Record<string, unknown>>(
          API.adminServiceAreas,
          body,
        );
        if ((res.status === 200 || res.status === 201) && data.success === true) {
          alert('أُضيفت المنطقة');
          onSaved();
        } else {
          alert(formatApiFailure(data, JSON.stringify(data)));
        }
      } else {
        const id = Number(existing?.id ?? 0);
        const { res, data } = await putJson<Record<string, unknown>>(
          API.adminServiceAreaUpdate(id),
          body,
        );
        if (res.ok && data.success === true) {
          alert('حُفظ التعديل');
          onSaved();
        } else {
          alert(formatApiFailure(data, JSON.stringify(data)));
        }
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" role="presentation" onClick={onClose}>
      <div className="modal" role="dialog" onClick={(ev) => ev.stopPropagation()} dir="rtl">
        <h3>{mode === 'new' ? 'منطقة جديدة' : 'تعديل المنطقة'}</h3>
        <label>
          اسم المنطقة
          <input value={name} onChange={(e) => setName(e.target.value)} />
        </label>
        <label style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
          <input
            type="checkbox"
            checked={active}
            onChange={(e) => setActive(e.target.checked)}
          />
          نشطة
        </label>
        <label>
          ترتيب العرض
          <input value={sortOrder} onChange={(e) => setSortOrder(e.target.value)} />
        </label>
        <p className="text-muted small" style={{ marginTop: 12 }}>
          حدود تقريبية (اختياري — إبقاؤها فارغة يعني عدم التحقق الجغرافي لهذه المنطقة)
        </p>
        <label>
          أدنى خط عرض (south_lat)
          <input value={south} onChange={(e) => setSouth(e.target.value)} />
        </label>
        <label>
          أعلى خط عرض (north_lat)
          <input value={north} onChange={(e) => setNorth(e.target.value)} />
        </label>
        <label>
          أدنى خط طول (west_lng)
          <input value={west} onChange={(e) => setWest(e.target.value)} />
        </label>
        <label>
          أعلى خط طول (east_lng)
          <input value={east} onChange={(e) => setEast(e.target.value)} />
        </label>
        <div className="row-gap" style={{ marginTop: 16 }}>
          <button type="button" className="btn-ghost" onClick={onClose}>
            إلغاء
          </button>
          <button type="button" className="btn-primary" disabled={busy} onClick={() => void save()}>
            {busy ? '…' : mode === 'new' ? 'إضافة' : 'حفظ'}
          </button>
        </div>
      </div>
    </div>
  );
}
