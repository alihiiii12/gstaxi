/** قيم عمود drivers.type — تُرسل كـ typeCar للـ API */
export const VEHICLE_TYPE_OPTIONS = [
  { value: 'car', label: 'سيارة' },
  { value: 'van_large', label: 'فان كبير' },
  { value: 'van_small', label: 'فان صغير' },
] as const;

export type VehicleTypeValue = (typeof VEHICLE_TYPE_OPTIONS)[number]['value'];

export function vehicleTypeLabel(type: string | null | undefined): string {
  const t = String(type ?? '').trim();
  const found = VEHICLE_TYPE_OPTIONS.find((o) => o.value === t);
  if (found) return found.label;
  if (t === 'motorcycle') return 'دراجة';
  return t;
}

export function normalizeVehicleTypeValue(
  raw: string | null | undefined,
): VehicleTypeValue {
  const t = String(raw ?? '').trim();
  if (VEHICLE_TYPE_OPTIONS.some((o) => o.value === t)) {
    return t as VehicleTypeValue;
  }
  return 'car';
}
