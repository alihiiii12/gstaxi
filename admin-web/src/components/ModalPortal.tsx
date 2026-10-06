import { useEffect, type ReactNode } from 'react';
import { createPortal } from 'react-dom';

type Props = {
  children: ReactNode;
  onClose?: () => void;
  className?: string;
};

/**
 * يعرض المحتوى فوق الصفحة بالكامل (document.body)
 * حتى لا يظهر المودال «في نصف الصفحة» بسبب تمرير/أنيميشن الحاوية.
 */
export function ModalPortal({ children, onClose, className }: Props) {
  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose?.();
    };
    window.addEventListener('keydown', onKey);
    return () => {
      document.body.style.overflow = prev;
      window.removeEventListener('keydown', onKey);
    };
  }, [onClose]);

  return createPortal(
    <div
      className={className ?? 'modal-backdrop'}
      role="presentation"
      onClick={() => onClose?.()}
    >
      {children}
    </div>,
    document.body,
  );
}
