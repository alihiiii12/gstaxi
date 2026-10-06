import { API } from './endpoints';
import { fetchJsonAuth } from './http';

const FREE_METER_NAME = 'العداد الحر';

function sortOrder(e: Record<string, unknown>): number {
  const v = e.sort_order ?? e.sortOrder;
  return Number(v) || 0;
}

export function sortCarTypes(list: Record<string, unknown>[]): void {
  list.sort((a, b) => {
    const sa = sortOrder(a);
    const sb = sortOrder(b);
    if (sa !== sb) return sa - sb;
    return (Number(a.id) || 0) - (Number(b.id) || 0);
  });
}

/** فئات التسعير لطلب التطبيق — يستبعد «العداد الحر» كما في Flutter */
export async function loadCarTypesForPricing(): Promise<
  Record<string, unknown>[]
> {
  const { data: j } = await fetchJsonAuth(API.carTypesIndex);
  if (j.success !== true || !Array.isArray(j.carTypes)) return [];
  const list = (j.carTypes as Record<string, unknown>[]).map((e) => ({ ...e }));
  const filtered = list.filter(
    (e) => String(e.name ?? '').trim() !== FREE_METER_NAME,
  );
  const out = filtered.length > 0 ? filtered : list;
  sortCarTypes(out);
  return out;
}
