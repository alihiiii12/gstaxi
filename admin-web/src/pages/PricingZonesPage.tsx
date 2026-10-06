import { useCallback, useEffect, useMemo, useState } from 'react';
import { API } from '../api/endpoints';
import { deleteJson, fetchJsonAuth, postJson, putJson } from '../api/http';
import { PageHeader } from '../components/PageHeader';
import { ZoneEditorMap, type TestPin, type ZoneShape } from '../components/ZoneEditorMap';
import { formatApiFailure } from '../util/apiError';
import type { LatLngTuple } from '../util/requestRouteMap';

type Snapshot = {
  zones: ZoneShape[];
  rules: Record<string, string>;
  outsideName: string;
};

type Editing = {
  id: number | null;
  name: string;
  color: string;
  active: boolean;
  polygon: LatLngTuple[];
};

type Mode = 'idle' | 'edit' | 'draw' | 'test';

const OUTSIDE = 0;
const COLORS = ['#1a2f75', '#2e7d32', '#c62828', '#6a1b9a', '#ef6c00', '#00838f'];

function parseSnapshot(d: Record<string, unknown>): Snapshot {
  const zones: ZoneShape[] = ((d.zones as unknown[]) ?? []).map((raw) => {
    const z = raw as Record<string, unknown>;
    const poly = ((z.polygon as unknown[]) ?? [])
      .map((p) => (Array.isArray(p) ? ([Number(p[0]), Number(p[1])] as LatLngTuple) : null))
      .filter((p): p is LatLngTuple => p !== null && Number.isFinite(p[0]) && Number.isFinite(p[1]));
    return {
      id: Number(z.id),
      name: String(z.name ?? ''),
      color: String(z.color ?? '#1a2f75'),
      active: z.is_active !== false,
      polygon: poly,
    };
  });
  const rules: Record<string, string> = {};
  for (const raw of (d.rules as unknown[]) ?? []) {
    const r = raw as Record<string, unknown>;
    rules[`${r.from_zone_id}:${r.to_zone_id}`] = String(Number(r.multiplier));
  }
  const outside = (d.outside as Record<string, unknown>) ?? {};
  return { zones, rules, outsideName: String(outside.name ?? 'الريف') };
}

