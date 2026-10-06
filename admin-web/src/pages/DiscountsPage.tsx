import { useCallback, useEffect, useState } from 'react';
import { API } from '../api/endpoints';
import { deleteJson, fetchJsonAuth, postJson } from '../api/http';
import { ModalPortal } from '../components/ModalPortal';
import { PageHeader } from '../components/PageHeader';
import { formatApiFailure } from '../util/apiError';

type CustomerPick = {
  id: number;
  name: string;
  phone: string;
};

const CUSTOMERS_PAGE_SIZE = 40;

type UsesMode = 'once' | 'custom' | 'unlimited';

function timesLabel(n: number): string {
  if (n <= 1) return 'مرة واحدة';
  if (n === 2) return 'مرتين';
  if (n <= 10) return `${n} مرات`;
  return `${n} مرة`;
}

function usesLimitOf(d: Record<string, unknown>): number | null {
  if (!('max_uses_per_user' in d)) return 1;
  const v = d.max_uses_per_user;
  if (v === null || v === undefined) return null;
  const n = Number(v);
  return Number.isFinite(n) && n >= 1 ? Math.floor(n) : 1;
}

export function DiscountsPage() {
  const [rows, setRows] = useState<Record<string, unknown>[]>([]);
  const [err, setErr] = useState('');
  const [show, setShow] = useState(false);
  const [creating, setCreating] = useState(false);
  const [deletingId, setDeletingId] = useState<number | null>(null);
  const [targetMode, setTargetMode] = useState<'all' | 'specific'>('all');
  const [discType, setDiscType] = useState<'Percentage' | 'Fixed'>('Percentage');
  const [amountStr, setAmountStr] = useState('');
  const [maxStr, setMaxStr] = useState('');
  const [usesMode, setUsesMode] = useState<UsesMode>('once');
  const [usesStr, setUsesStr] = useState('3');
  const [savingUsesId, setSavingUsesId] = useState<number | null>(null);
  /** phone → label (name) */
  const [selected, setSelected] = useState<Record<string, string>>({});
  const [custSearch, setCustSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [custPage, setCustPage] = useState(1);
  const [custLastPage, setCustLastPage] = useState(1);
  const [custTotal, setCustTotal] = useState(0);
  const [customers, setCustomers] = useState<CustomerPick[]>([]);
  const [custLoading, setCustLoading] = useState(false);
  const [custErr, setCustErr] = useState('');

  const load = useCallback(async () => {
    setErr('');
    try {
      const { data: j } = await fetchJsonAuth(`${API.discountsIndex}?per_page=30`);
      if (j.success !== true) throw new Error(String(j.message ?? ''));
      const data = j.data as Record<string, unknown> | undefined;
      const inner = data?.data as unknown[] | undefined;
      setRows(
        Array.isArray(inner)
          ? inner.map((e) => e as Record<string, unknown>)
          : [],
      );
    } catch (e) {
      setErr(String(e));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const t = window.setTimeout(() => setDebouncedSearch(custSearch.trim()), 350);
    return () => window.clearTimeout(t);
  }, [custSearch]);

  useEffect(() => {
    setCustPage(1);
  }, [debouncedSearch]);

  const loadCustomers = useCallback(async () => {
    if (!show || targetMode !== 'specific') return;
    setCustLoading(true);
    setCustErr('');
    try {
      const q = new URLSearchParams();
      q.set('per_page', String(CUSTOMERS_PAGE_SIZE));
      q.set('page', String(custPage));
      if (debouncedSearch) q.set('search', debouncedSearch);
      const { res, data: j } = await fetchJsonAuth(`${API.adminCustomers}?${q}`);
      if (!res.ok || j.success !== true) {
        throw new Error(String(j.message ?? res.statusText));
      }
      const payload = (j.data as Record<string, unknown>) ?? {};
      const inner = (payload.data as unknown[]) ?? [];
      const list: CustomerPick[] = [];
      for (const raw of inner) {
        const u = raw as Record<string, unknown>;
        const id = Number(u.id ?? 0);
        const phone = String(u.number ?? '').trim();
        if (!phone) continue;
        const name =
          `${u.firstName ?? ''} ${u.lastName ?? ''}`.trim() || `زبون #${id}`;
        list.push({ id, name, phone });
      }
      setCustomers(list);
      setCustLastPage(Number(payload.last_page ?? 1));
      setCustTotal(Number(payload.total ?? list.length));
    } catch (e) {
      setCustErr(String(e));
      setCustomers([]);
    } finally {
      setCustLoading(false);
    }
  }, [show, targetMode, custPage, debouncedSearch]);

  useEffect(() => {
    void loadCustomers();
  }, [loadCustomers]);

  function toggleCustomer(c: CustomerPick) {
    setSelected((prev) => {
      const next = { ...prev };
      if (next[c.phone]) delete next[c.phone];
      else next[c.phone] = c.name;
      return next;
    });
  }

  function resetModal() {
    setTargetMode('all');
    setDiscType('Percentage');
    setAmountStr('');
    setMaxStr('');
    setUsesMode('once');
    setUsesStr('3');
    setSelected({});
    setCustSearch('');
    setDebouncedSearch('');
    setCustPage(1);
    setCustErr('');
  }

  async function remove(id: number, code: string) {
    if (
      !window.confirm(
        `حذف الكوبون «${code}» نهائياً من قاعدة البيانات؟ لا يمكن التراجع.`,
      )
    ) {
      return;
    }
    setDeletingId(id);
    try {
      const { res, data: j } = await deleteJson(API.discountsDestroy(id));
      if (res.ok && j.success === true) {
        alert(String(j.message ?? 'تم حذف الكوبون'));
        await load();
      } else {
        alert(formatApiFailure(j, JSON.stringify(j)));
      }
    } finally {
      setDeletingId(null);
    }
  }

  async function notify(id: number) {
    const { res, data } = await postJson<Record<string, unknown>>(
      API.adminDiscountNotify(id),
      {},
    );
    const ok = res.ok && (data.success === true || data.state === true);
    alert(ok ? String(data.message ?? 'تم') : String(data.message ?? 'فشل'));
  }

  async function create(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const code = String(fd.get('code') ?? '').trim();
    const amount = Number(fd.get('amount') ?? 0);
    const maxDiscount = Number(fd.get('max_discount') ?? 0);
    const phones = Object.keys(selected);
    if (!(amount > 0)) {
      alert('أدخل قيمة خصم أكبر من صفر');
      return;
    }
    if (discType === 'Percentage' && !(maxDiscount > 0)) {
      alert('أدخل أقصى مبلغ للخصم (بالليرة) لكوبون النسبة');
      return;
    }
    if (targetMode === 'specific' && phones.length === 0) {
      alert('اختر زبوناً واحداً على الأقل من القائمة، أو اختر «الجميع»');
      return;
    }
    const customUses = Math.floor(Number(usesStr));
    if (usesMode === 'custom' && !(customUses >= 1 && customUses <= 10000)) {
      alert('أدخل عدد مرات الاستخدام لكل راكب (من 1 إلى 10000)');
      return;
    }
    const body: Record<string, unknown> = {
      code,
      amount,
      type: discType,
      max_discount: discType === 'Percentage' ? maxDiscount : null,
      unlimited_uses: usesMode === 'unlimited',
      max_uses_per_user:
        usesMode === 'unlimited' ? null : usesMode === 'once' ? 1 : customUses,
      target_all: targetMode === 'all',
      target_phones: targetMode === 'all' ? null : phones,
    };
    setCreating(true);
    try {
      const { res, data: j } = await postJson<Record<string, unknown>>(
        API.discountsStore,
        body,
      );
      if (res.ok && j.success !== false) {
        setShow(false);
        resetModal();
        await load();
        alert('أُضيف الكوبون');
      } else {
        alert(String(j.message ?? formatApiFailure(j, JSON.stringify(j))));
      }
    } finally {
      setCreating(false);
    }
  }

  function valueLabel(d: Record<string, unknown>): string {
    const num = (v: unknown) => {
      const n = Number(v ?? 0);
      return Number.isFinite(n) ? n.toLocaleString('en-US', { maximumFractionDigits: 2 }) : String(v);
    };
    if (String(d.type) === 'Fixed') return `خصم ${num(d.amount)} ل.س`;
    const max = Number(d.max_discount ?? 0);
    return max > 0
      ? `خصم ${num(d.amount)}٪ — حد أقصى ${num(max)} ل.س`
      : `خصم ${num(d.amount)}٪ — بدون حد أقصى`;
  }

  function usesBadge(d: Record<string, unknown>): string {
    const limit = usesLimitOf(d);
    return limit === null ? 'استخدام غير محدود لكل راكب' : `${timesLabel(limit)} لكل راكب`;
  }

  async function editUses(d: Record<string, unknown>) {
    const id = parseInt(String(d.id ?? 0), 10);
    if (!(id > 0)) return;
    const current = usesLimitOf(d);
    const input = window.prompt(
      `كم مرة يستطيع الراكب الواحد استخدام الكوبون «${String(d.code ?? '')}»؟\nاكتب رقماً (1 = مرة واحدة)، أو 0 لغير محدود.`,
      current === null ? '0' : String(current),
    );
    if (input === null) return;
    const n = Math.floor(Number(input.trim()));
    if (!Number.isFinite(n) || n < 0 || n > 10000) {
      alert('أدخل رقماً من 0 إلى 10000');
      return;
    }
    setSavingUsesId(id);
    try {
      const { res, data: j } = await postJson<Record<string, unknown>>(API.discountsUpdate(id), {
        unlimited_uses: n === 0,
        max_uses_per_user: n === 0 ? null : n,
      });
      if (res.ok && j.success !== false) {
        await load();
      } else {
        alert(String(j.message ?? formatApiFailure(j, JSON.stringify(j))));
      }
    } finally {
      setSavingUsesId(null);
    }
  }

  function audienceLabel(d: Record<string, unknown>): string {
    const phones = d.target_phones;
    if (Array.isArray(phones) && phones.length > 0) {
      return `مخصص لـ ${phones.length} زبون`;
    }
    return 'لجميع الزبائن';
  }

  const selectedCount = Object.keys(selected).length;

  const previewText = (() => {
    const fmt = (n: number) => n.toLocaleString('en-US', { maximumFractionDigits: 2 });
    const amount = Number(amountStr);
    const sample = 200;
    if (discType === 'Fixed') {
      if (!(amount > 0)) return 'أدخل مبلغ الخصم — إن كانت الأجرة أقل منه تصبح الرحلة مجانية.';
      const off = Math.min(amount, sample);
      return (
        <>
          رحلة بـ <b>{fmt(sample)} ل.س</b> ← خصم <b>{fmt(off)} ل.س</b> ويدفع الزبون{' '}
          <b>{fmt(sample - off)} ل.س</b>. لا يُخصم أكثر من الأجرة.
        </>
      );
    }
    const max = Number(maxStr);
    if (!(amount > 0) || !(max > 0)) {
      return 'أدخل النسبة وأقصى مبلغ — مثال 30٪ بحد 30 ل.س: رحلة بـ 200 يُخصم منها 30 فقط (وليس 60).';
    }
    const raw = (sample * Math.min(amount, 100)) / 100;
    const off = Math.min(raw, max);
    return (
      <>
        رحلة بـ <b>{fmt(sample)} ل.س</b> ← {fmt(amount)}٪ = {fmt(raw)}
        {raw > max ? <> لكن الحد الأقصى <b>{fmt(max)}</b></> : null} ← خصم <b>{fmt(off)} ل.س</b>{' '}
        ويدفع الزبون <b>{fmt(sample - off)} ل.س</b>.
      </>
    );
  })();

  return (
    <div className="page-pad">
      <PageHeader
        title="الخصومات"
        subtitle="إنشاء كوبونات للجميع أو لزبائن محددين من القائمة، وإشعارهم."
        onRefresh={() => void load()}
        actions={
          <button
            type="button"
            className="btn-primary"
            onClick={() => {
              resetModal();
              setShow(true);
            }}
          >
            كوبون جديد
          </button>
        }
      />
      {err && <p className="text-err">{err}</p>}
      <div className="card-list">
        {rows.map((d) => {
          const id = parseInt(String(d.id ?? 0), 10);
          return (
            <div key={id} className="card">
              <div className="row-between">
                <div>
                  <div className="card-title" style={{ letterSpacing: 0.5 }}>
                    {String(d.code)}
                  </div>
                  <div className="row-gap" style={{ gap: 6, flexWrap: 'wrap', marginTop: 6 }}>
                    <span
                      className="coupon-badge"
                      data-kind={String(d.type) === 'Fixed' ? 'fixed' : 'pct'}
                    >
                      {valueLabel(d)}
                    </span>
                    <span className="coupon-badge" data-kind="aud">
                      {audienceLabel(d)}
                    </span>
                    <span className="coupon-badge" data-kind="uses">
                      🔁 {usesBadge(d)}
                    </span>
                    {d.usage_count !== undefined && (
                      <span className="coupon-badge" data-kind="count">
                        استُخدم {Number(d.usage_count ?? 0).toLocaleString('en-US')} مرة
                      </span>
                    )}
                  </div>
                  {Array.isArray(d.target_phones) && d.target_phones.length > 0 && (
                    <pre className="card-sub" style={{ marginTop: 6 }}>
                      {(d.target_phones as unknown[]).slice(0, 8).join(' · ')}
                      {d.target_phones.length > 8 ? ' …' : ''}
                    </pre>
                  )}
                </div>
                {id > 0 && (
                  <div className="row-gap" style={{ flexWrap: 'wrap', justifyContent: 'flex-end' }}>
                    <button
                      type="button"
                      className="btn-ghost"
                      disabled={savingUsesId === id || deletingId === id}
                      onClick={() => void editUses(d)}
                    >
                      {savingUsesId === id ? 'جاري الحفظ…' : 'عدد مرات الاستخدام'}
                    </button>
                    <button
                      type="button"
                      className="btn-ghost"
                      disabled={deletingId === id}
                      onClick={() => void notify(id)}
                    >
                      إشعار المستهدفين
                    </button>
                    <button
                      type="button"
                      className="btn-warn"
                      disabled={deletingId === id}
                      onClick={() => void remove(id, String(d.code ?? ''))}
                    >
                      {deletingId === id ? 'جاري الحذف…' : 'حذف'}
                    </button>
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {show && (
        <ModalPortal
          onClose={() => {
            setShow(false);
            resetModal();
          }}
        >
          <div
            className="modal"
            role="dialog"
            onClick={(ev) => ev.stopPropagation()}
            dir="rtl"
            style={{ maxWidth: 520, maxHeight: '90vh', overflowY: 'auto' }}
          >
            <h3>كوبون جديد</h3>
            <form onSubmit={(e) => void create(e)}>
              <label>
                كود الكوبون
                <input
                  name="code"
                  required
                  placeholder="مثال: SYRIA30"
                  style={{ textTransform: 'uppercase', letterSpacing: 1, fontWeight: 700 }}
                />
              </label>

              <div className="opt-section-title">نوع الخصم</div>
              <div className="opt-grid">
                <label className={`opt-card${discType === 'Percentage' ? ' active' : ''}`}>
                  <input
                    type="radio"
                    name="disc_type"
                    checked={discType === 'Percentage'}
                    onChange={() => setDiscType('Percentage')}
                  />
                  <span className="opt-icon">%</span>
                  <span>
                    <span className="opt-title">نسبة مئوية</span>
                    <span className="opt-sub">نسبة من الأجرة مع حد أقصى بالليرة</span>
                  </span>
                </label>
                <label className={`opt-card${discType === 'Fixed' ? ' active' : ''}`}>
                  <input
                    type="radio"
                    name="disc_type"
                    checked={discType === 'Fixed'}
                    onChange={() => setDiscType('Fixed')}
                  />
                  <span className="opt-icon" style={{ fontSize: '0.78rem' }}>ل.س</span>
                  <span>
                    <span className="opt-title">مبلغ ثابت</span>
                    <span className="opt-sub">قيمة محددة تُخصم من الأجرة</span>
                  </span>
                </label>
              </div>

              {discType === 'Percentage' ? (
                <div className="field-row">
                  <label>
                    نسبة الخصم
                    <div className="input-affix">
                      <input
                        key="pct"
                        name="amount"
                        type="number"
                        inputMode="decimal"
                        min={0.01}
                        max={100}
                        step="0.01"
                        required
                        placeholder="30"
                        value={amountStr}
                        onChange={(e) => setAmountStr(e.target.value)}
                      />
                      <span className="affix">%</span>
                    </div>
                  </label>
                  <label>
                    أقصى مبلغ للخصم
                    <div className="input-affix">
                      <input
                        name="max_discount"
                        type="number"
                        inputMode="decimal"
                        min={0.01}
                        step="0.01"
                        required
                        placeholder="30"
                        value={maxStr}
                        onChange={(e) => setMaxStr(e.target.value)}
                      />
                      <span className="affix">ل.س</span>
                    </div>
                  </label>
                </div>
              ) : (
                <label>
                  مبلغ الخصم
                  <div className="input-affix">
                    <input
                      key="fixed"
                      name="amount"
                      type="number"
                      inputMode="decimal"
                      min={0.01}
                      step="0.01"
                      required
                      placeholder="50"
                      value={amountStr}
                      onChange={(e) => setAmountStr(e.target.value)}
                    />
                    <span className="affix">ل.س</span>
                  </div>
                </label>
              )}

              <div className="discount-preview">
                <span style={{ fontSize: '1.2rem' }}>💡</span>
                <span>{previewText}</span>
              </div>

              <div className="opt-section-title">عدد مرات الاستخدام لكل راكب</div>
              <div className="opt-grid opt-grid-3">
                <label className={`opt-card${usesMode === 'once' ? ' active' : ''}`}>
                  <input
                    type="radio"
                    name="uses_mode"
                    checked={usesMode === 'once'}
                    onChange={() => setUsesMode('once')}
                  />
                  <span className="opt-icon">1</span>
                  <span>
                    <span className="opt-title">مرة واحدة</span>
                    <span className="opt-sub">الافتراضي</span>
                  </span>
                </label>
                <label className={`opt-card${usesMode === 'custom' ? ' active' : ''}`}>
                  <input
                    type="radio"
                    name="uses_mode"
                    checked={usesMode === 'custom'}
                    onChange={() => setUsesMode('custom')}
                  />
                  <span className="opt-icon">#</span>
                  <span>
                    <span className="opt-title">عدد محدد</span>
                    <span className="opt-sub">تحدده أنت</span>
                  </span>
                </label>
                <label className={`opt-card${usesMode === 'unlimited' ? ' active' : ''}`}>
                  <input
                    type="radio"
                    name="uses_mode"
                    checked={usesMode === 'unlimited'}
                    onChange={() => setUsesMode('unlimited')}
                  />
                  <span className="opt-icon">∞</span>
                  <span>
                    <span className="opt-title">غير محدود</span>
                    <span className="opt-sub">طوال الصلاحية</span>
                  </span>
                </label>
              </div>
              {usesMode === 'custom' && (
                <label>
                  كم مرة يستطيع الراكب الواحد استخدامه؟
                  <div className="input-affix">
                    <input
                      type="number"
                      inputMode="numeric"
                      min={1}
                      max={10000}
                      step={1}
                      required
                      placeholder="3"
                      value={usesStr}
                      onChange={(e) => setUsesStr(e.target.value)}
                    />
                    <span className="affix">مرة</span>
                  </div>
                </label>
              )}
              <p className="text-muted small" style={{ marginTop: 4 }}>
                {usesMode === 'unlimited'
                  ? 'يستطيع الراكب استخدام الكوبون في كل رحلة طالما الكوبون فعّال.'
                  : `يستطيع كل راكب استخدام الكوبون ${
                      usesMode === 'once'
                        ? 'مرة واحدة'
                        : timesLabel(Math.max(1, Math.floor(Number(usesStr) || 1)))
                    } فقط. الرحلة الملغاة لا تُحسب.`}
              </p>

              <div className="opt-section-title">المستهدفون</div>
              <div className="opt-grid">
                <label className={`opt-card${targetMode === 'all' ? ' active' : ''}`}>
                  <input
                    type="radio"
                    name="audience"
                    checked={targetMode === 'all'}
                    onChange={() => setTargetMode('all')}
                  />
                  <span className="opt-icon">👥</span>
                  <span>
                    <span className="opt-title">جميع الزبائن</span>
                    <span className="opt-sub">أي زبون يمكنه استخدامه</span>
                  </span>
                </label>
                <label className={`opt-card${targetMode === 'specific' ? ' active' : ''}`}>
                  <input
                    type="radio"
                    name="audience"
                    checked={targetMode === 'specific'}
                    onChange={() => setTargetMode('specific')}
                  />
                  <span className="opt-icon">🎯</span>
                  <span>
                    <span className="opt-title">زبائن محددون</span>
                    <span className="opt-sub">تختارهم من القائمة</span>
                  </span>
                </label>
              </div>

              {targetMode === 'specific' && (
                <div style={{ marginBottom: 12 }}>
                  <div
                    className="row-between wrap"
                    style={{ gap: 8, alignItems: 'center', marginBottom: 8 }}
                  >
                    <strong style={{ fontSize: 13 }}>
                      المختارون: {selectedCount}
                    </strong>
                    {selectedCount > 0 && (
                      <button
                        type="button"
                        className="btn-ghost"
                        style={{ fontSize: 12, padding: '4px 8px' }}
                        onClick={() => setSelected({})}
                      >
                        مسح الاختيار
                      </button>
                    )}
                  </div>
                  {selectedCount > 0 && (
                    <div
                      style={{
                        display: 'flex',
                        flexWrap: 'wrap',
                        gap: 6,
                        marginBottom: 10,
                      }}
                    >
                      {Object.entries(selected).map(([phone, name]) => (
                        <button
                          key={phone}
                          type="button"
                          className="btn-ghost"
                          style={{ fontSize: 12, padding: '4px 8px' }}
                          title="إزالة"
                          onClick={() =>
                            setSelected((prev) => {
                              const next = { ...prev };
                              delete next[phone];
                              return next;
                            })
                          }
                        >
                          {name} · {phone} ×
                        </button>
                      ))}
                    </div>
                  )}
                  <label>
                    بحث بالاسم أو الرقم
                    <input
                      value={custSearch}
                      onChange={(e) => setCustSearch(e.target.value)}
                      placeholder="مثال: أحمد، 09…"
                    />
                  </label>
                  {custErr && <p className="text-err">{custErr}</p>}
                  {custLoading && <p className="text-muted">جاري تحميل الزبائن…</p>}
                  <div
                    style={{
                      maxHeight: 260,
                      overflowY: 'auto',
                      border: '1px solid #dde3f0',
                      borderRadius: 12,
                      marginTop: 8,
                    }}
                  >
                    {customers.map((c) => {
                      const checked = Boolean(selected[c.phone]);
                      return (
                        <label
                          key={`${c.id}-${c.phone}`}
                          className={`cust-pick-row${checked ? ' checked' : ''}`}
                        >
                          <input
                            type="checkbox"
                            checked={checked}
                            onChange={() => toggleCustomer(c)}
                          />
                          <span style={{ flex: 1 }}>
                            <strong>{c.name}</strong>
                            <div className="text-muted" style={{ fontSize: 12 }}>
                              {c.phone}
                            </div>
                          </span>
                        </label>
                      );
                    })}
                    {!custLoading && customers.length === 0 && (
                      <p className="text-muted" style={{ padding: 12, margin: 0 }}>
                        لا زبائن في هذه الصفحة
                      </p>
                    )}
                  </div>
                  <div
                    className="row-between wrap"
                    style={{ gap: 8, marginTop: 8, alignItems: 'center' }}
                  >
                    <span className="text-muted" style={{ fontSize: 12 }}>
                      صفحة {custPage} / {custLastPage} · الإجمالي {custTotal}
                    </span>
                    <div className="row-gap" style={{ gap: 6 }}>
                      <button
                        type="button"
                        className="btn-ghost"
                        disabled={custPage <= 1 || custLoading}
                        onClick={() => setCustPage((p) => Math.max(1, p - 1))}
                      >
                        السابق
                      </button>
                      <button
                        type="button"
                        className="btn-ghost"
                        disabled={custPage >= custLastPage || custLoading}
                        onClick={() =>
                          setCustPage((p) => Math.min(custLastPage, p + 1))
                        }
                      >
                        التالي
                      </button>
                    </div>
                  </div>
                </div>
              )}

              <p className="text-muted small" style={{ marginTop: 8 }}>
                عند الإشعار يُرسل للمستهدفين فقط. الكوبون المخصص لا يعمل إلا لأرقامهم.
              </p>
              <div className="row-gap" style={{ marginTop: 12 }}>
                <button
                  type="button"
                  className="btn-ghost"
                  onClick={() => {
                    setShow(false);
                    resetModal();
                  }}
                >
                  إلغاء
                </button>
                <button type="submit" className="btn-primary" disabled={creating}>
                  حفظ
                </button>
              </div>
            </form>
          </div>
        </ModalPortal>
      )}
    </div>
  );
}
