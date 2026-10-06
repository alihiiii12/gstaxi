import { useCallback, useEffect, useLayoutEffect, useState } from 'react';
import { Link, useNavigate, useParams, useLocation } from 'react-router-dom';
import { API } from '../api/endpoints';
import { deleteJson, fetchJsonAuth, postFormData, postJson } from '../api/http';
import { loadCarTypesForPricing } from '../api/carTypes';
import { formatApiFailure } from '../util/apiError';
import {
  normalizeVehicleTypeValue,
  VEHICLE_TYPE_OPTIONS,
} from '../util/vehicleTypeOptions';

function isTruthyApi(v: unknown): boolean {
  return v === true || v === 1 || v === '1' || v === 'true';
}

function asRecord(v: unknown): Record<string, unknown> | null {
  if (v && typeof v === 'object' && !Array.isArray(v)) return v as Record<string, unknown>;
  return null;
}

function strFrom(obj: Record<string, unknown>, ...keys: string[]): string {
  for (const k of keys) {
    const v = obj[k];
    if (v != null && String(v).trim() !== '') return String(v);
  }
  return '';
}

function mergeUserObjects(
  a: Record<string, unknown>,
  b: Record<string, unknown>,
): Record<string, unknown> {
  const out: Record<string, unknown> = { ...a };
  for (const [k, v] of Object.entries(b)) {
    if (v != null && String(v).trim() !== '') out[k] = v;
  }
  return out;
}

/** دمج صف من القائمة مع استجابة show — يحافظ على user إن غاب في الـ API */
function mergeDriverRows(
  fromList: Record<string, unknown> | null,
  fromApi: Record<string, unknown> | null,
): Record<string, unknown> | null {
  if (!fromList) return fromApi;
  if (!fromApi) return fromList;
  const u1 = asRecord(fromList.user) ?? {};
  const u2 = asRecord(fromApi.user) ?? {};
  return {
    ...fromList,
    ...fromApi,
    user: mergeUserObjects(u1, u2),
  };
}

/**
 * يستخرج كائن السائق للنموذج.
 * يغطّي: data = مصفوفة، driver + user أخوين، حقول المستخدم على نفس مستوى driver في data (شائع في Laravel).
 */
function extractDriverFromShowJson(j: Record<string, unknown>): Record<string, unknown> | null {
  if (Array.isArray(j.data)) {
    const row = asRecord((j.data as unknown[])[0]);
    if (row) return row;
  }

  const d = asRecord(j.data);
  if (d) {
    const drv = asRecord(d.driver);
    const usr =
      asRecord(d.user) ??
      asRecord(d.User) ??
      asRecord(d.account) ??
      asRecord(d.profile);

    if (drv && usr) {
      return { ...drv, user: usr };
    }
    if (drv && asRecord(drv.user)) {
      return drv;
    }
    if (drv) {
      if (usr) return { ...drv, user: usr };
      const hasLiftedUser =
        strFrom(d, 'firstName', 'first_name', 'FirstName') ||
        strFrom(d, 'lastName', 'last_name', 'LastName') ||
        strFrom(d, 'number', 'phone', 'mobile', 'phone_number', 'phoneNumber');
      if (hasLiftedUser) {
        return {
          ...drv,
          user: {
            firstName: strFrom(d, 'firstName', 'first_name', 'FirstName'),
            lastName: strFrom(d, 'lastName', 'last_name', 'LastName'),
            number: strFrom(d, 'number', 'phone', 'mobile', 'phone_number', 'phoneNumber'),
          },
        };
      }
      return drv;
    }

    const inner = asRecord(d.data);
    if (inner && !Array.isArray(inner)) {
      const idOk =
        inner.id != null ||
        inner.carNumber != null ||
        inner.car_number != null;
      if (idOk || strFrom(inner, 'firstName', 'first_name', 'number')) {
        return inner;
      }
    }

    if (Array.isArray(d.data)) {
      const first = d.data[0];
      const row = asRecord(first);
      if (row) return row;
    }

    if (
      d.id != null ||
      d.carNumber != null ||
      d.car_number != null ||
      strFrom(d, 'firstName', 'first_name', 'number', 'phone')
    ) {
      return d;
    }
  }

  return asRecord(j.driver);
}

