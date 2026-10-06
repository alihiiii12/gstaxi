import { useMemo, useState } from 'react';
import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { API } from '../api/endpoints';
import { authHeaders } from '../api/http';
import { staffHas, useAuth } from '../auth/AuthContext';

const NAVY = '#11215b';
const AMBER = '#ffc107';

function titleFromPath(pathname: string): string {
  if (pathname === '/drivers/new') return 'إضافة سائق';
  if (/^\/drivers\/[^/]+\/edit$/.test(pathname)) return 'تعديل سائق';
  if (pathname === '/drivers') return 'سائقون';
  if (pathname === '/requests/dispatch') return 'إرسال طلب لسائق';

  const m: Record<string, string> = {
    '/dashboard': 'لوحة التحكم',
    '/discounts': 'خصومات',
    '/sos': 'SOS',
    '/requests': 'الطلبات والتتبع',
    '/customers': 'الزبائن المسجّلون',
    '/wallet-log': 'سجل محافظ الزبائن',
    '/whatsapp-broadcast': 'إعلانات واتساب',
    '/mtn-sms-broadcast': 'رسائل MTN SMS',
    '/reviews': 'رأي الراكبين بالرحلة',
    '/areas': 'مناطق إدارية',
    '/map': 'خريطة العمليات',
    '/customers-map': 'خريطة الزبائن',
    '/car-types': 'فئات السيارة',
    '/free-meter': 'العداد الحر',
    '/pricing-zones': 'مناطق التسعير',
    '/employees': 'موظفو الإدارة',
    '/password': 'تغيير كلمة المرور',
  };
  for (const [k, v] of Object.entries(m)) {
    if (pathname === k || pathname.startsWith(`${k}/`)) return v;
  }
  return 'لوحة الإدارة';
}

function navActive(pathname: string, to: string): boolean {
  if (to === '/dashboard') return pathname === '/dashboard';
  return pathname === to || pathname.startsWith(`${to}/`);
}

