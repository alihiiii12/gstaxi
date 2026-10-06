import { useState, type FormEvent } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import './LoginPage.css';

export function LoginPage() {
  const { user, login, loading } = useAuth();
  const nav = useNavigate();
  const [number, setNumber] = useState('');
  const [password, setPassword] = useState('');
  const [err, setErr] = useState('');
  const [status, setStatus] = useState('');

  if (user) return <Navigate to="/" replace />;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setErr('');
    setStatus('جاري الاتصال بالخادم…');
    try {
      const msg = await login(number, password);
      if (msg) {
        setErr(msg);
        setStatus('');
        return;
      }
      setStatus('تم الدخول — جاري التحويل…');
      nav('/', { replace: true });
    } catch (ex) {
      setErr(`خطأ غير متوقع: ${String(ex)}`);
      setStatus('');
    }
  }

  return (
    <div className="login-root" dir="rtl">
      <div className="login-card">
        <h1 className="login-brand">GS TAXI</h1>
        <p className="login-sub">لوحة الإدارة — الدخول من الويب</p>
        <form onSubmit={onSubmit}>
          <label>
            رقم الهاتف
            <input
              type="text"
              autoComplete="username"
              value={number}
              onChange={(e) => setNumber(e.target.value)}
              required
            />
          </label>
          <label>
            كلمة المرور
            <input
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
          </label>
          {status && <p className="login-status">{status}</p>}
          {err && <p className="login-err" role="alert">{err}</p>}
          <button type="submit" disabled={loading}>
            {loading ? 'جاري الدخول…' : 'دخول'}
          </button>
        </form>
      </div>
    </div>
  );
}