function readPassedRow(
  loc: { state?: unknown },
  driverId: number,
): Record<string, unknown> | null {
  const s = loc.state as { row?: Record<string, unknown> } | null | undefined;
  const r = s?.row;
  if (!r || Number(r.id ?? 0) !== driverId) return null;
  return r;
}

function transTypeFromRow(row: Record<string, unknown>): Record<string, unknown> | null {
  const a = row.transType;
  if (a && typeof a === 'object') return a as Record<string, unknown>;
  const b = row.trans_type;
  if (b && typeof b === 'object') return b as Record<string, unknown>;
  return null;
}

function carTypeIdFromRow(row: Record<string, unknown>): number {
  const tt = transTypeFromRow(row);
  const fromRel = Number(tt?.id ?? 0);
  if (fromRel > 0) return fromRel;
  const direct = Number(
    row.carTypeId ?? row.car_type_id ?? row.CarTypeId ?? row.trans_type_id ?? 0,
  );
  return direct > 0 ? direct : 0;
}

function applyRowToForm(r: Record<string, unknown>) {
  const u = asRecord(r.user) ?? {};
  return {
    firstName:
      strFrom(u, 'firstName', 'first_name', 'FirstName') ||
      strFrom(r, 'firstName', 'first_name', 'FirstName'),
    lastName:
      strFrom(u, 'lastName', 'last_name', 'LastName') ||
      strFrom(r, 'lastName', 'last_name', 'LastName'),
    number:
      strFrom(u, 'number', 'phone', 'mobile', 'phone_number', 'phoneNumber') ||
      strFrom(r, 'number', 'phone', 'mobile', 'phone_number', 'phoneNumber'),
    carNumber: strFrom(r, 'carNumber', 'car_number', 'CarNumber'),
    insurance: strFrom(r, 'insurance'),
    mechanics: strFrom(r, 'mechanics'),
    typeCar: normalizeVehicleTypeValue(
      strFrom(r, 'type', 'typeCar', 'type_car', 'TypeCar') || 'car',
    ),
    carTypeId: carTypeIdFromRow(r),
    vehicleModel: strFrom(r, 'vehicle_model', 'vehicleModel', 'VehicleModel'),
  };
}

function applyFormFields(
  r: Record<string, unknown>,
  setters: {
    setRow: (v: Record<string, unknown>) => void;
    setFirstName: (v: string) => void;
    setLastName: (v: string) => void;
    setNumber: (v: string) => void;
    setPassword: (v: string) => void;
    setCarNumber: (v: string) => void;
    setInsurance: (v: string) => void;
    setMechanics: (v: string) => void;
    setTypeCar: (v: string) => void;
    setCarTypeId: (v: number) => void;
    setVehicleModel: (v: string) => void;
  },
) {
  setters.setRow(r);
  const f = applyRowToForm(r);
  setters.setFirstName(f.firstName);
  setters.setLastName(f.lastName);
  setters.setNumber(f.number);
  setters.setPassword('');
  setters.setCarNumber(f.carNumber);
  setters.setInsurance(f.insurance);
  setters.setMechanics(f.mechanics);
  setters.setTypeCar(f.typeCar);
  setters.setCarTypeId(f.carTypeId);
  setters.setVehicleModel(f.vehicleModel);
}

