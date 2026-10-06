import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { API } from '../api/endpoints';
import { fetchJsonAuth } from '../api/http';
import {
  formatDateLatin,
  formatDateTimeLatin,
  formatNumberLatin,
} from '../util/latinDigits';

function dashCount(v: unknown): string {
  if (v == null) return '—';
  if (typeof v === 'number') return Number.isInteger(v) ? String(v) : String(v);
  if (typeof v === 'string') {
    if (!v) return '—';
    const n = Number(v);
    return Number.isNaN(n) ? v : String(n);
  }
  return String(v);
}

function dashMoney(v: unknown): string {
  if (v == null) return '—';
  if (typeof v === 'number' || typeof v === 'string') return String(v);
  return String(v);
}

function parseMoney(v: unknown): number {
  if (typeof v === 'number' && !Number.isNaN(v)) return v;
  const s = String(v ?? '')
    .replace(/,/g, '')
    .trim();
  if (!s) return 0;
  const n = parseFloat(s);
  return Number.isNaN(n) ? 0 : n;
}

function formatTripDate(v: unknown): string {
  const s = String(v ?? '').trim();
  if (!s) return '—';
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return s.length > 18 ? s.slice(0, 18) : s;
  return formatDateTimeLatin(d);
}

type RevenueRow = {
  id: number;
  driver: string;
  cost: number;
  atLabel: string;
  sortMs: number;
  pathLabel: string;
  pathNote: string;
};

type ChartPoint = {
  date?: string;
  label: string;
  amount?: number;
  count?: number;
  customers?: number;
  drivers?: number;
};

function trendBadge(current: number, previous: number): {
  text: string;
  tone: 'up' | 'down' | 'flat';
} {
  if (previous === 0 && current === 0) return { text: '0%', tone: 'flat' };
  if (previous === 0) return { text: '+100%', tone: 'up' };
  const pct = ((current - previous) / Math.abs(previous)) * 100;
  const rounded = Math.round(pct * 10) / 10;
  if (Math.abs(rounded) < 0.05) return { text: '0%', tone: 'flat' };
  if (rounded > 0) return { text: `+${rounded}%`, tone: 'up' };
  return { text: `${rounded}%`, tone: 'down' };
}

