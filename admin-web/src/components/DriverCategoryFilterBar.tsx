type Props = {
  categories: Record<string, unknown>[];
  totalCount: number;
  blockedCount?: number;
  countByCategoryId: Map<number, number>;
  activeId: number | null;
  blockedOnly?: boolean;
  onSelect: (id: number | null) => void;
  onBlockedToggle?: () => void;
};

export function DriverCategoryFilterBar({
  categories,
  totalCount,
  blockedCount = 0,
  countByCategoryId,
  activeId,
  blockedOnly = false,
  onSelect,
  onBlockedToggle,
}: Props) {
  return (
    <div className="chip-row" role="toolbar" aria-label="تصفية السائقين">
      <button
        type="button"
        className={`chip${activeId === null && !blockedOnly ? ' chip-active' : ''}`}
        onClick={() => onSelect(null)}
      >
        الكل ({totalCount})
      </button>
      {onBlockedToggle != null && (
        <button
          type="button"
          className={`chip chip-danger${blockedOnly ? ' chip-active' : ''}`}
          onClick={onBlockedToggle}
        >
          محظورون ({blockedCount})
        </button>
      )}
      {categories.map((c) => {
        const id = Number(c.id ?? 0);
        if (id <= 0) return null;
        const name = String(c.name ?? `فئة ${id}`);
        const n = countByCategoryId.get(id) ?? 0;
        return (
          <button
            key={id}
            type="button"
            className={`chip${activeId === id ? ' chip-active' : ''}`}
            onClick={() => onSelect(id)}
          >
            {name} ({n})
          </button>
        );
      })}
    </div>
  );
}
