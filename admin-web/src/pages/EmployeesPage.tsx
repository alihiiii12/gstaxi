import { useCallback, useEffect, useState } from 'react';
import { API } from '../api/endpoints';
import { deleteJson, fetchJsonAuth, postJson, putJson } from '../api/http';
import { useAuth } from '../auth/AuthContext';
import { NameSearchField } from '../components/NameSearchField';
import { PageHeader } from '../components/PageHeader';
import { formatApiFailure } from '../util/apiError';
import { usePersistedState, useScrollRestore } from '../util/pageState';

const PERM_LABELS: Record<string, string> = {
  'drivers.read': 'عرض السائقين',
  'drivers.write': 'تعديل السائقين',
  'requests.read': 'عرض الطلبات',
  'requests.write': 'إدارة الطلبات',
  'discounts.write': 'إدارة الخصومات',
  'areas.read': 'عرض المناطق الإدارية (اختياري)',
  'areas.write': 'تعديل المناطق الإدارية (اختياري)',
  'reports.read': 'التقارير',
  'customers.read': 'عرض الزبائن',
  'customers.wallet': 'إدارة محافظ الزبائن (تعبئة/خصم/تصحيح)',
};

type Row = Record<string, unknown>;

export function EmployeesPage() {
  const { user } = useAuth();
  const isAdmin = user?.roll === 'Admin';
  const [rows, setRows] = useState<Row[]>([]);
  const [err, setErr] = useState('');
  const [createOpen, setCreateOpen] = useState(false);
  const [permUser, setPermUser] = useState<Row | null>(null);
  const [nameQuery, setNameQuery] = usePersistedState('employees.search', '');
  const [debouncedName, setDebouncedName] = useState(() => nameQuery.trim());

  useEffect(() => {
    const id = window.setTimeout(() => setDebouncedName(nameQuery.trim()), 350);
    return () => window.clearTimeout(id);
  }, [nameQuery]);

  const load = useCallback(async () => {
    setErr('');
    try {
      const q = new URLSearchParams();
      if (debouncedName) q.set('search', debouncedName);
      const url = q.toString() ? `${API.adminEmployees}?${q}` : API.adminEmployees;
      const { res, data: j } = await fetchJsonAuth(url);
      if (!res.ok || j.success !== true) {
        throw new Error(String(j.message ?? ''));
      }
      const list = (j.data as unknown[]) ?? [];
      setRows(list.map((e) => e as Row));
    } catch (e) {
      setErr(String(e));
    }
  }, [debouncedName]);

  useEffect(() => {
    void load();
  }, [load]);
  useScrollRestore('employees', rows.length > 0);

  async function removeEmployee(id: number, name: string) {
    if (!window.confirm(`حذف حساب «${name}»؟ (حذف منطقي)`)) return;
    try {
      const { res, data } = await deleteJson<Record<string, unknown>>(
        API.adminEmployeeDestroy(id),
      );
      if (res.ok && data.success === true) {
        alert(String(data.message ?? 'تم الحذف'));
        void load();
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } catch (e) {
      alert(String(e));
    }
  }

  return (
    <div className="page-pad">
      <PageHeader
        title="موظفو الإدارة"
        subtitle="حسابات الموظفين والصلاحيات."
        onRefresh={() => void load()}
        actions={
          isAdmin ? (
            <button type="button" className="btn-primary" onClick={() => setCreateOpen(true)}>
              + موظف جديد
            </button>
          ) : null
        }
      />
      {err && <p className="text-err">{err}</p>}
      <NameSearchField
        value={nameQuery}
        onChange={setNameQuery}
        label="بحث باسم الموظف أو رقم الهاتف"
        placeholder="مثال: أحمد، 09…"
      />
      <div className="card-list">
        {rows.map((u) => {
          const id = Number(u.id ?? 0);
          const name = `${u.firstName ?? ''} ${u.lastName ?? ''}`.trim();
          const roll = String(u.roll ?? '');
          const banned = u.banned === true ? ' (موقوف)' : '';
          const isSelf = user?.id === id;
          return (
            <div key={id} className="card">
              <div className="row-between">
                <div>
                  <div className="card-title">{name || `مستخدم #${id}`}</div>
                  <div className="text-muted">
                    {String(u.number ?? '')} — {roll}
                    {banned}
                  </div>
                </div>
                <div className="row-gap">
                  {roll === 'Employee' && isAdmin && (
                    <button type="button" className="btn-ghost" onClick={() => setPermUser(u)}>
                      صلاحيات
                    </button>
                  )}
                  {isAdmin && !isSelf && (
                    <button
                      type="button"
                      className="btn-warn"
                      onClick={() => void removeEmployee(id, name || `#${id}`)}
                    >
                      حذف
                    </button>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>
      {!rows.length && !err && debouncedName && (
        <p className="text-muted">لا موظف يطابق «{debouncedName}».</p>
      )}
      {!rows.length && !err && !debouncedName && <p className="text-muted">لا يوجد موظفون</p>}

      {createOpen && (
        <EmployeeCreateModal
          onClose={() => setCreateOpen(false)}
          onSaved={() => {
            setCreateOpen(false);
            void load();
          }}
        />
      )}
      {permUser && (
        <EmployeePermissionsModal
          user={permUser}
          onClose={() => setPermUser(null)}
          onSaved={() => {
            setPermUser(null);
            void load();
          }}
        />
      )}
    </div>
  );
}

function EmployeeCreateModal({
  onClose,
  onSaved,
}: {
  onClose: () => void;
  onSaved: () => void;
}) {
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [number, setNumber] = useState('');
  const [password, setPassword] = useState('');
  const [roll, setRoll] = useState('Employee');
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    try {
      const { res, data } = await postJson<Record<string, unknown>>(API.adminEmployees, {
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        number: number.trim(),
        password,
        roll,
        permissions: [],
      });
      if ((res.status === 200 || res.status === 201) && data.success === true) {
        alert(String(data.message ?? 'تم'));
        onSaved();
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" role="presentation" onClick={onClose}>
      <div className="modal" role="dialog" onClick={(e) => e.stopPropagation()} dir="rtl">
        <h3>موظف جديد</h3>
        <label>
          الاسم الأول
          <input value={firstName} onChange={(e) => setFirstName(e.target.value)} />
        </label>
        <label>
          الاسم الأخير
          <input value={lastName} onChange={(e) => setLastName(e.target.value)} />
        </label>
        <label>
          الرقم
          <input value={number} onChange={(e) => setNumber(e.target.value)} />
        </label>
        <label>
          كلمة السر
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
        </label>
        <label>
          الدور
          <select value={roll} onChange={(e) => setRoll(e.target.value)}>
            <option value="Employee">موظف</option>
            <option value="Admin">مسؤول</option>
          </select>
        </label>
        <div className="row-gap" style={{ marginTop: 16 }}>
          <button type="button" className="btn-ghost" onClick={onClose}>
            إلغاء
          </button>
          <button type="button" className="btn-primary" disabled={busy} onClick={() => void save()}>
            {busy ? '…' : 'حفظ'}
          </button>
        </div>
      </div>
    </div>
  );
}

function EmployeePermissionsModal({
  user,
  onClose,
  onSaved,
}: {
  user: Row;
  onClose: () => void;
  onSaved: () => void;
}) {
  const id = Number(user.id ?? 0);
  const raw = user.permissions;
  const initial = new Set<string>(
    Array.isArray(raw) ? raw.map((e) => String(e)) : [],
  );
  const [selected, setSelected] = useState(() => new Set(initial));
  const [busy, setBusy] = useState(false);

  function toggle(k: string) {
    setSelected((prev) => {
      const n = new Set(prev);
      if (n.has(k)) n.delete(k);
      else n.add(k);
      return n;
    });
  }

  async function save() {
    setBusy(true);
    try {
      const { res, data } = await putJson<Record<string, unknown>>(
        API.adminEmployeePermissions(id),
        { permissions: [...selected] },
      );
      if (res.ok && data.success === true) {
        alert('حُفظت الصلاحيات');
        onSaved();
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } finally {
      setBusy(false);
    }
  }

  const name = `${user.firstName ?? ''} ${user.lastName ?? ''}`.trim();

  return (
    <div className="modal-backdrop" role="presentation" onClick={onClose}>
      <div className="modal" role="dialog" onClick={(e) => e.stopPropagation()} dir="rtl">
        <h3>صلاحيات {name || `#${id}`}</h3>
        <div style={{ maxHeight: '50vh', overflow: 'auto' }}>
          {Object.entries(PERM_LABELS).map(([k, lab]) => (
            <label
              key={k}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 10,
                marginBottom: 10,
                fontWeight: 600,
              }}
            >
              <input type="checkbox" checked={selected.has(k)} onChange={() => toggle(k)} />
              {lab}
            </label>
          ))}
        </div>
        <div className="row-gap" style={{ marginTop: 16 }}>
          <button type="button" className="btn-ghost" onClick={onClose}>
            إلغاء
          </button>
          <button type="button" className="btn-primary" disabled={busy} onClick={() => void save()}>
            {busy ? '…' : 'حفظ'}
          </button>
        </div>
      </div>
    </div>
  );
}
