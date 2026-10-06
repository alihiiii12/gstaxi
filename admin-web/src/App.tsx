import { useEffect, useState } from 'react';
import { Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { AdminLayout } from './components/AdminLayout';
import { staffHas, useAuth, AuthProvider } from './auth/AuthContext';
import { API } from './api/endpoints';
import {
  clearServiceCutFlag,
  SERVICE_CUT_CODE,
  SERVICE_CUT_EVENT,
} from './api/http';
import { LoginPage } from './pages/LoginPage';
import { DashboardPage } from './pages/DashboardPage';
import { DriversPage } from './pages/DriversPage';
import { DriverRegisterPage } from './pages/DriverRegisterPage';
import { DriverEditPage } from './pages/DriverEditPage';
import { DiscountsPage } from './pages/DiscountsPage';
import { SosPage } from './pages/SosPage';
import { RequestsPage } from './pages/RequestsPage';
import { RequestDetailPage } from './pages/RequestDetailPage';
import { CustomersPage } from './pages/CustomersPage';
import { ReviewsPage } from './pages/ReviewsPage';
import { PasswordPage } from './pages/PasswordPage';
import { EmployeesPage } from './pages/EmployeesPage';
import { AreasPage } from './pages/AreasPage';
import { CarTypesPage } from './pages/CarTypesPage';
import { FreeMeterPage } from './pages/FreeMeterPage';
import { MapPage } from './pages/MapPage';
import { DispatchTripPage } from './pages/DispatchTripPage';
import { WhatsAppBroadcastPage } from './pages/WhatsAppBroadcastPage';
import { MtnSmsBroadcastPage } from './pages/MtnSmsBroadcastPage';
import { CustomersMapPage } from './pages/CustomersMapPage';
import { WalletLogPage } from './pages/WalletLogPage';
import { PricingZonesPage } from './pages/PricingZonesPage';

function ServiceCutOverlay() {
  const [cut, setCut] = useState(() => {
    try {
      return sessionStorage.getItem('service_cut') === '1';
    } catch {
      return false;
    }
  });
  const [checking, setChecking] = useState(false);

  useEffect(() => {
    const onCut = () => setCut(true);
    window.addEventListener(SERVICE_CUT_EVENT, onCut);
    return () => window.removeEventListener(SERVICE_CUT_EVENT, onCut);
  }, []);

  async function retry() {
    setChecking(true);
    try {
      const res = await fetch(`${API.base}/app/update-info`, {
        headers: { Accept: 'application/json' },
      });
      const text = await res.text();
      let code = '';
      try {
        code = String((JSON.parse(text) as { code?: string }).code ?? '');
      } catch {
        /* ignore */
      }
      if (res.ok || code !== SERVICE_CUT_CODE) {
        clearServiceCutFlag();
        setCut(false);
        window.location.reload();
        return;
      }
      setCut(true);
    } catch {
      setCut(true);
    } finally {
      setChecking(false);
    }
  }

  if (!cut) return null;

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 99999,
        background: 'rgba(15, 23, 42, 0.92)',
        color: '#fff',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 24,
        textAlign: 'center',
      }}
    >
      <div style={{ maxWidth: 420 }}>
        <h1 style={{ fontSize: 22, marginBottom: 12 }}>تم قطع الاتصال بالخادم</h1>
        <p style={{ opacity: 0.85, lineHeight: 1.6, marginBottom: 20 }}>
          التطبيق ولوحة التحكم متوقفان مؤقتاً. أعد التشغيل من السيرفر ثم اضغط
          «إعادة المحاولة».
        </p>
        <button
          type="button"
          className="btn"
          disabled={checking}
          onClick={() => void retry()}
          style={{ minWidth: 160 }}
        >
          {checking ? 'جاري التحقق…' : 'إعادة المحاولة'}
        </button>
      </div>
    </div>
  );
}

function RequireAuth({ children }: { children: React.ReactNode }) {
  const { user } = useAuth();
  const loc = useLocation();
  if (!user) {
    return <Navigate to="/login" replace state={{ from: loc.pathname }} />;
  }
  return <>{children}</>;
}

function RequireAdmin({ children }: { children: React.ReactNode }) {
  const { user } = useAuth();
  if (user?.roll !== 'Admin') {
    return <Navigate to="/" replace />;
  }
  return <>{children}</>;
}

function PermissionGate({ perm, children }: { perm: string; children: React.ReactNode }) {
  const { user } = useAuth();
  if (!user || !staffHas(user.roll, user.permissions, perm)) {
    return (
      <div className="page-pad">
        <p className="text-err">لا تملك صلاحية الوصول إلى هذا القسم.</p>
      </div>
    );
  }
  return <>{children}</>;
}

