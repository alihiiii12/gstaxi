import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { API } from '../api/endpoints';
import { postFormData } from '../api/http';
import { loadCarTypesForPricing } from '../api/carTypes';
import { formatApiFailure } from '../util/apiError';
import { VEHICLE_TYPE_OPTIONS } from '../util/vehicleTypeOptions';

export function DriverRegisterPage() {
  const nav = useNavigate();
  const [categories, setCategories] = useState<Record<string, unknown>[]>([]);
  const [loadingCat, setLoadingCat] = useState(true);
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [number, setNumber] = useState('');
  const [password, setPassword] = useState('');
  const [carNumber, setCarNumber] = useState('');
  const [insurance, setInsurance] = useState('');
  const [mechanics, setMechanics] = useState('');
  const [vehicleModel, setVehicleModel] = useState('');
  const [typeCar, setTypeCar] = useState('car');
  const [carTypeId, setCarTypeId] = useState<number>(0);
  const [imgDriver, setImgDriver] = useState<File | null>(null);
  const [imgId, setImgId] = useState<File | null>(null);
  const [imgCar, setImgCar] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoadingCat(true);
      try {
        const list = await loadCarTypesForPricing();
        if (!cancelled) {
          setCategories(list);
          const firstId = Number(list[0]?.id ?? 0);
          setCarTypeId(firstId > 0 ? firstId : 0);
        }
      } finally {
        if (!cancelled) setLoadingCat(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  async function submit() {
    if (!carTypeId) {
      alert('اختر الفئة التسعيرية');
      return;
    }
    if (!imgDriver || !imgId || !imgCar) {
      alert('اختر صورة السائق وصورة الهوية وصورة السيارة');
      return;
    }
    const fd = new FormData();
    fd.append('firstName', firstName.trim());
    fd.append('lastName', lastName.trim());
    fd.append('number', number.trim());
    fd.append('password', password);
    fd.append('CarTypeId', String(carTypeId));
    fd.append('carNumber', carNumber.trim());
    fd.append('insurance', insurance.trim());
    fd.append('mechanics', mechanics.trim());
    fd.append('vehicle_model', vehicleModel.trim());
    fd.append('typeCar', typeCar);
    fd.append('image', imgDriver);
    fd.append('IDImage', imgId);
    fd.append('carImage', imgCar);

    setBusy(true);
    try {
      const { res, data } = await postFormData(API.driversStore, fd);
      const d = data as Record<string, unknown>;
      if ((res.status === 200 || res.status === 201) && d.success === true) {
        alert(String(d.message ?? 'أُضيف السائق'));
        nav('/drivers', { replace: true });
      } else {
        alert(formatApiFailure(data, JSON.stringify(data)));
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="page-pad">
      <Link to="/drivers" className="link-back">
        ← السائقون
      </Link>
      <h2 className="page-title">إضافة سائق</h2>
      {loadingCat && <p className="text-muted">جاري تحميل الفئات…</p>}
      {!loadingCat && !categories.length && (
        <p className="text-err">تعذّر تحميل الفئات. عرّف فئة من «فئات السيارة» أولاً.</p>
      )}

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
          كلمة السر
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
        </label>
      </div>

      <h4 className="mt">المركبة والفئة</h4>
      <div className="card stack-tight">
        <label>
          الفئة التسعيرية *
          <select
            value={carTypeId || ''}
            onChange={(e) => setCarTypeId(Number(e.target.value))}
            disabled={!categories.length}
          >
            {categories.map((c) => {
              const id = Number(c.id ?? 0);
              if (id <= 0) return null;
              return (
                <option key={id} value={id}>
                  {String(c.name ?? id)}
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
            placeholder="مثال: كيا، هونداي، تويوتا…"
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

      <h4 className="mt">الصور</h4>
      <div className="card stack-tight">
        <label>
          صورة السائق *
          <input type="file" accept="image/*" onChange={(e) => setImgDriver(e.target.files?.[0] ?? null)} />
        </label>
        <label>
          صورة الهوية *
          <input type="file" accept="image/*" onChange={(e) => setImgId(e.target.files?.[0] ?? null)} />
        </label>
        <label>
          صورة السيارة *
          <input type="file" accept="image/*" onChange={(e) => setImgCar(e.target.files?.[0] ?? null)} />
        </label>
      </div>

      <button
        type="button"
        className="btn-primary"
        style={{ marginTop: 20 }}
        disabled={busy || loadingCat || !categories.length}
        onClick={() => void submit()}
      >
        {busy ? 'جاري الإرسال…' : 'حفظ السائق'}
      </button>
    </div>
  );
}
