/**
 * عرض الأرقام والتواريخ بأرقام لاتينية (0–9) كما في الإنجليزية،
 * مع بقاء النص العربي في الواجهة.
 */

export function formatNumberLatin(
  value: number,
  options?: Intl.NumberFormatOptions,
): string {
  return new Intl.NumberFormat('en-US', {
    maximumFractionDigits: 4,
    minimumFractionDigits: 0,
    ...options,
  }).format(value);
}

export function formatDateLatin(d: Date): string {
  return d.toLocaleDateString('en-GB', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
}

export function formatDateTimeLatin(d: Date): string {
  return d.toLocaleString('en-GB', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: true,
  });
}
