function hasDriver(driverId: unknown): boolean {
  if (driverId == null) return false;
  const n = parseInt(String(driverId), 10);
  return !Number.isNaN(n) && n > 0;
}

export function statusArabic(apiStatus: string | undefined, driverId?: unknown): string {
  switch (apiStatus) {
    case 'Pending':
      return hasDriver(driverId) ? 'قيد الانتظار' : 'قيد الانتظار (لم يُقبل بعد)';
    case 'Reserved':
      return 'غير مكتملة — تم قبول السائق (محجوز)';
    case 'DriverArrived':
      return 'غير مكتملة — وصل السائق';
    case 'AwaitingDestination':
      return 'غير مكتملة — بانتظار تحديد الوجهة';
    case 'Running':
      return 'جارية';
    case 'Finished':
      return 'مكتملة';
    case 'Removed':
      return 'ملغاة';
    default: {
      const s = apiStatus?.trim();
      return !s ? '—' : s;
    }
  }
}

export function typeArabic(apiType: string | undefined): string {
  switch (apiType) {
    case 'Immediate':
      return 'طلب فوري';
    case 'Schedual':
      return 'حجز مسبق';
    default:
      return apiType ?? '—';
  }
}
