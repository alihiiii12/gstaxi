import { useState, type FormEvent } from 'react';
import { API } from '../api/endpoints';
import { postJson } from '../api/http';

export function PasswordPage() {
  const [p1, setP1] = useState('');
  const [p2, setP2] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');

  async function submit(e: FormEvent) {
    e.preventDefault();
    setMsg('');
    if (p1.length < 6) {
      setMsg('كلمة المرور يجب ألا تقل عن 6 أحرف');
      return;
    }
    if (p1 !== p2) {
      setMsg('التأكيد غير مطابق');
      return;
    }
    setBusy(true);
    try {
      const { res, data } = await postJson<Record<string, unknown>>(
        API.updatePassword,
        { password: p1 },
      );
      const ok = res.ok && (data.state === true || data.success === true);
      setMsg(ok ? 'تم تحديث كلمة المرور' : String(data.message ?? 'فشل'));
    } catch (err) {
      setMsg(String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="page-pad narrow">
      <h2 className="page-title">تغيير كلمة المرور</h2>
      <form onSubmit={(e) => void submit(e)} className="stack-form">
        <label>
          كلمة المرور الجديدة
          <input type="password" value={p1} onChange={(e) => setP1(e.target.value)} />
        </label>
        <label>
          تأكيد كلمة المرور
          <input type="password" value={p2} onChange={(e) => setP2(e.target.value)} />
        </label>
        {msg && <p className={msg.includes('تم') ? 'text-ok' : 'text-err'}>{msg}</p>}
        <button type="submit" className="btn-primary" disabled={busy}>
          {busy ? 'جاري الحفظ…' : 'حفظ'}
        </button>
      </form>
    </div>
  );
}
