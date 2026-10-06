type Props = {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  label?: string;
  hint?: string;
};

/** شريط بحث موحّد بمظهر أوضح */
export function NameSearchField({
  value,
  onChange,
  placeholder,
  label,
  hint,
}: Props) {
  return (
    <div className="search-bar">
      <label className="search-bar-label">
        <span className="search-bar-caption">
          {label ?? 'بحث بالاسم (الاسم الأول أو الأخير)'}
        </span>
        <div className="search-bar-field">
          <span className="search-bar-icon" aria-hidden>
            ⌕
          </span>
          <input
            type="search"
            className="search-bar-input"
            value={value}
            onChange={(e) => onChange(e.target.value)}
            placeholder={placeholder ?? 'مثال: أحمد، محمد، الدمشقي…'}
            dir="rtl"
            autoComplete="off"
          />
          {value ? (
            <button
              type="button"
              className="search-bar-clear"
              aria-label="مسح البحث"
              onClick={() => onChange('')}
            >
              ✕
            </button>
          ) : null}
        </div>
      </label>
      {hint ? <p className="search-bar-hint">{hint}</p> : null}
    </div>
  );
}