export function DriverEditPage() {
  const { id: idParam } = useParams();
  const id = Number(idParam ?? 0);
  const nav = useNavigate();
  const location = useLocation();

  const [row, setRow] = useState<Record<string, unknown> | null>(null);
  const [loadingRow, setLoadingRow] = useState(true);
  const [loadErr, setLoadErr] = useState('');
  const [categories, setCategories] = useState<Record<string, unknown>[]>([]);
  const [loadingCat, setLoadingCat] = useState(true);

  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [number, setNumber] = useState('');
  const [password, setPassword] = useState('');
  const [carNumber, setCarNumber] = useState('');
  const [insurance, setInsurance] = useState('');
  const [mechanics, setMechanics] = useState('');
  const [typeCar, setTypeCar] = useState('car');
  const [vehicleModel, setVehicleModel] = useState('');
  const [carTypeId, setCarTypeId] = useState(0);
  const [imgDriver, setImgDriver] = useState<File | null>(null);
  const [imgId, setImgId] = useState<File | null>(null);
  const [imgCar, setImgCar] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);

  const todayYmd = () => {
    const d = new Date();
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  };
  const [tripsFrom, setTripsFrom] = useState(todayYmd);
  const [tripsTo, setTripsTo] = useState(todayYmd);
  const [tripsLoading, setTripsLoading] = useState(false);
  const [tripsErr, setTripsErr] = useState('');
  const [trips, setTrips] = useState<Record<string, unknown>[]>([]);
  const [tripsSummary, setTripsSummary] = useState<Record<string, unknown> | null>(null);

  const [walletBalance, setWalletBalance] = useState(0);
  const [walletCurrency, setWalletCurrency] = useState('SYP');
  const [walletTxs, setWalletTxs] = useState<Record<string, unknown>[]>([]);
  const [walletLoading, setWalletLoading] = useState(false);
  const [walletErr, setWalletErr] = useState('');
  const [walletAmount, setWalletAmount] = useState('');
  const [walletNote, setWalletNote] = useState('');
  const [walletBusy, setWalletBusy] = useState(false);

  const setters = {
    setRow,
    setFirstName,
    setLastName,
    setNumber,
    setPassword,
    setCarNumber,
    setInsurance,
    setMechanics,
    setTypeCar,
    setCarTypeId,
    setVehicleModel,
  };

  useLayoutEffect(() => {
    if (!id) return;
    const passed = readPassedRow(location, id);
    if (!passed) return;
    applyFormFields(passed, setters);
    setLoadingRow(false);
  }, [id, location.key, location.state]);

  const loadDriver = useCallback(async () => {
    if (!id) return;
    setLoadErr('');
    const passed = readPassedRow(location, id);
    if (!passed) {
      setLoadingRow(true);
    }
    try {
      const { res, data: j } = await fetchJsonAuth(API.driverShow(id));
      const r0 = extractDriverFromShowJson(j);
      const ok =
        res.ok &&
        (isTruthyApi(j.success) ||
          isTruthyApi(j.state) ||
          (r0 != null &&
            (r0.id != null ||
              r0.carNumber != null ||
              r0.car_number != null ||
              strFrom(r0, 'firstName', 'first_name', 'number'))));
      if (!ok) {
        throw new Error(String(j.message ?? res.statusText));
      }
      const fromApi = r0 ?? asRecord(j.data);
      const merged = mergeDriverRows(passed, fromApi) ?? fromApi ?? passed;
      if (!merged) {
        throw new Error('لا بيانات سائق في الاستجابة');
      }
      applyFormFields(merged, setters);
    } catch (e) {
      if (!passed) {
        setLoadErr(String(e));
        setRow(null);
      } else {
        setLoadErr(String(e));
      }
    } finally {
      setLoadingRow(false);
    }
  }, [id, location.key, location.state]);

  useEffect(() => {
    void loadDriver();
  }, [loadDriver]);

  const loadTrips = useCallback(async () => {
    if (!id) return;
    setTripsLoading(true);
    setTripsErr('');
    try {
      const q = new URLSearchParams({
        from_date: tripsFrom,
        to_date: tripsTo,
      });
      const { res, data: j } = await fetchJsonAuth(
        `${API.adminDriverTrips(id)}?${q.toString()}`,
      );
      if (!res.ok || !isTruthyApi(j.success)) {
        throw new Error(String(j.message ?? res.statusText));
      }
      const data = asRecord(j.data) ?? {};
      const list = Array.isArray(data.trips) ? data.trips : [];
      setTrips(
        list
          .map((e) => asRecord(e))
          .filter((e): e is Record<string, unknown> => e != null),
      );
      setTripsSummary(asRecord(data.summary));
    } catch (e) {
      setTripsErr(String(e));
      setTrips([]);
      setTripsSummary(null);
    } finally {
      setTripsLoading(false);
    }
  }, [id, tripsFrom, tripsTo]);

  useEffect(() => {
    void loadTrips();
  }, [loadTrips]);

  const loadWallet = useCallback(async () => {
    if (!id) return;
    setWalletLoading(true);
    setWalletErr('');
    try {
      const { res, data: j } = await fetchJsonAuth(API.driverWallet(id));
      if (!res.ok || !isTruthyApi(j.success)) {
        throw new Error(String(j.message ?? res.statusText));
      }
      const data = asRecord(j.data) ?? {};
      const wallet = asRecord(data.wallet) ?? {};
      setWalletBalance(Number(wallet.balance ?? 0));
      setWalletCurrency(String(wallet.currency ?? 'SYP'));
      const list = Array.isArray(data.transactions) ? data.transactions : [];
      setWalletTxs(
        list
          .map((e) => asRecord(e))
          .filter((e): e is Record<string, unknown> => e != null),
      );
    } catch (e) {
      setWalletErr(String(e));
      setWalletBalance(0);
      setWalletTxs([]);
    } finally {
      setWalletLoading(false);
    }
  }, [id]);

  useEffect(() => {
    void loadWallet();
  }, [loadWallet]);

  async function submitWalletAction(kind: 'reward' | 'withdraw' | 'violation') {
    if (!id) return;
    const amount = Number(walletAmount);
    if (!Number.isFinite(amount) || amount <= 0) {
      alert('أدخل مبلغاً موجباً');
      return;
    }
    const label =
      kind === 'reward' ? 'مكافأة' : kind === 'violation' ? 'مخالفة' : 'سحب';
    const confirmMsg =
      kind === 'withdraw'
        ? `سحب ${amount} من محفظة السائق؟ سيظهر فوراً في التطبيق.`
        : kind === 'violation'
          ? `خصم ${amount} كمخالفة من محفظة السائق؟`
          : `إضافة مكافأة ${amount} لمحفظة السائق؟`;
    if (!window.confirm(confirmMsg)) {
      return;
    }
    setWalletBusy(true);
    try {
      const url =
        kind === 'reward'
          ? API.driverWalletReward(id)
          : kind === 'violation'
            ? API.driverWalletViolation(id)
            : API.driverWalletWithdraw(id);
      const { res, data } = await postJson<Record<string, unknown>>(url, {
        amount,
        note:
          walletNote.trim() ||
          (kind === 'violation' ? 'مخالفة' : undefined),
      });
      if (res.ok && data.success === true) {
        alert(String(data.message ?? `تم ${label}`));
        setWalletAmount('');
        setWalletNote('');
        void loadWallet();
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } catch (e) {
      alert(String(e));
    } finally {
      setWalletBusy(false);
    }
  }

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoadingCat(true);
      try {
        const list = await loadCarTypesForPricing();
        if (!cancelled) setCategories(list);
      } finally {
        if (!cancelled) setLoadingCat(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!categories.length || !row) return;
    const tid = carTypeIdFromRow(row);
    const valid = tid > 0 && categories.some((c) => Number(c.id) === tid);
    const first = Number(categories[0]?.id ?? 0);
    setCarTypeId(valid ? tid : first > 0 ? first : 0);
  }, [categories, row]);

  async function save() {
    if (!id) return;
    if (!carTypeId) {
      alert('اختر الفئة التسعيرية');
      return;
    }
    const fd = new FormData();
    fd.append('firstName', firstName.trim());
    fd.append('lastName', lastName.trim());
    fd.append('number', number.trim());
    if (password.trim()) fd.append('password', password.trim());
    fd.append('CarTypeId', String(carTypeId));
    fd.append('carNumber', carNumber.trim());
    fd.append('insurance', insurance.trim());
    fd.append('mechanics', mechanics.trim());
    fd.append('vehicle_model', vehicleModel.trim());
    fd.append('typeCar', typeCar);
    if (imgDriver) fd.append('image', imgDriver);
    if (imgId) fd.append('IDImage', imgId);
    if (imgCar) fd.append('carImage', imgCar);

    setBusy(true);
    try {
      const { res, data } = await postFormData(API.driverUpdate(id), fd);
      const d = data as Record<string, unknown>;
      const saved = res.ok && (isTruthyApi(d.success) || isTruthyApi(d.state));
      if (saved) {
        alert('تم');
        nav('/drivers', { replace: true });
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    if (!id) return;
    if (!window.confirm('حذف السائق؟ (Soft delete)')) return;
    const { res, data: j } = await deleteJson(API.driverDestroy(id));
    if (res.ok && (isTruthyApi(j.success) || isTruthyApi(j.state))) {
      alert('تم');
      nav('/drivers', { replace: true });
    } else {
      alert(formatApiFailure(j, JSON.stringify(j)));
    }
  }

  if (!id) {
    return (
      <div className="page-pad">
        <p className="text-err">معرّف غير صالح</p>
      </div>
    );
  }

  if (loadingRow && !loadErr && !row) {
    return (
      <div className="page-center">
        <div className="spinner" />
      </div>
    );
  }

  if ((loadErr && !row) || (!row && !loadingRow)) {
    return (
      <div className="page-pad">
        <Link to="/drivers" className="link-back">
          ← السائقون
        </Link>
        <p className="text-err">{loadErr || 'تعذر تحميل بيانات السائق'}</p>
        {loadErr && (
          <button type="button" className="btn-ghost" onClick={() => void loadDriver()}>
            إعادة المحاولة
          </button>
        )}
      </div>
    );
  }

  if (!row) {
    return (
      <div className="page-center">
        <div className="spinner" />
      </div>
    );
  }

  return (
    <div className="page-pad">
      {loadErr && row && (
        <p className="text-err" style={{ marginBottom: 12 }}>
          تحذير: {loadErr} — تُعرض البيانات المتاحة (من القائمة أو آخر تحميل ناجح).
        </p>
      )}
      <div className="row-between wrap">
        <div>
          <Link to="/drivers" className="link-back">
            ← السائقون
          </Link>
          <h2 className="page-title">سائق #{id}</h2>
        </div>
        <button type="button" className="btn-warn" onClick={() => void remove()}>
          حذف السائق
        </button>
      </div>

      {loadingCat && <p className="text-muted">جاري تحميل الفئات…</p>}

      <h4 className="mt">بيانات السائق</h4>
      <div className="card stack-tight">
        <label>
          الاسم الأول
          <input value={firstName} onChange={(e) => setFirstName(e.target.value)} />
        </label>
        <label>
          الاسم الأخير
          <input value={lastName} onChange={(e) => setLastName(e.target.value)} />
        </label>
        <label>
          رقم الهاتف
          <input value={number} onChange={(e) => setNumber(e.target.value)} />
        </label>
        <label>
          كلمة سر جديدة (اختياري)
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
        </label>
      </div>

      <h4 className="mt">المركبة والفئة</h4>
      <div className="card stack-tight">
        <label>
          الفئة التسعيرية *
          <select
            value={carTypeId ? String(carTypeId) : ''}
            onChange={(e) => setCarTypeId(Number(e.target.value))}
            disabled={!categories.length}
          >
            {categories.map((c) => {
              const cid = Number(c.id ?? 0);
              if (cid <= 0) return null;
              return (
                <option key={cid} value={String(cid)}>
                  {String(c.name ?? cid)}
                </option>
              );
            })}
          </select>
        </label>
        <label>
          نوع المركبة *
          <select value={typeCar} onChange={(e) => setTypeCar(e.target.value)}>
            {VEHICLE_TYPE_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
        </label>
        <label>
          نوع السيارة (الماركة)
          <input
            value={vehicleModel}
            onChange={(e) => setVehicleModel(e.target.value)}
            placeholder="مثال: كيا، هونداي…"
          />
        </label>
        <label>
          رقم اللوحة
          <input value={carNumber} onChange={(e) => setCarNumber(e.target.value)} />
        </label>
        <label>
          التأمين
          <input value={insurance} onChange={(e) => setInsurance(e.target.value)} />
        </label>
        <label>
          الميكانيك
          <input value={mechanics} onChange={(e) => setMechanics(e.target.value)} />
        </label>
      </div>

      <h4 className="mt">صور جديدة (اختياري)</h4>
      <div className="card stack-tight">
        <label>
          صورة السائق
          <input type="file" accept="image/*" onChange={(e) => setImgDriver(e.target.files?.[0] ?? null)} />
        </label>
        <label>
          صورة الهوية
          <input type="file" accept="image/*" onChange={(e) => setImgId(e.target.files?.[0] ?? null)} />
        </label>
        <label>
          صورة السيارة
          <input type="file" accept="image/*" onChange={(e) => setImgCar(e.target.files?.[0] ?? null)} />
        </label>
      </div>

      <h4 className="mt">محفظة السائق</h4>
      <div className="card stack-tight">
        <div className="row-between wrap" style={{ gap: 12, alignItems: 'center' }}>
          <p style={{ margin: 0, fontSize: 18, fontWeight: 700 }}>
            الرصيد:{' '}
            <span style={{ color: 'var(--accent, #0ea5e9)' }}>
              {walletBalance.toLocaleString('ar-SY')} {walletCurrency === 'SYP' ? 'ل.س' : walletCurrency}
            </span>
          </p>
          <button
            type="button"
            className="btn-ghost"
            disabled={walletLoading || walletBusy}
            onClick={() => void loadWallet()}
          >
            تحديث
          </button>
        </div>
        <p className="text-muted" style={{ margin: 0, fontSize: 13 }}>
          المكافأة تضيف رصيداً · المخالفة تخصم · السحب ينقل للسائق ويظهر فوراً في التطبيق.
        </p>
        {walletLoading && <p className="text-muted">جاري تحميل المحفظة…</p>}
        {walletErr && <p className="text-err">{walletErr}</p>}
        <div className="row-between wrap" style={{ gap: 12 }}>
          <label style={{ flex: 1, minWidth: 140 }}>
            المبلغ
            <input
              type="number"
              min="0"
              step="0.01"
              value={walletAmount}
              onChange={(e) => setWalletAmount(e.target.value)}
              placeholder="0"
              disabled={walletBusy}
            />
          </label>
          <label style={{ flex: 2, minWidth: 180 }}>
            ملاحظة (اختياري)
            <input
              value={walletNote}
              onChange={(e) => setWalletNote(e.target.value)}
              placeholder="سبب المكافأة / المخالفة / السحب"
              disabled={walletBusy}
            />
          </label>
        </div>
        <div className="row-gap" style={{ gap: 8, flexWrap: 'wrap' }}>
          <button
            type="button"
            className="btn-primary"
            disabled={walletBusy}
            onClick={() => void submitWalletAction('reward')}
          >
            إضافة مكافأة
          </button>
          <button
            type="button"
            className="btn-warn"
            disabled={walletBusy}
            onClick={() => void submitWalletAction('violation')}
          >
            مخالفة (خصم)
          </button>
          <button
            type="button"
            className="btn-ghost"
            disabled={walletBusy || walletBalance <= 0}
            onClick={() => void submitWalletAction('withdraw')}
          >
            سحب من المحفظة
          </button>
        </div>
        {walletTxs.length > 0 && (
          <div style={{ overflowX: 'auto' }}>
            <table className="data-table" style={{ width: '100%', fontSize: 13 }}>
              <thead>
                <tr>
                  <th>النوع</th>
                  <th>المبلغ</th>
                  <th>بعد العملية</th>
                  <th>الراكب</th>
                  <th>ملاحظة</th>
                  <th>التاريخ</th>
                </tr>
              </thead>
              <tbody>
                {walletTxs.map((tx) => {
                  const amt = Number(tx.amount ?? 0);
                  return (
                    <tr key={String(tx.id)}>
                      <td>{String(tx.type_label ?? tx.type ?? '')}</td>
                      <td style={{ color: amt < 0 ? '#b91c1c' : '#15803d', fontWeight: 600 }}>
                        {amt > 0 ? '+' : ''}
                        {amt.toLocaleString('ar-SY')}
                      </td>
                      <td>{Number(tx.balance_after ?? 0).toLocaleString('ar-SY')}</td>
                      <td>{String(tx.customer_name ?? '—')}</td>
                      <td>{String(tx.note ?? '—')}</td>
                      <td>
                        {tx.created_at
                          ? new Date(String(tx.created_at)).toLocaleString('ar-SY')
                          : '—'}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        {!walletLoading && !walletErr && walletTxs.length === 0 && (
          <p className="text-muted">لا حركات بعد</p>
        )}
      </div>

      <h4 className="mt">رحلات السائق</h4>
      <div className="card stack-tight">
        <div className="row-between wrap" style={{ gap: 12 }}>
          <label>
            من تاريخ
            <input
              type="date"
              value={tripsFrom}
              onChange={(e) => setTripsFrom(e.target.value)}
            />
          </label>
          <label>
            إلى تاريخ
            <input
              type="date"
              value={tripsTo}
              onChange={(e) => setTripsTo(e.target.value)}
            />
          </label>
          <button type="button" className="btn-ghost" onClick={() => void loadTrips()}>
            تحديث
          </button>
        </div>
        {tripsSummary && (
          <p className="text-muted" style={{ margin: 0 }}>
            المجموع: {String(tripsSummary.trips_count ?? 0)} · تطبيق:{' '}
            {String(tripsSummary.app_trips ?? 0)} · عداد حر:{' '}
            {String(tripsSummary.free_meter_trips ?? 0)} · أجور:{' '}
            {String(tripsSummary.total_fare ?? 0)} ل.س
          </p>
        )}
        {tripsLoading && <p className="text-muted">جاري تحميل الرحلات…</p>}
        {tripsErr && <p className="text-err">{tripsErr}</p>}
        {!tripsLoading && !tripsErr && trips.length === 0 && (
          <p className="text-muted">لا توجد رحلات في هذا التاريخ</p>
        )}
        {trips.length > 0 && (
          <>
            <TripTable
              title="رحلات طلب التطبيق"
              trips={trips.filter(
                (t) => !String(t.billing_kind ?? '').includes('free_meter'),
              )}
            />
            <TripTable
              title="رحلات العداد الحر"
              trips={trips.filter((t) =>
                String(t.billing_kind ?? '').includes('free_meter'),
              )}
            />
          </>
        )}
      </div>

      <button
        type="button"
        className="btn-primary"
        style={{ marginTop: 20 }}
        disabled={busy}
        onClick={() => void save()}
      >
        {busy ? 'جاري الحفظ…' : 'حفظ التعديلات'}
      </button>
    </div>
  );
}

function TripTable({
  title,
  trips,
}: {
  title: string;
  trips: Record<string, unknown>[];
}) {
  return (
    <div style={{ marginTop: 12 }}>
      <h5 style={{ margin: '0 0 8px' }}>{title}</h5>
      {trips.length === 0 ? (
        <p className="text-muted" style={{ margin: 0 }}>
          لا توجد رحلات
        </p>
      ) : (
        <div style={{ overflowX: 'auto' }}>
          <table className="table">
            <thead>
              <tr>
                <th>#</th>
                <th>النوع</th>
                <th>الوقت</th>
                <th>المسافة</th>
                <th>الأجرة</th>
              </tr>
            </thead>
            <tbody>
              {trips.map((t) => {
                const tid = String(t.id ?? '');
                const path =
                  String(t.path_label ?? '') ||
                  (String(t.billing_kind ?? '').includes('free_meter')
                    ? 'رحلة عداد حر'
                    : 'رحلة تطبيق');
                const when = String(
                  t.trip_started_at ?? t.requestDate ?? t.created_at ?? '',
                );
                const km = t.distance_traveled_km ?? t.distanceTraveledKm ?? '—';
                const cost = t.final_cost ?? t.finalCost ?? '—';
                return (
                  <tr key={tid}>
                    <td>
                      <Link to={`/requests/${tid}`}>{tid}</Link>
                    </td>
                    <td>{path}</td>
                    <td>{when}</td>
                    <td>{String(km)}</td>
                    <td>{String(cost)} ل.س</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
