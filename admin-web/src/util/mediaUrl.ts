import { API } from '../api/endpoints';

/** جذر موقع Laravel `public` مُستخرج من `.../public/api` */
export function laravelPublicRoot(): string {
  return API.base.replace(/\/api\/?$/i, '');
}

/** يحوّل مساراً نسبياً أو رابطاً كاملاً من الـ API إلى عنوان جاهز للعرض */
export function resolveMediaUrl(raw: unknown): string | undefined {
  const s = typeof raw === 'string' ? raw.trim() : '';
  if (!s) return undefined;
  if (/^https?:\/\//i.test(s)) return s;
  const root = laravelPublicRoot().replace(/\/$/, '');
  if (s.startsWith('/')) return `${root}${s}`;
  return `${root}/${s}`;
}
