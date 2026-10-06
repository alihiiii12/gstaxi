# تتبع الرحلات (Trip Trace) — لوحة التحكم

**مصدر الباكند المعتمد للرفع:** `C:\xampp\htdocs\SyriaTaxi-main\`

تم نسخ الملفات هناك. هذا المجلد مرآة للمساعدة فقط.

## ملفات الرفع من XAMPP

| الملف |
|-------|
| `app/Services/TripTraceService.php` |
| `database/migrations/2026_08_27_140000_add_trip_trace_fields_to_requests.php` |
| `app/Http/Controllers/RequestController.php` |
| `app/Http/Controllers/AdminOverviewController.php` |
| `app/Models/RequestModel.php` |
| `app/Models/RequestHistory.php` |

```bash
php artisan migrate --force
php artisan optimize:clear
```

لوحة الأدمن: ارفع `syriataxi/admin-web/dist/*` → `public/admin/`