function HomeIndex() {
  const { user } = useAuth();
  if (!user) return <Navigate to="/login" replace />;
  const { roll, permissions } = user;
  const first = (path: string, key: string) =>
    staffHas(roll, permissions, key) ? path : null;
  const dest =
    first('/dashboard', 'reports.read') ??
    first('/drivers', 'drivers.read') ??
    first('/discounts', 'discounts.write') ??
    first('/sos', 'requests.read') ??
    first('/requests', 'requests.read') ??
    first('/customers', 'customers.read') ??
    first('/reviews', 'customers.read') ??
    first('/areas', 'areas.read') ??
    first('/map', 'requests.read') ??
    first('/car-types', 'drivers.write') ??
    first('/free-meter', 'drivers.write') ??
    (roll === 'Admin' ? '/employees' : null) ??
    '/password';
  return <Navigate to={dest} replace />;
}

function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        element={
          <RequireAuth>
            <AdminLayout />
          </RequireAuth>
        }
      >
        <Route index element={<HomeIndex />} />
        <Route
          path="dashboard"
          element={
            <PermissionGate perm="reports.read">
              <DashboardPage />
            </PermissionGate>
          }
        />
        <Route
          path="drivers"
          element={
            <PermissionGate perm="drivers.read">
              <DriversPage />
            </PermissionGate>
          }
        />
        <Route
          path="drivers/new"
          element={
            <PermissionGate perm="drivers.write">
              <DriverRegisterPage />
            </PermissionGate>
          }
        />
        <Route
          path="drivers/:id/edit"
          element={
            <PermissionGate perm="drivers.write">
              <DriverEditPage />
            </PermissionGate>
          }
        />
        <Route
          path="discounts"
          element={
            <PermissionGate perm="discounts.write">
              <DiscountsPage />
            </PermissionGate>
          }
        />
        <Route
          path="sos"
          element={
            <PermissionGate perm="requests.read">
              <SosPage />
            </PermissionGate>
          }
        />
        <Route
          path="requests"
          element={
            <PermissionGate perm="requests.read">
              <RequestsPage />
            </PermissionGate>
          }
        />
        <Route
          path="requests/dispatch"
          element={
            <PermissionGate perm="requests.write">
              <DispatchTripPage />
            </PermissionGate>
          }
        />
        <Route
          path="requests/:id"
          element={
            <PermissionGate perm="requests.read">
              <RequestDetailPage />
            </PermissionGate>
          }
        />
        <Route
          path="customers"
          element={
            <PermissionGate perm="customers.read">
              <CustomersPage />
            </PermissionGate>
          }
        />
        <Route
          path="wallet-log"
          element={
            <PermissionGate perm="customers.read">
              <WalletLogPage />
            </PermissionGate>
          }
        />
        <Route
          path="whatsapp-broadcast"
          element={
            <PermissionGate perm="customers.read">
              <WhatsAppBroadcastPage />
            </PermissionGate>
          }
        />
        <Route
          path="mtn-sms-broadcast"
          element={
            <PermissionGate perm="customers.read">
              <MtnSmsBroadcastPage />
            </PermissionGate>
          }
        />
        <Route
          path="customers-map"
          element={
            <PermissionGate perm="customers.read">
              <CustomersMapPage />
            </PermissionGate>
          }
        />
        <Route
          path="reviews"
          element={
            <PermissionGate perm="customers.read">
              <ReviewsPage />
            </PermissionGate>
          }
        />
        <Route path="password" element={<PasswordPage />} />
        <Route
          path="employees"
          element={
            <RequireAdmin>
              <EmployeesPage />
            </RequireAdmin>
          }
        />
        <Route
          path="areas"
          element={
            <PermissionGate perm="areas.read">
              <AreasPage />
            </PermissionGate>
          }
        />
        <Route
          path="map"
          element={
            <PermissionGate perm="requests.read">
              <MapPage />
            </PermissionGate>
          }
        />
        <Route
          path="car-types"
          element={
            <PermissionGate perm="drivers.write">
              <CarTypesPage />
            </PermissionGate>
          }
        />
        <Route
          path="free-meter"
          element={
            <PermissionGate perm="drivers.write">
              <FreeMeterPage />
            </PermissionGate>
          }
        />
        <Route
          path="pricing-zones"
          element={
            <PermissionGate perm="drivers.write">
              <PricingZonesPage />
            </PermissionGate>
          }
        />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <ServiceCutOverlay />
      <AppRoutes />
    </AuthProvider>
  );
}
