import { Link } from 'react-router-dom';
import type { ReactNode } from 'react';

type Props = {
  title: string;
  subtitle?: string;
  brand?: string;
  backTo?: string;
  backLabel?: string;
  onRefresh?: () => void;
  refreshing?: boolean;
  actions?: ReactNode;
  compact?: boolean;
};

/** رأس موحّد لكل صفحات لوحة الإدارة */
export function PageHeader({
  title,
  subtitle,
  brand = 'GS TAXI',
  backTo,
  backLabel = 'رجوع',
  onRefresh,
  refreshing = false,
  actions,
  compact = false,
}: Props) {
  return (
    <header className={`page-chrome${compact ? ' page-chrome-compact' : ''}`}>
      <div className="page-chrome-main">
        {backTo && (
          <Link to={backTo} className="link-back page-chrome-back">
            ← {backLabel}
          </Link>
        )}
        <p className="page-chrome-brand">{brand}</p>
        <h2 className="page-chrome-title">{title}</h2>
        {subtitle ? <p className="page-chrome-sub">{subtitle}</p> : null}
      </div>
      <div className="page-chrome-actions">
        {actions}
        {onRefresh && (
          <button
            type="button"
            className="btn-ghost"
            disabled={refreshing}
            onClick={onRefresh}
          >
            {refreshing ? 'جاري التحديث…' : 'تحديث'}
          </button>
        )}
      </div>
    </header>
  );
}
