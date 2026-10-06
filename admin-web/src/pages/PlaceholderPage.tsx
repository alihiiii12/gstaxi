export function PlaceholderPage({
  title,
  hint,
}: {
  title: string;
  hint: string;
}) {
  return (
    <div className="page-pad">
      <h2 className="page-title">{title}</h2>
      <div className="card">
        <p>{hint}</p>
        <p className="text-muted">
          الـ API جاهزة في المشروع (`api_endpoints.dart`)؛ يمكن نقل نفس المنطق من شاشات Flutter
          إلى هنا خطوة بخطوة.
        </p>
      </div>
    </div>
  );
}