export function DashboardPage() {
  const nav = useNavigate();
  const [d, setD] = useState<Record<string, unknown> | null>(null);
  const [err, setErr] = useState('');
  const [revModal, setRevModal] = useState<{
    loading: boolean;
    err: string;
    rows: RevenueRow[];
    title: string;
    officialTotal: number;
    sumListed: number;
    rangeLabel: string;
    note: string;
  } | null>(null);

  const load = useCallback(async () => {
    setErr('');
    try {
      const { res, data: j } = await fetchJsonAuth(API.dashboardSummary);
      if (!res.ok || j.success !== true) {
        const raw = String(j.message ?? res.statusText ?? '');
        if (/server error/i.test(raw) || res.status >= 500) {
          throw new Error(
            raw.includes('تعذر')
              ? raw
              : 'تعذر تحميل لوحة التحكم من الخادم. ارفع ملفات API المحدّثة ثم نفّذ php artisan migrate.',
          );
        }
        throw new Error(raw || 'تعذر تحميل لوحة التحكم');
      }
      setD(j.data as Record<string, unknown>);
    } catch (e) {
      setErr(String(e));
      setD(null);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const openRevenueDetail = useCallback(
    async (opts: {
      officialTotal: number;
      fromMs: number;
      toMs: number;
      title: string;
      rangeLabel: string;
      billingFilter?: 'all' | 'app' | 'free_meter';
    }) => {
      const {
        officialTotal,
        fromMs,
        toMs,
        title,
        rangeLabel,
        billingFilter = 'all',
      } = opts;

      setRevModal({
        loading: true,
        err: '',
        rows: [],
        officialTotal,
        sumListed: 0,
        rangeLabel,
        title,
        note: '',
      });

      try {
        const fromDate = new Date(fromMs).toISOString().slice(0, 10);
        const toDate = new Date(toMs).toISOString().slice(0, 10);
        const q = new URLSearchParams({
          from_date: fromDate,
          to_date: toDate,
          billing: billingFilter,
        });
        const { res, data: j } = await fetchJsonAuth(
          `${API.dashboardRevenueTrips}?${q}`,
        );
        if (!res.ok || j.success !== true) {
          throw new Error(String(j.message ?? res.statusText));
        }
        const payload = (j.data as Record<string, unknown>) ?? {};
        const trips = Array.isArray(payload.trips)
          ? (payload.trips as Record<string, unknown>[])
          : [];
        const rows: RevenueRow[] = trips.map((t) => ({
          id: Number(t.id ?? 0),
          driver: String(t.driver ?? '—'),
          cost: parseMoney(t.cost),
          atLabel: String(t.at_label ?? formatTripDate(t.at)),
          sortMs: Number(t.sort_ms ?? 0),
          pathLabel: String(t.path_label ?? '—'),
          pathNote:
            billingFilter === 'free_meter'
              ? 'عداد حر'
              : billingFilter === 'app'
                ? 'طلب تطبيق'
                : String(t.billing_kind ?? ''),
        }));
        const sumListed = parseMoney(payload.sum ?? rows.reduce((s, r) => s + r.cost, 0));
        const filterNote =
          billingFilter === 'free_meter'
            ? 'رحلات العداد الحر المكتملة فقط في هذا النطاق.'
            : billingFilter === 'app'
              ? 'رحلات طلب التطبيق المكتملة فقط — بدون العداد الحر.'
              : 'رحلات «مكتملة» فقط حسب وقت الإنهاء.';
        setRevModal({
          loading: false,
          err: '',
          rows,
          officialTotal,
          sumListed,
          rangeLabel,
          title,
          note: filterNote,
        });
      } catch (e) {
        setRevModal({
          loading: false,
          err: String(e),
          rows: [],
          officialTotal,
          sumListed: 0,
          rangeLabel,
          title,
          note: '',
        });
      }
    },
    [],
  );

  const openLast30Revenue = useCallback(
    (official30: number) => {
      const cutoffMs = Date.now() - 30 * 86400000;
      void openRevenueDetail({
        officialTotal: official30,
        fromMs: cutoffMs,
        toMs: Date.now(),
        title: 'رحلات إيراد آخر 30 يوماً',
        rangeLabel: `${formatDateLatin(new Date(cutoffMs))} — ${formatDateLatin(new Date())}`,
        billingFilter: 'all',
      });
    },
    [openRevenueDetail],
  );

  const openTodayRevenue = useCallback(
    (officialToday: number) => {
      const start = new Date();
      start.setHours(0, 0, 0, 0);
      const end = new Date();
      end.setHours(23, 59, 59, 999);
      void openRevenueDetail({
        officialTotal: officialToday,
        fromMs: start.getTime(),
        toMs: end.getTime(),
        title: 'رحلات إيرادات اليوم',
        rangeLabel: formatDateLatin(start),
        billingFilter: 'all',
      });
    },
    [openRevenueDetail],
  );

  const openTodayFinishedTrips = useCallback(
    (count: number, billingFilter: 'app' | 'free_meter') => {
      const start = new Date();
      start.setHours(0, 0, 0, 0);
      const end = new Date();
      end.setHours(23, 59, 59, 999);
      void openRevenueDetail({
        officialTotal: count,
        fromMs: start.getTime(),
        toMs: end.getTime(),
        title:
          billingFilter === 'free_meter'
            ? 'رحلات العداد الحر'
            : 'رحلات مُنجَزة اليوم (طلب التطبيق)',
        rangeLabel: formatDateLatin(start),
        billingFilter,
      });
    },
    [openRevenueDetail],
  );

  const charts = useMemo(() => {
    const c = (d?.charts as Record<string, unknown> | undefined) ?? {};
    const revenue = (c.revenue_daily as ChartPoint[]) ?? [];
    const customers = (c.customers_daily as ChartPoint[]) ?? [];
    const drivers = (c.drivers_daily as ChartPoint[]) ?? [];
    const trips = (c.trips_daily as ChartPoint[]) ?? [];
    const growth = customers.map((row, i) => ({
      label: row.label,
      customers: Number(row.count ?? 0),
      drivers: Number(drivers[i]?.count ?? 0),
    }));
    return { revenue, customers, drivers, trips, growth };
  }, [d]);

  if (err && !d) {
    return (
      <div className="page-pad">
        <p className="text-err">{err}</p>
        <button type="button" className="btn-primary" onClick={() => void load()}>
          إعادة المحاولة
        </button>
      </div>
    );
  }
  if (!d) {
    return (
      <div className="page-center">
        <div className="spinner" />
      </div>
    );
  }

  // المقارنة مع أمس حتى نفس الساعة (الحقول القديمة = أمس كاملاً كاحتياط).
  const revToday = parseMoney(d.revenue_today);
  const revYday = parseMoney(d.revenue_yesterday_same_time ?? d.revenue_yesterday);
  const revTrend = trendBadge(revToday, revYday);
  const custTrend = trendBadge(
    Number(d.customers_new_today ?? 0),
    Number(d.customers_new_yesterday_same_time ?? d.customers_new_yesterday ?? 0),
  );
  const drvTrend = trendBadge(
    Number(d.drivers_new_today ?? 0),
    Number(d.drivers_new_yesterday_same_time ?? d.drivers_new_yesterday ?? 0),
  );
  const trendTitle = 'مقارنة باليوم السابق حتى نفس الساعة';
  const onlineHint =
    d.drivers_online_available != null
      ? `متصل الآن: ${dashCount(d.drivers_online ?? 0)} (متاح ${dashCount(d.drivers_online_available)} · في رحلة ${dashCount(d.drivers_online_on_trip ?? 0)} · متجه للراكب ${dashCount(d.drivers_online_to_pickup ?? 0)})`
      : `متصل الآن: ${dashCount(d.drivers_online ?? 0)}`;
  const runningOffline = Number(d.requests_running_driver_offline ?? 0);

  const heroKpis = [
    {
      key: 'rev',
      label: 'إيرادات اليوم',
      value: `${dashMoney(d.revenue_today)} ل.س`,
      icon: '💰',
      tone: 'gold' as const,
      trend: revTrend,
      onClick: () => void openTodayRevenue(revToday),
    },
    {
      key: 'cust',
      label: 'إجمالي الزبائن',
      value: dashCount(d.customers_total),
      icon: '👥',
      tone: 'blue' as const,
      trend: custTrend,
      hint: `جدد اليوم: ${dashCount(d.customers_new_today ?? 0)}`,
    },
    {
      key: 'drv',
      label: 'إجمالي السائقين',
      value: dashCount(d.drivers_total),
      icon: '🚕',
      tone: 'navy' as const,
      trend: drvTrend,
      hint: onlineHint,
      onClick: () => nav('/map'),
    },
    {
      key: 'run',
      label: 'رحلات قيد التنفيذ',
      value: dashCount(d.requests_running),
      icon: '🚀',
      tone: 'green' as const,
      trend: { text: `${dashCount(d.requests_pending)} انتظار`, tone: 'flat' as const },
      hint:
        runningOffline > 0
          ? `منها ${dashCount(runningOffline)} سائقها غير متصل (غالباً عداد لم يُنهَ)`
          : undefined,
    },
  ];

  const secondaryCards: {
    t: string;
    v: string;
    tone: 'navy' | 'gold' | 'green' | 'blue' | 'warn' | 'rose';
    icon: string;
    onOpen?: () => void;
    hint?: string;
  }[] = [
    {
      t: 'إيراد آخر 30 يوماً',
      v: `${dashMoney(d.revenue_last_30_days)} ل.س`,
      tone: 'gold',
      icon: '📈',
      onOpen: () => void openLast30Revenue(parseMoney(d.revenue_last_30_days)),
      hint: 'اضغط للتفاصيل',
    },
    {
      t: 'الطلبات النشطة',
      v: dashCount(d.requests_active_total),
      tone: 'navy',
      icon: '📋',
    },
    {
      t: 'بانتظار التوجيه',
      v: dashCount(d.requests_pending),
      tone: 'rose',
      icon: '⏳',
    },
    {
      t: 'قبل التنفيذ (محجوز/وصل)',
      v: dashCount(d.unfinished_bookings),
      tone: 'blue',
      icon: '📍',
    },
    {
      t: 'منجَزة اليوم (تطبيق)',
      v: dashCount(d.requests_finished_today),
      tone: 'green',
      icon: '✅',
      onOpen: () =>
        void openTodayFinishedTrips(
          parseInt(String(d.requests_finished_today ?? 0), 10) || 0,
          'app',
        ),
      hint: 'اضغط للتفاصيل',
    },
    {
      t: 'عداد حر اليوم',
      v: dashCount(d.free_meter_finished_today),
      tone: 'blue',
      icon: '⏱️',
      onOpen: () =>
        void openTodayFinishedTrips(
          parseInt(String(d.free_meter_finished_today ?? 0), 10) || 0,
          'free_meter',
        ),
      hint: 'اضغط للتفاصيل',
    },
    {
      t: 'بلاغات SOS نشطة',
      v: dashCount(d.active_sos),
      tone: 'warn',
      icon: '🆘',
      onOpen:
        parseInt(String(d.active_sos ?? 0), 10) > 0
          ? async () => {
              try {
                const { data: j } = await fetchJsonAuth(API.emergencyActive);
                const ok = j.state === true || j.success === true;
                const list = (ok ? (j.data as unknown[]) : []) ?? [];
                const first = list[0] as Record<string, unknown> | undefined;
                const role = String(first?.role ?? 'driver').toLowerCase();
                if (role === 'customer') {
                  const key = String(
                    first?.redisKey ??
                      first?.redis_key ??
                      (first?.customerId || first?.userId
                        ? `c:${first?.customerId ?? first?.userId}`
                        : ''),
                  );
                  nav(key ? `/map?sosKey=${encodeURIComponent(key)}` : '/sos');
                  return;
                }
                const did = parseInt(
                  String(first?.driverId ?? first?.driver_id ?? 0),
                  10,
                );
                nav(did > 0 ? `/map?sosDriver=${did}` : '/map');
              } catch {
                nav('/map');
              }
            }
          : undefined,
      hint:
        parseInt(String(d.active_sos ?? 0), 10) > 0
          ? 'افتح الخريطة'
          : undefined,
    },
  ];

  const tooltipStyle = {
    background: '#fff',
    border: '1px solid rgba(17,33,91,0.12)',
    borderRadius: 10,
    fontSize: 12,
  };

  return (
    <div className="page-pad dash-page">
      <div className="page-hero">
        <div>
          <p className="page-hero-brand">GS TAXI</p>
          <h2>لوحة التحكم</h2>
          <p>نظرة حية على الإيرادات والزبائن والسائقين والعمليات.</p>
        </div>
        <button type="button" className="btn-ghost" onClick={() => void load()}>
          تحديث البيانات
        </button>
      </div>

      <div className="dash-kpi-grid">
        {heroKpis.map((k) => (
          <button
            key={k.key}
            type="button"
            className={`dash-kpi dash-kpi-${k.tone}${k.onClick ? ' is-clickable' : ''}`}
            onClick={() => k.onClick?.()}
          >
            <div className="dash-kpi-top">
              <span className="dash-kpi-icon" aria-hidden>
                {k.icon}
              </span>
              <span
                className={`dash-kpi-trend tone-${k.trend.tone}`}
                title={k.key === 'run' ? undefined : trendTitle}
              >
                {k.trend.text}
              </span>
            </div>
            <div className="dash-kpi-label">{k.label}</div>
            <div className="dash-kpi-value">{k.value}</div>
            {k.hint ? <div className="dash-kpi-hint">{k.hint}</div> : null}
          </button>
        ))}
      </div>

      <div className="dash-charts-grid">
        <section className="dash-chart-card">
          <header>
            <h3>حركة الأرباح</h3>
            <p>إيراد الرحلات المكتملة — آخر 14 يوماً</p>
          </header>
          <div className="dash-chart-body">
            {charts.revenue.length === 0 ? (
              <p className="text-muted">لا بيانات رسم بعد رفع API المحدّث.</p>
            ) : (
              <ResponsiveContainer width="100%" height={260}>
                <AreaChart data={charts.revenue} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="revFill" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#11215b" stopOpacity={0.28} />
                      <stop offset="100%" stopColor="#11215b" stopOpacity={0.02} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(17,33,91,0.08)" />
                  <XAxis dataKey="label" tick={{ fontSize: 11 }} />
                  <YAxis
                    tick={{ fontSize: 11 }}
                    width={56}
                    tickFormatter={(v) =>
                      v >= 1000 ? `${Math.round(v / 1000)}k` : String(v)
                    }
                  />
                  <Tooltip
                    contentStyle={tooltipStyle}
                    formatter={(v: number) => [`${formatNumberLatin(v)} ل.س`, 'الإيراد']}
                  />
                  <Area
                    type="monotone"
                    dataKey="amount"
                    name="الإيراد"
                    stroke="#11215b"
                    strokeWidth={2.5}
                    fill="url(#revFill)"
                    dot={{ r: 3, fill: '#ffc107', stroke: '#11215b' }}
                  />
                </AreaChart>
              </ResponsiveContainer>
            )}
          </div>
        </section>

        <section className="dash-chart-card">
          <header>
            <h3>نمو الزبائن والسائقين</h3>
            <p>تسجيلات جديدة يومياً — آخر 14 يوماً</p>
          </header>
          <div className="dash-chart-body">
            {charts.growth.length === 0 ? (
              <p className="text-muted">لا بيانات رسم بعد رفع API المحدّث.</p>
            ) : (
              <ResponsiveContainer width="100%" height={260}>
                <BarChart data={charts.growth} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(17,33,91,0.08)" />
                  <XAxis dataKey="label" tick={{ fontSize: 11 }} />
                  <YAxis allowDecimals={false} tick={{ fontSize: 11 }} width={36} />
                  <Tooltip contentStyle={tooltipStyle} />
                  <Legend />
                  <Bar dataKey="customers" name="زبائن جدد" fill="#1e4f9a" radius={[6, 6, 0, 0]} />
                  <Bar dataKey="drivers" name="سائقون جدد" fill="#d4a106" radius={[6, 6, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>
        </section>

        <section className="dash-chart-card dash-chart-wide">
          <header>
            <h3>الرحلات المكتملة يومياً</h3>
            <p>عدد الرحلات المنتهية التي تدخل في الإيراد</p>
          </header>
          <div className="dash-chart-body">
            {charts.trips.length === 0 ? (
              <p className="text-muted">لا بيانات رسم بعد رفع API المحدّث.</p>
            ) : (
              <ResponsiveContainer width="100%" height={240}>
                <LineChart data={charts.trips} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(17,33,91,0.08)" />
                  <XAxis dataKey="label" tick={{ fontSize: 11 }} />
                  <YAxis allowDecimals={false} tick={{ fontSize: 11 }} width={36} />
                  <Tooltip contentStyle={tooltipStyle} />
                  <Line
                    type="monotone"
                    dataKey="count"
                    name="رحلات"
                    stroke="#1b7a4b"
                    strokeWidth={2.5}
                    dot={{ r: 3, fill: '#1b7a4b' }}
                  />
                </LineChart>
              </ResponsiveContainer>
            )}
          </div>
        </section>
      </div>

      <h3 className="dash-section-title">مؤشرات إضافية</h3>
      <div className="stat-list">
        {secondaryCards.map((c) => {
          const clickable = Boolean(c.onOpen);
          return (
            <div
              key={c.t}
              className={`stat-card stat-tone-${c.tone} ${clickable ? 'stat-card-clickable' : ''}`}
              onClick={() => c.onOpen?.()}
              onKeyDown={(ev) => {
                if (!clickable) return;
                if (ev.key === 'Enter' || ev.key === ' ') {
                  ev.preventDefault();
                  c.onOpen?.();
                }
              }}
              role={clickable ? 'button' : undefined}
              tabIndex={clickable ? 0 : undefined}
              title={c.hint}
            >
              <div className="stat-card-top">
                <span className="stat-icon" aria-hidden>
                  {c.icon}
                </span>
                {clickable && <span className="stat-chip">تفاصيل</span>}
              </div>
              <span className="stat-title">{c.t}</span>
              <span className="stat-val">{c.v}</span>
              {c.hint && <span className="stat-foot">{c.hint}</span>}
            </div>
          );
        })}
      </div>

      {revModal && (
        <div
          className="modal-backdrop"
          role="presentation"
          onClick={() => setRevModal(null)}
        >
          <div
            className="modal modal-wide"
            role="dialog"
            aria-modal="true"
            aria-labelledby="rev30-title"
            onClick={(ev) => ev.stopPropagation()}
            dir="rtl"
          >
            <h3 id="rev30-title">{revModal.title}</h3>
            <p className="text-muted small" style={{ marginTop: 0 }}>
              النطاق: {revModal.rangeLabel}
            </p>
            {revModal.note && (
              <p className="text-muted small" style={{ marginTop: 6 }}>
                {revModal.note}
              </p>
            )}
            {revModal.loading && <p className="text-muted">جاري التحميل…</p>}
            {revModal.err && <p className="text-err">{revModal.err}</p>}
            {!revModal.loading && !revModal.err && revModal.rows.length === 0 && (
              <p className="text-muted">لا توجد رحلات مطابقة في هذه الفترة.</p>
            )}
            {!revModal.loading && revModal.rows.length > 0 && (
              <>
                <div style={{ overflow: 'auto', maxHeight: '55vh' }}>
                  <table className="revenue-table">
                    <thead>
                      <tr>
                        <th>الرحلة</th>
                        <th>السائق</th>
                        <th>المسار والتفاصيل المالية</th>
                        <th>التكلفة (ل.س)</th>
                        <th>وقت الإكمال</th>
                      </tr>
                    </thead>
                    <tbody>
                      {revModal.rows.map((r) => (
                        <tr key={r.id || `${r.driver}-${r.sortMs}`}>
                          <td>
                            {r.id > 0 ? (
                              <Link to={`/requests/${r.id}`}>طلب #{r.id}</Link>
                            ) : (
                              '—'
                            )}
                          </td>
                          <td>{r.driver}</td>
                          <td style={{ maxWidth: 300 }}>
                            <div style={{ fontWeight: 700 }}>{r.pathLabel}</div>
                            <div
                              className="text-muted small"
                              style={{ marginTop: 6, lineHeight: 1.4, whiteSpace: 'normal' }}
                            >
                              {r.pathNote}
                            </div>
                          </td>
                          <td>{r.cost > 0 ? formatNumberLatin(r.cost) : '—'}</td>
                          <td>{r.atLabel}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <div className="revenue-total-bar">
                  {revModal.title.includes('إيراد') ? (
                    <>
                      الإجمالي المعتمد (لوحة التحكم):{' '}
                      {formatNumberLatin(revModal.officialTotal)} ل.س
                    </>
                  ) : (
                    <>عدد الرحلات: {formatNumberLatin(revModal.rows.length)}</>
                  )}
                  <span style={{ fontWeight: 600, fontSize: '0.85rem', marginRight: 10 }}>
                    ({revModal.rows.length} رحلة مكتملة)
                  </span>
                </div>
              </>
            )}
            <div className="row-gap" style={{ marginTop: 16, justifyContent: 'flex-end' }}>
              <button type="button" className="btn-ghost" onClick={() => setRevModal(null)}>
                إغلاق
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
