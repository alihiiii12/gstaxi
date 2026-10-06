/** رسالة خطأ من استجابة Laravel JSON */
export function formatApiFailure(
  data: unknown,
  fallbackText: string,
): string {
  if (data && typeof data === 'object') {
    const o = data as Record<string, unknown>;
    const msg = o.message != null ? String(o.message) : '';
    const errs = o.errors;
    if (errs && typeof errs === 'object' && !Array.isArray(errs)) {
      const lines: string[] = [];
      for (const v of Object.values(errs as Record<string, unknown>)) {
        if (Array.isArray(v) && v.length > 0) lines.push(`• ${String(v[0])}`);
      }
      if (lines.length > 0) {
        return [msg, ...lines.slice(0, 8)].filter(Boolean).join('\n');
      }
    }
    if (msg.trim()) return msg.trim();
  }
  const b = fallbackText.trim();
  return b.length > 320 ? `${b.slice(0, 320)}…` : b;
}