export function PricingZonesPage() {
  const [snap, setSnap] = useState<Snapshot | null>(null);
  const [err, setErr] = useState('');
  const [rules, setRules] = useState<Record<string, string>>({});
  const [savingRules, setSavingRules] = useState(false);
  const [mode, setMode] = useState<Mode>('idle');
  const [editing, setEditing] = useState<Editing | null>(null);
  const [savingZone, setSavingZone] = useState(false);
  const [fitToken, setFitToken] = useState(0);
  const [testPins, setTestPins] = useState<LatLngTuple[]>([]);
  const [testResult, setTestResult] = useState<Record<string, unknown> | null>(null);
  const [outsideDraft, setOutsideDraft] = useState('');
  const [savingOutside, setSavingOutside] = useState(false);

  const apply = useCallback((d: Record<string, unknown>, refit = false) => {
    const s = parseSnapshot(d);
    setSnap(s);
    setRules(s.rules);
    setOutsideDraft(s.outsideName);
    if (refit) setFitToken((n) => n + 1);
  }, []);

  const load = useCallback(async () => {
    setErr('');
    try {
      const { res, data: j } = await fetchJsonAuth(API.adminPricingZones);
      if (!res.ok || j.success !== true) throw new Error(String(j.message ?? res.statusText));
      apply(j.data as Record<string, unknown>, true);
    } catch (e) {
      setErr(String(e));
    }
  }, [apply]);

  useEffect(() => {
    void load();
  }, [load]);

  const cols = useMemo(() => {
    if (!snap) return [];
    return [
      ...snap.zones.map((z) => ({ id: z.id, name: z.name, color: z.color })),
      { id: OUTSIDE, name: snap.outsideName, color: '#8d6e63' },
    ];
  }, [snap]);

  function startEdit(z: ZoneShape) {
    setTestPins([]);
    setTestResult(null);
    setEditing({ id: z.id, name: z.name, color: z.color, active: z.active, polygon: z.polygon });
    setMode('edit');
    setFitToken((n) => n + 1);
  }

  function startDraw() {
    setTestPins([]);
    setTestResult(null);
    const used = new Set(snap?.zones.map((z) => z.color));
    setEditing({
      id: null,
      name: '',
      color: COLORS.find((c) => !used.has(c)) ?? COLORS[0],
      active: true,
      polygon: [],
    });
    setMode('draw');
  }

  function cancelEdit() {
    setEditing(null);
    setMode('idle');
  }

  async function saveZone() {
    if (!editing) return;
    if (!editing.name.trim()) {
      alert('اكتب اسم المنطقة');
      return;
    }
    if (editing.polygon.length < 3) {
      alert('ارسم 3 نقاط على الأقل على الخريطة');
      return;
    }
    setSavingZone(true);
    try {
      const body = {
        name: editing.name.trim(),
        color: editing.color,
        is_active: editing.active,
        polygon: editing.polygon.map(([a, b]) => [Number(a.toFixed(6)), Number(b.toFixed(6))]),
      };
      const { res, data } =
        editing.id === null
          ? await postJson<Record<string, unknown>>(API.adminPricingZones, body)
          : await putJson<Record<string, unknown>>(API.adminPricingZone(editing.id), body);
      if (res.ok && data.success === true) {
        apply(data.data as Record<string, unknown>);
        setEditing(null);
        setMode('idle');
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } finally {
      setSavingZone(false);
    }
  }

  async function removeZone(z: ZoneShape) {
    if (!window.confirm(`حذف منطقة «${z.name}»؟ ستُعتبر نقاطها «${snap?.outsideName}» بعد الحذف.`)) return;
    const { res, data } = await deleteJson(API.adminPricingZone(z.id));
    if (res.ok && data.success === true) {
      apply(data.data as Record<string, unknown>);
      if (editing?.id === z.id) cancelEdit();
    } else {
      alert(formatApiFailure(data, JSON.stringify(data)));
    }
  }

  async function saveOutsideName() {
    const name = outsideDraft.trim();
    if (!name) {
      alert('اكتب اسماً للمنطقة الخارجية');
      return;
    }
    setSavingOutside(true);
    try {
      const { res, data } = await putJson<Record<string, unknown>>(API.adminPricingZoneOutside, { name });
      if (res.ok && data.success === true) {
        apply(data.data as Record<string, unknown>);
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } finally {
      setSavingOutside(false);
    }
  }

  async function saveRules() {
    const list: { from_zone_id: number; to_zone_id: number; multiplier: number }[] = [];
    for (const from of cols) {
      for (const to of cols) {
        const raw = rules[`${from.id}:${to.id}`] ?? '1';
        const m = Number(raw);
        if (!(m >= 0.1 && m <= 20)) {
          alert(`قيمة غير صحيحة (${from.name} ← ${to.name}): أدخل رقماً بين 0.1 و 20`);
          return;
        }
        list.push({ from_zone_id: from.id, to_zone_id: to.id, multiplier: m });
      }
    }
    setSavingRules(true);
    try {
      const { res, data } = await putJson<Record<string, unknown>>(API.adminPricingZoneRules, {
        rules: list,
      });
      if (res.ok && data.success === true) {
        apply(data.data as Record<string, unknown>);
        alert('حُفظت المعاملات — تُطبَّق على الطلبات الجديدة فوراً');
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } finally {
      setSavingRules(false);
    }
  }

  const runTest = useCallback(async (a: LatLngTuple, b: LatLngTuple) => {
    const q = new URLSearchParams({
      pickup_lat: String(a[0]),
      pickup_lng: String(a[1]),
      dest_lat: String(b[0]),
      dest_lng: String(b[1]),
    });
    const { data } = await fetchJsonAuth(`${API.adminPricingZoneQuote}?${q}`);
    setTestResult((data.data as Record<string, unknown>) ?? null);
  }, []);

  const onMapClick = useMemo(() => {
    if (mode === 'draw') {
      return (pos: LatLngTuple) =>
        setEditing((e) => (e ? { ...e, polygon: [...e.polygon, pos] } : e));
    }
    if (mode === 'test') {
      return (pos: LatLngTuple) => {
        setTestPins((prev) => {
          const next = prev.length >= 2 ? [pos] : [...prev, pos];
          if (next.length === 2) void runTest(next[0], next[1]);
          else setTestResult(null);
          return next;
        });
      };
    }
    return undefined;
  }, [mode, runTest]);

  const pins: TestPin[] = useMemo(
    () => testPins.map((p, i) => ({ position: p, label: i === 0 ? 'A' : 'B' })),
    [testPins],
  );

  const zonesForMap = useMemo(
    () =>
      (snap?.zones ?? []).map((z) =>
        editing?.id === z.id ? { ...z, color: editing.color } : z,
      ),
    [snap, editing],
  );

  const editingForMap = useMemo(
    () =>
      editing ? { id: editing.id, color: editing.color, polygon: editing.polygon } : null,
    [editing],
  );

  return (
    <div className="page-pad">
      <PageHeader
        title="مناطق التسعير"
        subtitle={`ارسم المناطق على الخريطة وحدّد معامل السعر بين كل منطقتين. أي مكان خارج المناطق المرسومة يُعتبر «${snap?.outsideName ?? 'الريف'}». يمكن رسم منطقة داخل أخرى (المدينة داخل حدود الريف) — الأصغر لها الأولوية.`}
        onRefresh={() => void load()}
        actions={
          <button type="button" className="btn-primary" onClick={startDraw} disabled={mode !== 'idle' && mode !== 'test'}>
            + منطقة جديدة
          </button>
        }
      />
      {err && <p className="text-err">{err}</p>}

      <div className="pz-layout">
        <div className="pz-map-col">
          <div className="pz-toolbar">
            {mode === 'idle' && (
              <button type="button" className="btn-ghost" onClick={() => setMode('test')}>
                🧪 اختبار التسعيرة على الخريطة
              </button>
            )}
            {mode === 'test' && (
              <>
                <span className="pz-hint">
                  انقر نقطة الانطلاق <b>A</b> ثم الوجهة <b>B</b>
                </span>
                <button
                  type="button"
                  className="btn-ghost"
                  onClick={() => {
                    setMode('idle');
                    setTestPins([]);
                    setTestResult(null);
                  }}
                >
                  إنهاء الاختبار
                </button>
              </>
            )}
            {mode === 'draw' && (
              <span className="pz-hint">
                انقر على الخريطة لإضافة نقاط حدود المنطقة بالترتيب ({editing?.polygon.length ?? 0} نقطة)
              </span>
            )}
            {mode === 'edit' && (
              <span className="pz-hint">
                اسحب النقاط البيضاء لتعديل الحد · اسحب النقاط الصغيرة لإضافة نقطة · انقر مرتين على نقطة لحذفها
              </span>
            )}
          </div>
          <ZoneEditorMap
            zones={zonesForMap}
            editing={editingForMap}
            onEditingChange={(polygon) => setEditing((e) => (e ? { ...e, polygon } : e))}
            onMapClick={onMapClick}
            testPins={pins}
            fitToken={fitToken}
          />
          {mode === 'test' && testResult && (
            <div className="pz-test-result">
              <div>
                <span className="text-muted">من</span> <b>{String((testResult.from_zone as Record<string, unknown>)?.name ?? '')}</b>
                <span className="text-muted"> إلى </span>
                <b>{String((testResult.to_zone as Record<string, unknown>)?.name ?? '')}</b>
              </div>
              <div className="pz-mult">×{String(testResult.multiplier ?? 1)}</div>
            </div>
          )}
        </div>

        <div className="pz-side-col">
          {editing ? (
            <div className="card pz-card">
              <div className="card-title">{editing.id === null ? 'منطقة جديدة' : 'تعديل المنطقة'}</div>
              <label className="pz-field">
                الاسم
                <input
                  value={editing.name}
                  onChange={(e) => setEditing({ ...editing, name: e.target.value })}
                  placeholder="مثال: جرمانا"
                />
              </label>
              <div className="pz-field">
                اللون
                <div className="pz-colors">
                  {COLORS.map((c) => (
                    <button
                      key={c}
                      type="button"
                      className={`pz-color${editing.color === c ? ' active' : ''}`}
                      style={{ background: c }}
                      onClick={() => setEditing({ ...editing, color: c })}
                      aria-label={c}
                    />
                  ))}
                </div>
              </div>
              <label className="pz-check">
                <input
                  type="checkbox"
                  checked={editing.active}
                  onChange={(e) => setEditing({ ...editing, active: e.target.checked })}
                />
                مفعّلة (إن عُطّلت تُعتبر نقاطها «{snap?.outsideName}»)
              </label>
              <div className="text-muted small">عدد النقاط: {editing.polygon.length}</div>
              <div className="row-gap" style={{ marginTop: 12, flexWrap: 'wrap' }}>
                <button type="button" className="btn-primary" disabled={savingZone} onClick={() => void saveZone()}>
                  {savingZone ? 'جاري الحفظ…' : 'حفظ المنطقة'}
                </button>
                {mode === 'draw' && editing.polygon.length > 0 && (
                  <button
                    type="button"
                    className="btn-ghost"
                    onClick={() => setEditing({ ...editing, polygon: editing.polygon.slice(0, -1) })}
                  >
                    تراجع عن آخر نقطة
                  </button>
                )}
                {mode === 'draw' && editing.polygon.length >= 3 && (
                  <button type="button" className="btn-ghost" onClick={() => setMode('edit')}>
                    إنهاء الرسم وتعديل النقاط
                  </button>
                )}
                <button type="button" className="btn-ghost" onClick={cancelEdit}>
                  إلغاء
                </button>
              </div>
            </div>
          ) : (
            <div className="card pz-card">
              <div className="card-title">المناطق</div>
              {(snap?.zones ?? []).map((z) => (
                <div key={z.id} className="pz-zone-row">
                  <span className="pz-swatch" style={{ background: z.color }} />
                  <div style={{ flex: 1 }}>
                    <b>{z.name}</b>
                    <div className="text-muted small">
                      {z.active ? 'مفعّلة' : 'معطّلة'} · {z.polygon.length} نقطة
                    </div>
                  </div>
                  <button type="button" className="btn-ghost" onClick={() => startEdit(z)}>
                    تعديل الحدود
                  </button>
                  <button type="button" className="btn-warn" onClick={() => void removeZone(z)}>
                    حذف
                  </button>
                </div>
              ))}
              <div className="pz-zone-row">
                <span className="pz-swatch" style={{ background: '#8d6e63' }} />
                <div style={{ flex: 1 }}>
                  <input
                    value={outsideDraft}
                    onChange={(e) => setOutsideDraft(e.target.value)}
                    maxLength={80}
                    placeholder="مثال: ريف الريف"
                    style={{ width: '100%' }}
                  />
                  <div className="text-muted small">كل مكان خارج المناطق أعلاه</div>
                </div>
                <button
                  type="button"
                  className="btn-ghost"
                  disabled={savingOutside || !snap || outsideDraft.trim() === snap.outsideName}
                  onClick={() => void saveOutsideName()}
                >
                  {savingOutside ? 'جاري الحفظ…' : 'حفظ الاسم'}
                </button>
              </div>
            </div>
          )}

          <div className="card pz-card">
            <div className="card-title">معامل السعر (من ← إلى)</div>
            <p className="text-muted small" style={{ margin: '4px 0 10px' }}>
              السعر = (افتتاح + كم × سعر الكيلو + دقائق × سعر الدقيقة) × المعامل. 1 = بدون تغيير، 1.5 = زيادة 50٪.
            </p>
            <div style={{ overflowX: 'auto' }}>
              <table className="pz-matrix">
                <thead>
                  <tr>
                    <th>من ↓ / إلى ←</th>
                    {cols.map((c) => (
                      <th key={c.id}>
                        <span className="pz-swatch sm" style={{ background: c.color }} /> {c.name}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {cols.map((from) => (
                    <tr key={from.id}>
                      <th>
                        <span className="pz-swatch sm" style={{ background: from.color }} /> {from.name}
                      </th>
                      {cols.map((to) => {
                        const k = `${from.id}:${to.id}`;
                        const v = rules[k] ?? '1';
                        const changed = Number(v) !== 1;
                        return (
                          <td key={to.id}>
                            <div className={`pz-mult-input${changed ? ' changed' : ''}`}>
                              <span>×</span>
                              <input
                                type="number"
                                inputMode="decimal"
                                min={0.1}
                                max={20}
                                step="0.05"
                                value={v}
                                onChange={(e) => setRules((r) => ({ ...r, [k]: e.target.value }))}
                              />
                            </div>
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <button
              type="button"
              className="btn-primary"
              style={{ marginTop: 12 }}
              disabled={savingRules || !snap}
              onClick={() => void saveRules()}
            >
              {savingRules ? 'جاري الحفظ…' : 'حفظ المعاملات'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