export function AdminLayout() {
  const { user, logout } = useAuth();
  const loc = useLocation();
  const nav = useNavigate();
  const [drawer, setDrawer] = useState(false);

  const title = useMemo(() => titleFromPath(loc.pathname), [loc.pathname]);

  if (!user) return null;

  const { roll, permissions } = user;

  async function exportCsv(kind: 'customers' | 'drivers') {
    try {
      const res = await fetch(
        `${API.adminExportUsersCsv}?${new URLSearchParams({ kind })}`,
        { headers: authHeaders() },
      );
      const text = await res.text();
      const ct = (res.headers.get('content-type') ?? '').toLowerCase();
      if (!res.ok || !ct.includes('csv')) {
        alert(text.length > 400 ? `${text.slice(0, 400)}…` : text);
        return;
      }
      const blob = new Blob([text], { type: 'text/csv;charset=utf-8' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `export_${kind}.csv`;
      a.click();
      URL.revokeObjectURL(a.href);
    } catch (e) {
      alert(String(e));
    }
  }

  async function financialPdf() {
    const defFrom = new Date(Date.now() - 30 * 864e5).toISOString().slice(0, 10);
    const defTo = new Date().toISOString().slice(0, 10);
    const from = window.prompt('من تاريخ (yyyy-MM-dd)', defFrom);
    if (!from) return;
    const to = window.prompt('إلى تاريخ (yyyy-MM-dd)', defTo);
    if (!to) return;
    const url = API.financialReport(from.trim(), to.trim(), 'pdf');
    const res = await fetch(url, { headers: authHeaders() });
    const buf = await res.arrayBuffer();
    if (!res.ok || buf.byteLength < 100) {
      alert('تعذر تنزيل PDF');
      return;
    }
    const blob = new Blob([buf], { type: 'application/pdf' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `financial_${from}_${to}.pdf`;
    a.click();
    URL.revokeObjectURL(a.href);
  }

  function go(path: string) {
    setDrawer(false);
    nav(path);
  }

  function NavBtn({ to, children }: { to: string; children: string }) {
    return (
      <button
        type="button"
        className={navActive(loc.pathname, to) ? 'drawer-nav-active' : undefined}
        onClick={() => go(to)}
      >
        {children}
      </button>
    );
  }

  return (
    <div className={`admin-root${drawer ? ' drawer-is-open' : ''}`} dir="rtl">
      {drawer && (
        <button
          type="button"
          className="drawer-scrim"
          aria-label="إغلاق القائمة"
          onClick={() => setDrawer(false)}
        />
      )}
      <aside className={`drawer ${drawer ? 'drawer-open' : ''}`} aria-hidden={!drawer}>
        <div className="drawer-head">
          <div className="drawer-head-row">
            <div>
              <div className="drawer-logo">GS TAXI</div>
              <div className="drawer-sub">لوحة الإدارة</div>
              <div className="drawer-roll">{roll}</div>
            </div>
            <button
              type="button"
              className="drawer-close"
              aria-label="إغلاق"
              onClick={() => setDrawer(false)}
            >
              ✕
            </button>
          </div>
        </div>
        <nav className="drawer-nav">
          {staffHas(roll, permissions, 'reports.read') && (
            <NavBtn to="/dashboard">لوحة التحكم</NavBtn>
          )}
          {staffHas(roll, permissions, 'drivers.read') && (
            <NavBtn to="/drivers">سائقون</NavBtn>
          )}
          {staffHas(roll, permissions, 'discounts.write') && (
            <NavBtn to="/discounts">خصومات</NavBtn>
          )}
          {staffHas(roll, permissions, 'requests.read') && (
            <NavBtn to="/sos">تنبيهات SOS</NavBtn>
          )}
          {staffHas(roll, permissions, 'requests.read') && (
            <NavBtn to="/requests">الطلبات والتتبع</NavBtn>
          )}
          {staffHas(roll, permissions, 'requests.write') && (
            <NavBtn to="/requests/dispatch">إرسال طلب لسائق</NavBtn>
          )}
          {staffHas(roll, permissions, 'customers.read') && (
            <>
              <NavBtn to="/customers">الزبائن المسجّلون</NavBtn>
              <NavBtn to="/wallet-log">سجل محافظ الزبائن</NavBtn>
              <NavBtn to="/customers-map">خريطة الزبائن</NavBtn>
              <NavBtn to="/whatsapp-broadcast">إعلانات واتساب للزبائن</NavBtn>
              <NavBtn to="/mtn-sms-broadcast">إرسال رسائل MTN SMS</NavBtn>
              <NavBtn to="/reviews">رأي الراكبين بالرحلة</NavBtn>
            </>
          )}
          {staffHas(roll, permissions, 'areas.read') && (
            <NavBtn to="/areas">مناطق إدارية (اختياري)</NavBtn>
          )}
          {staffHas(roll, permissions, 'reports.read') && (
            <>
              <button type="button" onClick={() => void exportCsv('customers')}>
                تصدير زبائن (CSV)
              </button>
              <button type="button" onClick={() => void exportCsv('drivers')}>
                تصدير سائقين (CSV)
              </button>
              <button type="button" onClick={() => void financialPdf()}>
                تقرير مالي PDF
              </button>
            </>
          )}
          {staffHas(roll, permissions, 'requests.read') && (
            <NavBtn to="/map">خريطة العمليات</NavBtn>
          )}
          {staffHas(roll, permissions, 'drivers.write') && (
            <>
              <NavBtn to="/car-types">فئات السيارة (التسعير)</NavBtn>
              <NavBtn to="/pricing-zones">مناطق التسعير (مدينة/ريف)</NavBtn>
              <NavBtn to="/free-meter">إعدادات العداد الحر</NavBtn>
            </>
          )}
          {roll === 'Admin' && <NavBtn to="/employees">موظفو الإدارة</NavBtn>}
          <NavBtn to="/password">تغيير كلمة المرور</NavBtn>
          <hr className="drawer-hr" />
          <button
            type="button"
            className="drawer-logout"
            onClick={() => {
              setDrawer(false);
              void logout().then(() => nav('/login', { replace: true }));
            }}
          >
            تسجيل الخروج
          </button>
        </nav>
        <div className="drawer-foot">
          <div>GS TAXI</div>
          <div className="small">بوابتك لعالم التوصيل الذكي</div>
        </div>
      </aside>

      <div className="admin-main">
        <header className="admin-appbar">
          <button
            type="button"
            className="icon-btn"
            aria-label={drawer ? 'إغلاق القائمة' : 'فتح القائمة'}
            aria-expanded={drawer}
            onClick={() => setDrawer((v) => !v)}
          >
            {drawer ? '✕' : '☰'}
          </button>
          <h1 className="admin-title">{title}</h1>
          <span className="icon-spacer" />
        </header>

        <main className="admin-body" key={loc.pathname}>
          <Outlet />
        </main>
      </div>
    </div>
  );
}

export { NAVY, AMBER };
