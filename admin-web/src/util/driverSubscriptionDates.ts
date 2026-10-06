function parseDate(raw: unknown): Date | null {
  if (raw == null || raw === '') return null;
  const d = new Date(String(raw));
  return Number.isNaN(d.getTime()) ? null : d;
}

export function formatDateAr(d: Date): string {
  return d.toLocaleDateString('ar-SY', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

/** بداية ونهاية الاشتراك للعرض في بطاقة السائق. */
export function driverSubscriptionDateLines(
  row: Record<string, unknown>,
): string[] {
  const lines: string[] = [];
  let ends = parseDate(
    row.subscription_ends_at ?? row.subscriptionEndsAt,
  );
  let starts = parseDate(
    row.subscription_starts_at ?? row.subscriptionStartsAt,
  );
  if (!starts && ends) {
    starts = new Date(ends.getTime() - 30 * 24 * 60 * 60 * 1000);
  }
  if (!starts) {
    starts = parseDate(row.created_at ?? row.createdAt);
  }
  if (starts && !ends) {
    ends = new Date(starts.getTime() + 30 * 24 * 60 * 60 * 1000);
  }

  if (starts) {
    lines.push(`بداية الاشتراك: ${formatDateAr(starts)}`);
  }
  if (ends) {
    lines.push(`نهاية الاشتراك: ${formatDateAr(ends)}`);
  }

  const blocked =
    row.subscription_blocked === true ||
    row.subscription_blocked === 1 ||
    row.subscriptionBlocked === true;
  const active =
    row.subscription_active === true || row.subscriptionActive === true;

  if (blocked) {
    lines.push('الحالة: محظور — قم بالدفع');
  } else if (ends && ends.getTime() < Date.now()) {
    lines.push('الحالة: منتهٍ — قم بالدفع');
  } else if (active || (ends && ends.getTime() > Date.now())) {
    const days = ends
      ? Math.ceil((ends.getTime() - Date.now()) / (24 * 60 * 60 * 1000))
      : 30;
    lines.push(`الحالة: ساري (${days} يوم متبقٍ)`);
  } else if (!ends && starts) {
    lines.push('الحالة: ساري');
  }

  return lines;
}

export function isDriverSubscriptionBlocked(row: Record<string, unknown>): boolean {
  return (
    row.subscription_blocked === true ||
    row.subscription_blocked === 1 ||
    row.subscriptionBlocked === true
  );
}
