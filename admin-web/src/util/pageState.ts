import { useCallback, useEffect, useRef, useState, type Dispatch, type SetStateAction } from 'react';
import { useNavigationType } from 'react-router-dom';

const PREFIX = 'pageState:';

function read<T>(key: string, fallback: T): T {
  try {
    const raw = sessionStorage.getItem(PREFIX + key);
    return raw == null ? fallback : (JSON.parse(raw) as T);
  } catch {
    return fallback;
  }
}

function write(key: string, value: unknown): void {
  try {
    sessionStorage.setItem(PREFIX + key, JSON.stringify(value));
  } catch {
    /* التخزين ممتلئ أو معطّل — نكمل بدون حفظ */
  }
}

/**
 * مثل useState لكن القيمة تبقى عند مغادرة الصفحة والعودة إليها (طوال جلسة التبويب).
 * المفتاح يجب أن يكون فريداً لكل صفحة/حقل، مثل `requests.status`.
 */
export function usePersistedState<T>(
  key: string,
  initial: T | (() => T),
): [T, Dispatch<SetStateAction<T>>] {
  const [value, setValue] = useState<T>(() =>
    read(key, typeof initial === 'function' ? (initial as () => T)() : initial),
  );
  useEffect(() => {
    write(key, value);
  }, [key, value]);
  return [value, setValue];
}

/** ينفّذ reset عند تغيّر القيم بعد التحميل الأول فقط — حتى لا يُصفَّر رقم الصفحة المحفوظ عند العودة. */
export function useResetOnChange(deps: unknown[], reset: () => void): void {
  const first = useRef(true);
  const resetRef = useRef(reset);
  useEffect(() => {
    resetRef.current = reset;
  });
  useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    resetRef.current();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
}

/**
 * يعيد موضع التمرير عند الرجوع للصفحة (زر الرجوع) بعد أن تُحمَّل البيانات.
 * ready = true عندما تُعرض القائمة.
 */
export function useScrollRestore(key: string, ready: boolean): void {
  const navType = useNavigationType();
  const storageKey = `scroll.${key}`;
  const [initialTarget] = useState<number | null>(() =>
    navType === 'POP' ? read<number | null>(storageKey, null) : null,
  );
  const pending = useRef<number | null>(initialTarget);
  const restored = useRef(initialTarget == null);

  const save = useCallback(() => {
    if (restored.current) write(storageKey, Math.round(window.scrollY));
  }, [storageKey]);

  useEffect(() => {
    let raf = 0;
    const onScroll = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(save);
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('scroll', onScroll);
      save();
    };
  }, [save]);

  useEffect(() => {
    if (!ready || restored.current || pending.current == null) return;
    const target = pending.current;
    let tries = 0;
    let timer = 0;
    const attempt = () => {
      window.scrollTo(0, target);
      tries += 1;
      if (Math.abs(window.scrollY - target) > 4 && tries < 12) {
        timer = window.setTimeout(attempt, 80);
      } else {
        restored.current = true;
        pending.current = null;
      }
    };
    timer = window.setTimeout(attempt, 0);
    return () => window.clearTimeout(timer);
  }, [ready]);
}
