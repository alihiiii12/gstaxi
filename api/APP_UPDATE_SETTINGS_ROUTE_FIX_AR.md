# إصلاح «route api/admin/app-update-settings could not be found»

ارفع هذه الملفات إلى مجلد الـ API على السيرفر (استبدل القديمة):

1. `routes/api.php`
2. `app/Http/Controllers/Admin/WhatsAppBroadcastController.php`
3. `app/Services/AppUpdatePolicy.php`
4. `app/Console/Commands/AppUpdateGateCommand.php`  (اختياري لكن مفيد)

ثم على السيرفر من مجلد المشروع:

```bash
php artisan route:clear
php artisan config:clear
php artisan cache:clear
```

**فتح الدخول فوراً بدون لوحة التحكم:**

```bash
php artisan app:update-gate --allow
```

بعدها حدّث صفحة الأدمن (Ctrl+F5) وجرّب «حفظ إعدادات التحديث» من جديد.
