import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { API } from '../api/endpoints';
import { authHeaders, postFormLogin } from '../api/http';

export interface AuthUser {
  id: number;
  firstName: string;
  lastName: string;
  number: string;
  roll: string;
  permissions: string[];
  token: string;
}

function readStored(): AuthUser | null {
  const token = localStorage.getItem('token');
  if (!token) return null;
  const roll = localStorage.getItem('user_roll') ?? '';
  const permsRaw = localStorage.getItem('staff_permissions');
  let permissions: string[] = [];
  try {
    if (permsRaw) permissions = JSON.parse(permsRaw) as string[];
  } catch {
    permissions = [];
  }
  return {
    id: parseInt(localStorage.getItem('user_id') ?? '0', 10),
    firstName: localStorage.getItem('user_first') ?? '',
    lastName: localStorage.getItem('user_last') ?? '',
    number: localStorage.getItem('user_number') ?? '',
    roll,
    permissions,
    token,
  };
}

function parseLogin(raw: Record<string, unknown>): AuthUser | null {
  const ok =
    raw.success === true ||
    raw.state === true ||
    raw.state === 1 ||
    raw.success === 1;
  if (!ok) return null;
  const u = raw.user as Record<string, unknown> | undefined;
  if (!u) return null;
  const token = String(raw.token ?? u.token ?? '');
  if (!token) return null;
  const perms = u.permissions;
  const permissions = Array.isArray(perms) ? perms.map(String) : [];
  return {
    id: Number(u.id ?? 0),
    firstName: String(u.firstName ?? ''),
    lastName: String(u.lastName ?? ''),
    number: String(u.number ?? ''),
    roll: String(u.roll ?? ''),
    permissions,
    token,
  };
}

function persist(u: AuthUser) {
  localStorage.setItem('token', u.token);
  localStorage.setItem('user_id', String(u.id));
  localStorage.setItem('user_roll', u.roll);
  localStorage.setItem('staff_permissions', JSON.stringify(u.permissions));
  localStorage.setItem('user_first', u.firstName);
  localStorage.setItem('user_last', u.lastName);
  localStorage.setItem('user_number', u.number);
}

function clearPersist() {
  [
    'token',
    'user_id',
    'user_roll',
    'staff_permissions',
    'user_first',
    'user_last',
    'user_number',
    'driver_id',
  ].forEach((k) => localStorage.removeItem(k));
}

export function staffHas(roll: string, permissions: string[], key: string): boolean {
  if (roll === 'Admin') return true;
  return permissions.includes(key);
}

interface AuthContextValue {
  user: AuthUser | null;
  loading: boolean;
  login: (number: string, password: string) => Promise<string | void>;
  logout: () => Promise<void>;
  refresh: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(() => readStored());
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(() => {
    setUser(readStored());
  }, []);

  const login = useCallback(async (number: string, password: string) => {
    setLoading(true);
    try {
      const raw = (await postFormLogin(number.trim(), password)) as Record<
        string,
        unknown
      >;
      const u = parseLogin(raw);
      if (!u) {
        const errs = raw.errors as Record<string, unknown> | undefined;
        if (errs && typeof errs === 'object') {
          const first = Object.values(errs).flatMap((v) =>
            Array.isArray(v) ? v.map(String) : [String(v)],
          );
          if (first.length > 0) return first[0];
        }
        return String(raw.message ?? 'فشل تسجيل الدخول — تحقق من الرقم وكلمة المرور');
      }
      if (u.roll !== 'Admin' && u.roll !== 'Employee') {
        return 'هذه اللوحة للموظفين والمسؤولين فقط (حساب سائق/راكب لا يدخل هنا)';
      }
      persist(u);
      setUser(u);
      return undefined;
    } catch (e) {
      return 'تعذر الاتصال بالخادم — تحقق من الإنترنت أو عنوان API'
        + (e instanceof Error && e.message ? ` (${e.message})` : '');
    } finally {
      setLoading(false);
    }
  }, []);

  const logout = useCallback(async () => {
    try {
      await fetch(API.logout, { method: 'POST', headers: authHeaders() });
    } catch {
      /* ignore */
    }
    clearPersist();
    setUser(null);
  }, []);

  const value = useMemo(
    () => ({ user, loading, login, logout, refresh }),
    [user, loading, login, logout, refresh],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth outside AuthProvider');
  return ctx;
}
