# إعلانات واتساب للزبائن (UltraMsg) — نشر

## الملفات الجديدة/المحدَّثة
- `app/Services/UltraMsgWhatsAppService.php` — نص + صورة + مستند
- `app/Services/CustomerWhatsAppBroadcastService.php`
- `app/Http\Controllers/Admin/WhatsAppBroadcastController.php`
- `routes/api.php`
- لوحة الأدمن: `public/admin/` (من `admin-web/dist`)

## على السيرفر
```bash
cd /var/www/syriataxi-api   # أو مسار المشروع
php artisan storage:link
php artisan config:cache
php artisan route:cache
```

تأكد أن `APP_URL=https://gstaxi.online` حتى يصل UltraMsg لروابط الصور/الملفات العامة تحت `/storage/...`.

UltraMsg في `.env`:
```
ULTRAMSG_INSTANCE_ID=...
ULTRAMSG_TOKEN=...
```

## ملف APK كبير (خطأ 413)

nginx يرفض الرفع إن تجاوز `client_max_body_size`. للـ APK (~80MB+):

**الأفضل:** ارفع الملف يدوياً ثم ضع رابطه في الحقل «رابط ملف عام»:
```bash
mkdir -p /var/www/syriataxi-api/public/downloads
# انسخ gstaxi.apk إلى public/downloads/
# الرابط: https://gstaxi.online/downloads/gstaxi.apk
```

**أو** زد حد nginx (اختياري):
```nginx
client_max_body_size 100m;
```
ثم `nginx -t && systemctl reload nginx`

وفي PHP (`php.ini` أو pool):
```
upload_max_filesize = 100M
post_max_size = 100M
```

## الاستخدام
القائمة → **إعلانات واتساب للزبائن**
- نص و/أو رابط ملف عام (مستحسن للـ APK) أو مرفق صغير
- **الكل** أو **تحديد مشتركين** (بحث + تحديد الصفحة)
- فلتر المؤكَّدين فقط
