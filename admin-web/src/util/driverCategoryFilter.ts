export function transTypeIdFromDriverRow(row: Record<string, unknown>): number {
  const direct = Number(row.transTypeId ?? row.trans_type_id ?? 0);
  if (direct > 0) return direct;
  const t = row.transType ?? row.trans_type;
  if (t && typeof t === 'object') {
    return Number((t as Record<string, unknown>).id ?? 0);
  }
  return 0;
}

export function vehicleModelFromRow(row: Record<string, unknown>): string {
  return String(row.vehicle_model ?? row.vehicleModel ?? '').trim();
}
