type Props = {
  currentPage: number;
  lastPage: number;
  total: number;
  pageSize: number;
  loading?: boolean;
  onPageChange: (page: number) => void;
};

export function ListPagination({
  currentPage,
  lastPage,
  total,
  pageSize,
  loading = false,
  onPageChange,
}: Props) {
  if (lastPage <= 1 && total <= pageSize) return null;

  const from = total === 0 ? 0 : (currentPage - 1) * pageSize + 1;
  const to = Math.min(currentPage * pageSize, total);

  return (
    <div className="list-pagination row-between wrap">
      <span className="text-muted" style={{ fontSize: 14 }}>
        عرض {from}–{to} من {total}
        {lastPage > 1 ? ` · صفحة ${currentPage} من ${lastPage}` : ''}
      </span>
      <div className="row-gap">
        <button
          type="button"
          className="btn-ghost"
          disabled={loading || currentPage <= 1}
          onClick={() => onPageChange(currentPage - 1)}
        >
          السابق
        </button>
        <button
          type="button"
          className="btn-ghost"
          disabled={loading || currentPage >= lastPage}
          onClick={() => onPageChange(currentPage + 1)}
        >
          التالي
        </button>
      </div>
    </div>
  );
}
