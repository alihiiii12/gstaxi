import { API } from './endpoints';

export function authHeaders(): HeadersInit {
  const token = localStorage.getItem('token') ?? '';
  return {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'Accept-Language': 'ar',
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };
}

export const SERVICE_CUT_CODE = 'SERVICE_CUT';
export const SERVICE_CUT_EVENT = 'gstaxi-service-cut';

export function notifyServiceCut(): void {
  try {
    sessionStorage.setItem('service_cut', '1');
  } catch {
    /* ignore */
  }
  window.dispatchEvent(new Event(SERVICE_CUT_EVENT));
}

export function clearServiceCutFlag(): void {
  try {
    sessionStorage.removeItem('service_cut');
  } catch {
    /* ignore */
  }
}

function raiseIfServiceCut(
  data: Record<string, unknown>,
  res: Response,
): void {
  if (data.code === SERVICE_CUT_CODE || (res.status === 503 && data.code === SERVICE_CUT_CODE)) {
    notifyServiceCut();
    throw new Error(
      typeof data.message === 'string' && data.message.trim()
        ? data.message
        : 'تم قطع الاتصال بالخادم مؤقتاً',
    );
  }
}

/** يقرأ JSON بأمان — يتجنّب SyntaxError عند رد HTML (503 nginx، 500، إلخ). */
export async function readJsonResponse(
  res: Response,
): Promise<Record<string, unknown>> {
  const text = await res.text();
  try {
    const data = JSON.parse(text) as Record<string, unknown>;
    raiseIfServiceCut(data, res);
    return data;
  } catch (e) {
    if (e instanceof Error && e.message.includes('قطع الاتصال')) throw e;
    const trimmed = text.trim();
    if (res.status === 503 || trimmed.includes('503 Service')) {
      throw new Error(
        'الخادم مشغول مؤقتاً (503). حدّث إعداد nginx على السيرفر — لا تضع limit_req على كل الطلبات.',
      );
    }
    if (trimmed.startsWith('<')) {
      throw new Error(
        trimmed.slice(0, 180) ||
          `الخادم أعاد صفحة HTML بدل JSON (${res.status})`,
      );
    }
    throw new Error(trimmed.slice(0, 200) || `تعذر قراءة رد الخادم (${res.status})`);
  }
}

export async function fetchJsonAuth(
  url: string,
  init?: RequestInit,
): Promise<{ res: Response; data: Record<string, unknown> }> {
  const res = await fetch(url, {
    ...init,
    headers: { ...authHeaders(), ...(init?.headers as Record<string, string> | undefined) },
  });
  const data = await readJsonResponse(res);
  return { res, data };
}

export async function getJson<T>(url: string): Promise<T> {
  const { res, data } = await fetchJsonAuth(url);
  if (!res.ok) {
    const msg =
      typeof data.message === 'string' && data.message.trim()
        ? data.message
        : res.statusText;
    throw new Error(msg);
  }
  return data as T;
}

export async function postJson<T>(
  url: string,
  body: unknown,
): Promise<{ res: Response; data: T }> {
  const res = await fetch(url, {
    method: 'POST',
    headers: authHeaders(),
    body: JSON.stringify(body),
  });
  const data = (await readJsonResponse(res)) as T;
  return { res, data };
}

export async function putJson<T>(
  url: string,
  body: unknown,
): Promise<{ res: Response; data: T }> {
  const res = await fetch(url, {
    method: 'PUT',
    headers: authHeaders(),
    body: JSON.stringify(body),
  });
  const data = (await readJsonResponse(res)) as T;
  return { res, data };
}

/** POST multipart — لا تُمرَّر Content-Type يدوياً */
export async function postFormData(
  url: string,
  form: FormData,
): Promise<{ res: Response; data: unknown }> {
  const token = localStorage.getItem('token') ?? '';
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Accept-Language': 'ar',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: form,
  });
  const text = await res.text();
  let data: unknown;
  try {
    data = JSON.parse(text) as unknown;
  } catch {
    data = { message: text };
  }
  if (
    data &&
    typeof data === 'object' &&
    (data as Record<string, unknown>).code === SERVICE_CUT_CODE
  ) {
    notifyServiceCut();
  }
  return { res, data };
}

export async function deleteJson<T = Record<string, unknown>>(
  url: string,
): Promise<{ res: Response; data: T }> {
  const res = await fetch(url, { method: 'DELETE', headers: authHeaders() });
  const text = await res.text();
  let data: T;
  try {
    data = JSON.parse(text) as T;
  } catch {
    data = { message: text } as T;
  }
  if (
    data &&
    typeof data === 'object' &&
    (data as Record<string, unknown>).code === SERVICE_CUT_CODE
  ) {
    notifyServiceCut();
  }
  return { res, data };
}

/**
 * تسجيل دخول لوحة التحكم — JSON + Bearer token (مثل تطبيق Flutter).
 * لا يعتمد على كوكي Sanctum/CSRF لتجنّب فشل الدخول على الإنتاج.
 */
export async function postFormLogin(
  number: string,
  password: string,
): Promise<unknown> {
  const res = await fetch(API.login, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Accept-Language': 'ar',
      'Content-Type': 'application/json',
      // مطلوب لدخول الأدمن/الموظف — التطبيق لا يرسل هذا الرأس فيُرفض.
      'X-Client': 'web-admin',
    },
    body: JSON.stringify({
      number: number.trim(),
      password,
    }),
  });
  const text = await res.text();
  try {
    const data = JSON.parse(text) as Record<string, unknown>;
    if (data.code === SERVICE_CUT_CODE) {
      notifyServiceCut();
    }
    if (!res.ok) {
      if (data.message == null || String(data.message).trim() === '') {
        data.message =
          data.code === SERVICE_CUT_CODE
            ? 'تم قطع الاتصال بالخادم مؤقتاً'
            : res.status === 419
              ? 'CSRF على السيرفر — ارفع bootstrap/app.php الجديد ثم: php artisan config:cache'
              : res.status === 500
                ? 'خطأ 500 في الخادم — راجع Laravel (migrate / personal_access_tokens)'
                : `خطأ من الخادم (${res.status})`;
      }
      data.success = false;
      data.state = false;
    }
    return data;
  } catch {
    const snippet = text.trim().slice(0, 280);
    return {
      success: false,
      state: false,
      message:
        snippet ||
        (res.status === 500
          ? 'الخادم يعيد خطأ 500 بدون رسالة — ارفع UserController.php ونفّذ php artisan migrate'
          : `تعذر قراءة رد الخادم (${res.status})`),
    };
  }
}
