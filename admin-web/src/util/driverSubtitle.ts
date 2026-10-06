import { driverSubscriptionDateLines } from './driverSubscriptionDates';
import { vehicleModelFromRow } from './driverCategoryFilter';
import { vehicleTypeLabel } from './vehicleTypeOptions';

export function adminDriverCardSubtitle(
  row: Record<string, unknown>,
  user: Record<string, unknown>,
): string {
  const plate = String(
    row['car_number'] ?? row['carNumber'] ?? '',
  ).trim();
  let trans: Record<string, unknown> | undefined;
  const a = row['transType'];
  const b = row['trans_type'];
  if (a && typeof a === 'object') trans = a as Record<string, unknown>;
  else if (b && typeof b === 'object') trans = b as Record<string, unknown>;
  const cat = String(trans?.['name'] ?? '').trim();
  const model = vehicleModelFromRow(row);
  const vType = vehicleTypeLabel(
    String(row['type'] ?? row['typeCar'] ?? row['type_car'] ?? ''),
  );
  const phone = String(user['number'] ?? '').trim();
  const lines = [`لوحة: ${plate || '—'}`];
  if (vType) lines.push(`نوع المركبة: ${vType}`);
  if (model) lines.push(`ماركة/موديل: ${model}`);
  if (cat) lines.push(`فئة التسعير: ${cat}`);
  if (phone) lines.push(`هاتف السائق: ${phone}`);
  lines.push(...driverSubscriptionDateLines(row));
  return lines.join('\n');
}
